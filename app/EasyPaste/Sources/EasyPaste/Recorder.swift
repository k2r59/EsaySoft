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
    var webcam = false
    var microphoneID = ""
    var cameraID = ""
    var fullResolution = true
    static func dimensions(_ size: CGSize, scale: CGFloat, fullResolution: Bool) -> (Int, Int) {
        guard size.width.isFinite, size.height.isFinite, scale.isFinite, size.width > 0, size.height > 0, scale > 0 else { return (2, 2) }
        let longest = max(size.width * scale, size.height * scale)
        guard longest.isFinite else { return (2, 2) }
        let ratio = min(1, (fullResolution ? 3840.0 : 1920.0) / max(1, longest))
        return (max(2, Int(size.width * scale * ratio) / 2 * 2), max(2, Int(size.height * scale * ratio) / 2 * 2))
    }
}

@MainActor final class Recorder: NSObject, SCStreamDelegate {
    enum State { case idle, starting, recording, stopping }
    private(set) var state: State = .idle
    private var stream: SCStream?
    private var writer: RecordingWriter?
    private var deadline: Task<Void, Never>?
    var onStart: (() -> Void)?
    var onStopping: (() -> Void)?
    var onFinish: ((Result<URL, Error>) -> Void)?
    func start(display: SCDisplay, area: CGRect, content: SCShareableContent, options: RecordingOptions, cameraWindow: CGWindowID? = nil) async throws {
        guard state == .idle else { throw CaptureFailure.message("Un enregistrement est déjà en cours.") }
        state = .starting
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyPaste/Recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            guard available > 2_500_000_000 else { throw CaptureFailure.message("Libère au moins 2,5 Go pour enregistrer une vidéo.") }
            let destination = folder.appendingPathComponent("EasyPaste-" + UUID().uuidString + ".mp4")
            let included = content.windows.filter { $0.windowID == cameraWindow }
            if options.webcam && included.isEmpty { throw CaptureFailure.message("L’aperçu de la webcam n’est pas prêt. Relance l’enregistrement.") }
            let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }, exceptingWindows: included)
            let configuration = SCStreamConfiguration()
            let local = try CaptureImage.pixelAligned(CGRect(x: area.minX - display.frame.minX, y: area.minY - display.frame.minY, width: area.width, height: area.height), scale: CGFloat(filter.pointPixelScale))
            configuration.sourceRect = local.intersection(CGRect(origin: .zero, size: display.frame.size))
            guard !configuration.sourceRect.isEmpty else { throw CaptureFailure.message("La zone vidéo est en dehors de l’écran.") }
            let dimensions = RecordingOptions.dimensions(configuration.sourceRect.size, scale: CGFloat(filter.pointPixelScale), fullResolution: options.fullResolution)
            configuration.width = dimensions.0; configuration.height = dimensions.1
            configuration.captureResolution = .best; configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.queueDepth = 5; configuration.showsCursor = true
            configuration.capturesAudio = options.systemAudio; configuration.excludesCurrentProcessAudio = true
            configuration.captureMicrophone = options.microphone
            if !options.microphoneID.isEmpty { configuration.microphoneCaptureDeviceID = options.microphoneID }
            configuration.sampleRate = 48000; configuration.channelCount = 2
            let writer = try RecordingWriter(url: destination, width: dimensions.0, height: dimensions.1, systemAudio: options.systemAudio, microphone: options.microphone)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            self.stream = stream; self.writer = writer
            writer.onFirstFrame = { [weak self, weak writer] in Task { @MainActor in
                guard let self, self.writer === writer, self.state == .starting else { return }
                self.deadline?.cancel(); self.state = .recording; self.onStart?()
            } }
            writer.onFailure = { [weak self, weak writer] error in Task { @MainActor in
                guard let self, self.writer === writer else { return }; self.abort(error)
            } }
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            if options.systemAudio { try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue) }
            if options.microphone { try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: writer.queue) }
            armTimeout(seconds: 15, message: "Aucune image reçue. Vérifie l’autorisation d’écran puis réessaie.")
            try await stream.startCapture()
            if self.stream !== stream || state == .idle { try? await stream.stopCapture(); writer.cancel(removeFile: true) }
        } catch { writer?.cancel(removeFile: true); reset(); throw error }
    }
    func cancel() {
        let stream = stream; writer?.cancel(removeFile: true); reset()
        Task { try? await stream?.stopCapture() }
    }
    func stop() {
        guard state == .recording || state == .starting, let stream, let writer else { return }
        let stopped = CMClockGetTime(CMClockGetHostTimeClock())
        state = .stopping; onStopping?()
        armTimeout(seconds: 90, message: "La finalisation de la vidéo a pris trop de temps. Le fichier de récupération reste dans EasyPaste/Recordings.")
        Task {
            do {
                try await stream.stopCapture()
                let url = try await writer.finish(at: stopped)
                guard self.writer === writer else { return }
                finish(.success(url))
            } catch { if self.writer === writer { writer.cancel(); finish(.failure(error)) } }
        }
    }
    func checkSize() {
        guard state == .recording, let writer else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: writer.url.path)[.size] as? NSNumber)?.int64Value ?? 0
        let available = (try? writer.url.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        if size >= 800_000_000 || available < 1_100_000_000 { stop() }
    }
    private func armTimeout(seconds: Double, message: String) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard let self, self.state != .idle else { return }
            self.abort(CaptureFailure.message(message))
        }
    }
    private func reset() { deadline?.cancel(); deadline = nil; stream = nil; writer = nil; state = .idle }
    private func finish(_ result: Result<URL, Error>) { guard state != .idle else { return }; reset(); onFinish?(result) }
    private func abort(_ error: Error) {
        let stream = stream; writer?.cancel(); finish(.failure(error))
        Task { try? await stream?.stopCapture() }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in guard self.stream === stream, self.state != .stopping else { return }; self.abort(error) }
    }
}
