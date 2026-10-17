import AppKit
import ScreenCaptureKit
import AVFoundation

enum CaptureFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
struct RecordingOptions {
    var area = true
    var systemAudio = false
    var microphone = false
    var fullResolution = false
    static func dimensions(_ size: CGSize, scale: CGFloat, fullResolution: Bool) -> (Int, Int) {
        let longest = max(size.width * scale, size.height * scale)
        let ratio = min(1, (fullResolution ? 3840.0 : 1920.0) / max(1, longest))
        return (max(2, Int(size.width * scale * ratio) / 2 * 2), max(2, Int(size.height * scale * ratio) / 2 * 2))
    }
}

@MainActor final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    enum State { case idle, starting, recording, stopping }
    private(set) var state: State = .idle
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var url: URL?
    private var deadline: Task<Void, Never>?
    var onStart: (() -> Void)?
    var onFinish: ((Result<URL, Error>) -> Void)?
    func start(display: SCDisplay, area: CGRect, content: SCShareableContent, options: RecordingOptions) async throws {
        guard state == .idle else { throw CaptureFailure.message("Un enregistrement est déjà en cours.") }
        state = .starting
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyPaste/Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard available > 1_500_000_000 else { throw CaptureFailure.message("Libère au moins 1,5 Go pour enregistrer une vidéo.") }
            let destination = folder.appendingPathComponent("EasyPaste-" + UUID().uuidString + ".mp4")
            url = destination
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY, width: area.width, height: area.height)
            let dimensions = RecordingOptions.dimensions(area.size, scale: CaptureImage.nativeScale(display.displayID), fullResolution: options.fullResolution)
            configuration.width = dimensions.0; configuration.height = dimensions.1
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 3; configuration.showsCursor = true
            configuration.capturesAudio = options.systemAudio; configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = options.microphone
            configuration.sampleRate = 48000; configuration.channelCount = 2
            let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }, exceptingWindows: [])
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            let config = SCRecordingOutputConfiguration(); config.outputURL = destination
            config.outputFileType = .mp4; config.videoCodecType = .h264
            let output = SCRecordingOutput(configuration: config, delegate: self)
            self.stream = stream; self.output = output
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            // Some failures arrive only through the delegate. Bound a missing start callback.
            if state == .starting { armTimeout(seconds: 15, message: "L’enregistrement n’a pas démarré. Vérifie l’autorisation d’écran.") }
        } catch { reset(); throw error }
    }
    func stop() {
        guard state == .recording || state == .starting, let stream else { return }
        state = .stopping; armTimeout(seconds: 30, message: "La finalisation de la vidéo a pris trop de temps. Le fichier de récupération est conservé dans EasyPaste/Recordings.")
        Task { do { try await stream.stopCapture() } catch { if self.state != .idle { self.finish(.failure(error)) } } }
    }
    func checkSize() {
        guard state == .recording, let output else { return }
        if output.recordedFileSize >= 800_000_000 { stop() }
    }
    private func armTimeout(seconds: Double, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.state != .idle else { return }
            let stream = self.stream
            self.finish(.failure(CaptureFailure.message(message)))
            try? await stream?.stopCapture()
        }
    }
    private func reset() { deadline?.cancel(); deadline = nil; stream = nil; output = nil; url = nil; state = .idle }
    private func finish(_ result: Result<URL, Error>) {
        guard state != .idle else { return }
        reset(); onFinish?(result)
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard self.output === recordingOutput, self.state == .starting else { return }
            self.deadline?.cancel(); self.state = .recording; self.onStart?()
        }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            guard self.output === recordingOutput, let url = self.url else { return }
            self.finish(.success(url))
        }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.output === recordingOutput else { return }
            let stream = self.stream; self.finish(.failure(error)); try? await stream?.stopCapture()
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream, self.state != .stopping else { return }
            self.finish(.failure(error))
        }
    }
}
