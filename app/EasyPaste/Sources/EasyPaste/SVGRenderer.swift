import AppKit
import Darwin

enum SVGRenderer {
    struct Request: Codable { let source: String; let maxPixels: Int }
    static let outputLimit = 20_000_000
    static func render(_ document: SVGDocument, maxPixels: Int = 2048, executable: URL? = nil) async throws -> Data {
        let box = RenderProcess()
        let request = try JSONEncoder().encode(Request(source: document.canonical, maxPixels: max(1, min(2048, maxPixels))))
        guard let executable = executable ?? Bundle.main.executableURL else { throw TextIssue(message: "Moteur SVG indisponible.") }
        let worker = Task.detached(priority: .userInitiated) { try box.run(executable: executable, input: request) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { box.stop(); worker.cancel() })
    }
    /// Invoked before normal app initialization. The child receives only a bounded
    /// document and returns PNG bytes; it never opens the clipboard or history.
    static func runHelper() {
        var cpu = rlimit(rlim_cur: 4, rlim_max: 5); _ = setrlimit(RLIMIT_CPU, &cpu)
        do {
            var data = Data()
            while let chunk = try FileHandle.standardInput.read(upToCount: 16 * 1024), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= 2 * 1024 * 1024 else { throw TextIssue(message: "Requête SVG trop grande.") }
            }
            let request = try JSONDecoder().decode(Request.self, from: data)
            let document = try SVGDocument.parse(request.source)
            let png = try rasterize(document, maxPixels: max(1, min(2048, request.maxPixels)))
            try FileHandle.standardOutput.write(contentsOf: png)
        } catch { exit(2) }
    }
    static func rasterize(_ document: SVGDocument, maxPixels: Int) throws -> Data {
        let side = Double(max(1, min(2048, maxPixels))), longest = max(document.width, document.height)
        guard document.width > 0, document.height > 0, longest.isFinite else { throw TextIssue(message: "Dimensions SVG invalides.") }
        let width = max(1, Int((document.width / longest * side).rounded())), height = max(1, Int((document.height / longest * side).rounded()))
        guard let image = NSImage(data: Data(document.canonical.utf8)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmapContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw TextIssue(message: "Ce SVG ne peut pas être rendu.") }
        let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
        NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context; context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
        image.draw(in: CGRect(x: 0, y: 0, width: width, height: height), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        guard let raster = bitmapContext.makeImage(), let data = NSBitmapImageRep(cgImage: raster).representation(using: .png, properties: [:]), data.count <= outputLimit else { throw TextIssue(message: "Échec du rendu SVG.") }
        return data
    }
}

private final class RenderProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private var cancelled = false
    func stop() {
        lock.lock(); cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.lock.lock(); defer { self.lock.unlock() }
            if self.process.isRunning { kill(self.process.processIdentifier, SIGKILL) }
        }
    }
    func run(executable: URL, input: Data) throws -> Data {
        let stdin = Pipe(), stdout = Pipe()
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = executable; process.arguments = ["--render-svg"]
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled || Task.isCancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let deadline = DispatchWorkItem { [weak self] in self?.stop() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6, execute: deadline)
        defer { deadline.cancel(); try? stdin.fileHandleForWriting.close(); try? stdout.fileHandleForReading.close(); if process.isRunning { stop() } }
        try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close()
        var result = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
            result.append(chunk)
            if result.count > SVGRenderer.outputLimit { stop(); throw TextIssue(message: "Image SVG trop grande.") }
        }
        process.waitUntilExit(); try Task.checkCancellation()
        guard process.terminationStatus == 0, !result.isEmpty else { throw TextIssue(message: "Rendu SVG interrompu ou indisponible. Le source est conservé.") }
        return result
    }
}
