import AVFoundation
import ScreenCaptureKit

/// One serial queue owns the encoder. At most one screen surface is retained;
/// busy inputs drop samples instead of building an unbounded queue of frames.
final class RecordingWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "EasyPaste.recording.writer", qos: .userInitiated)
    let url: URL
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private var audio: [SCStreamOutputType: AVAssetWriterInput] = [:]
    private var epoch: CMTime?
    private var latest: CVPixelBuffer?
    private var lastPTS = CMTime.invalid
    private var timer: DispatchSourceTimer?
    private var finishing = false
    private var failed = false
    private var audioTypes = Set<SCStreamOutputType>()
    var onFirstFrame: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    init(url: URL, width: Int, height: Int, systemAudio: Bool, microphone: Bool) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: min(48_000_000, max(3_000_000, width * height * 6)),
                AVVideoExpectedSourceFrameRateKey: 30, AVVideoMaxKeyFrameIntervalDurationKey: 1,
                AVVideoAllowFrameReorderingKey: false, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
        super.init()
        guard writer.canAdd(video) else { throw CaptureFailure.message("L’encodeur vidéo n’est pas disponible.") }
        writer.add(video)
        for (type, enabled, channels) in [(SCStreamOutputType.audio, systemAudio, 2), (.microphone, microphone, 1)] where enabled {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000, AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: channels * 96_000])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else { throw CaptureFailure.message("L’encodeur audio n’est pas disponible.") }
            writer.add(input); audio[type] = input
        }
        guard writer.startWriting() else { throw writer.error ?? CaptureFailure.message("Impossible de créer la vidéo.") }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finishing, !failed, sample.isValid else { return }
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
                  let pixel = sample.imageBuffer else { return }
            appendVideo(pixel, at: sample.presentationTimeStamp)
        } else { appendAudio(sample, type: type) }
    }
    /// Also exercised by fixtures: all calls must run on `queue`.
    func appendVideo(_ pixel: CVPixelBuffer, at time: CMTime) {
        guard !finishing, !failed, time.isNumeric else { return }
        latest = pixel
        if epoch == nil {
            epoch = time; writer.startSession(atSourceTime: .zero)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 0.2, repeating: 0.2, leeway: .milliseconds(25))
            timer.setEventHandler { [weak self] in self?.holdFrame() }
            self.timer = timer; timer.resume()
        }
        append(pixel, at: max(.zero, time - epoch!))
    }
    private func append(_ pixel: CVPixelBuffer, at time: CMTime) {
        guard writer.status == .writing, video.isReadyForMoreMediaData, !lastPTS.isNumeric || time > lastPTS else {
            if writer.status == .failed { fail(writer.error ?? CaptureFailure.message("L’écriture de la vidéo a échoué.")) }
            return
        }
        guard adaptor.append(pixel, withPresentationTime: time) else { fail(writer.error ?? CaptureFailure.message("Une image vidéo n’a pas pu être écrite.")); return }
        let first = !lastPTS.isNumeric
        lastPTS = time
        if first { onFirstFrame?() }
    }
    private func holdFrame() {
        guard !finishing, !failed, let latest, let epoch else { return }
        let time = CMClockGetTime(CMClockGetHostTimeClock()) - epoch
        // ScreenCaptureKit emits no new image for an unchanged screen. Keep a
        // sample alive so seeking anywhere in the movie never reaches a gap.
        if time.isNumeric, time - lastPTS >= CMTime(value: 1, timescale: 5) { append(latest, at: time) }
    }
    func appendAudio(_ sample: CMSampleBuffer, type: SCStreamOutputType) {
        guard !finishing, !failed, let epoch, let input = audio[type], input.isReadyForMoreMediaData else { return }
        guard let adjusted = Self.retime(sample, relativeTo: epoch) else { return }
        if input.append(adjusted) { audioTypes.insert(type) }
        else { fail(writer.error ?? CaptureFailure.message("L’écriture du son a échoué.")) }
    }
    static func retime(_ sample: CMSampleBuffer, relativeTo epoch: CMTime) -> CMSampleBuffer? {
        guard sample.presentationTimeStamp.isNumeric, sample.presentationTimeStamp >= epoch else { return nil }
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count) == noErr, count > 0 else { return nil }
        var timings = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timings, entriesNeededOut: nil) == noErr else { return nil }
        for i in timings.indices {
            timings[i].presentationTimeStamp = timings[i].presentationTimeStamp - epoch
            if timings[i].decodeTimeStamp.isNumeric { timings[i].decodeTimeStamp = timings[i].decodeTimeStamp - epoch }
        }
        var copy: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &copy) == noErr else { return nil }
        return copy
    }
    private func fail(_ error: Error) {
        guard !failed else { return }; failed = true; timer?.cancel(); timer = nil; onFailure?(error)
    }
    func cancel(removeFile: Bool = false) {
        queue.async { self.finishing = true; self.timer?.cancel(); self.timer = nil; self.latest = nil; self.writer.cancelWriting(); if removeFile { try? FileManager.default.removeItem(at: self.url) } }
    }
    func finish(at endTime: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.finishing else { continuation.resume(throwing: CaptureFailure.message("La vidéo est déjà en cours de finalisation.")); return }
                self.finishing = true; self.timer?.cancel(); self.timer = nil
                guard let epoch = self.epoch, self.lastPTS.isNumeric, !self.failed else {
                    self.writer.cancelWriting(); self.latest = nil
                    continuation.resume(throwing: self.writer.error ?? CaptureFailure.message("Aucune image vidéo n’a été reçue. Vérifie l’autorisation d’écran.")); return
                }
                let end = max(self.lastPTS + CMTime(value: 1, timescale: 30), endTime - epoch)
                self.finishLastFrame(end: end, attempts: 100, continuation: continuation)
            }
        }
    }
    private func finishLastFrame(end: CMTime, attempts: Int, continuation: CheckedContinuation<URL, Error>) {
        guard writer.status == .writing, !failed else {
            latest = nil; continuation.resume(throwing: writer.error ?? CaptureFailure.message("La finalisation de la vidéo a échoué.")); return
        }
        if !video.isReadyForMoreMediaData && attempts > 0 {
            queue.asyncAfter(deadline: .now() + 0.02) { self.finishLastFrame(end: end, attempts: attempts - 1, continuation: continuation) }; return
        }
        guard video.isReadyForMoreMediaData else {
            writer.cancelWriting(); latest = nil; continuation.resume(throwing: CaptureFailure.message("L’encodeur vidéo ne répond plus.")); return
        }
        if let latest { append(latest, at: max(lastPTS + CMTime(value: 1, timescale: 600), end - CMTime(value: 1, timescale: 30))) }
        latest = nil; writer.endSession(atSourceTime: end)
        video.markAsFinished(); audio.values.forEach { $0.markAsFinished() }
        let needsMix = audioTypes.count > 1
        writer.finishWriting { [self] in
            guard writer.status == .completed else { continuation.resume(throwing: writer.error ?? CaptureFailure.message("La vidéo n’a pas été finalisée.")); return }
            Task {
                do { continuation.resume(returning: needsMix ? try await RecordingAudioMix.merge(url) : url) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
}

/// Mix only the audio when both sources are enabled, then remux the original
/// H.264 frames unchanged. No second video encoder or large frame array.
enum RecordingAudioMix {
    static func merge(_ source: URL) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1 else { return source }
        let temporary = source.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".m4a")
        let result = source.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            let audioComposition = AVMutableComposition(), mix = AVMutableAudioMix()
            var parameters: [AVAudioMixInputParameters] = []
            for track in audioTracks {
                let range = try await track.load(.timeRange)
                guard let copy = audioComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CaptureFailure.message("Impossible de réunir le micro et le son de l’ordinateur.") }
                try copy.insertTimeRange(range, of: track, at: range.start)
                let parameter = AVMutableAudioMixInputParameters(track: copy); parameter.setVolume(0.7, at: .zero); parameters.append(parameter)
            }
            mix.inputParameters = parameters
            guard let audioExport = AVAssetExportSession(asset: audioComposition, presetName: AVAssetExportPresetAppleM4A) else { throw CaptureFailure.message("Le mixage audio n’est pas disponible.") }
            audioExport.audioMix = mix; try await audioExport.export(to: temporary, as: .m4a)
            let composition = AVMutableComposition()
            let mixed = AVURLAsset(url: temporary)
            for track in try await asset.loadTracks(withMediaType: .video) + mixed.loadTracks(withMediaType: .audio) {
                let range = try await track.load(.timeRange)
                guard let copy = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw CaptureFailure.message("Impossible de réunir l’image et le son.") }
                try copy.insertTimeRange(range, of: track, at: range.start)
                if track.mediaType == .video { copy.preferredTransform = try await track.load(.preferredTransform) }
            }
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else { throw CaptureFailure.message("La vidéo ne peut pas être finalisée.") }
            try await export.export(to: result, as: .mp4)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: result.path)
            try FileManager.default.removeItem(at: source)
            return result
        } catch { try? FileManager.default.removeItem(at: result); throw error }
    }
}
