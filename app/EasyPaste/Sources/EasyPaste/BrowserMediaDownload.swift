import AppKit
import SwiftUI
import Darwin

struct BrowserMediaRequest: Codable, Identifiable {
    let id: UUID
    let url: String
    let mode: String
    let generation: String?
    let created: Date
    var quality: String? = nil
    static let notification = Notification.Name("app.easypaste.web.media-request")
    static func validated(_ data: Data, origin: String) throws -> (url: String, mode: String, nonce: String, quality: String?) {
        guard data.count <= BrowserBridgeProtocol.maximumMessage,
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).subtracting(["quality"]) == Set(["protocol", "type", "nonce", "extensionVersion", "url", "mode"]),
              object["type"] as? String == "media", let raw = object.removeValue(forKey: "url") as? String,
              let mode = object.removeValue(forKey: "mode") as? String, ["video", "audio"].contains(mode),
              let url = webURL(raw), let nonce = object["nonce"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        let quality = object.removeValue(forKey: "quality")
        guard quality == nil || ["best", "1080", "720", "480"].contains(quality as? String ?? "") else { throw CocoaError(.fileReadCorruptFile) }
        object["type"] = "hello"
        _ = try BrowserBridgeProtocol.response(JSONSerialization.data(withJSONObject: object), origin: origin, enabled: true, version: "0.3.13")
        return (url.absoluteString, mode, nonce, quality as? String)
    }
    static func webURL(_ raw: String) -> URL? {
        guard raw.utf8.count <= 2048, !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }),
              let url = URL(string: raw), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased(), !host.isEmpty,
              host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
              host != "[::1]", host != "::1", !host.hasPrefix("127."), !host.hasPrefix("10."),
              !host.hasPrefix("192.168."), !host.hasPrefix("169.254."), host != "0.0.0.0" else { return nil }
        if host.hasPrefix("172."), let second = host.split(separator: ".").dropFirst().first.flatMap({ Int($0) }), (16...31).contains(second) { return nil }
        return url
    }
    static func folder(root: URL) -> URL { root.appendingPathComponent("MediaRequests", isDirectory: true) }
    static func enqueue(url: String, mode: String, config: BrowserBridgeConfiguration, root: URL, quality: String? = nil) throws -> URL {
        guard config.enabled, webURL(url) != nil, ["video", "audio"].contains(mode) else { throw CocoaError(.fileReadNoPermission) }
        let directory = folder(root: root)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard files.filter({ $0.pathExtension == "json" }).count < 20 else { throw TextIssue(message: "Trop de demandes en attente. Ouvre Téléchargements web dans EasyPaste.") }
        let request = BrowserMediaRequest(id: UUID(), url: url, mode: mode, generation: config.generation, created: Date(), quality: quality)
        let file = directory.appendingPathComponent(request.id.uuidString + ".json")
        try BrowserExtensionFiles.write(request, to: file)
        return file
    }
}

// Small, expiring status records expose only the requested job, never paths or history.
struct BrowserMediaStatus: Codable {
    let id: UUID
    let generation: String?
    let state: String
    let message: String
    let updated: Date
    static func file(_ id: UUID, root: URL) -> URL { root.appendingPathComponent("MediaStatus").appendingPathComponent(id.uuidString + ".json") }
    static func save(_ id: UUID, generation: String?, state: String, message: String, root: URL) {
        try? BrowserExtensionFiles.write(Self(id: id, generation: generation, state: state, message: String(message.prefix(240)), updated: Date()), to: file(id, root: root))
    }
    static func reply(_ data: Data, origin: String, config: BrowserBridgeConfiguration?, root: URL) throws -> Data {
        guard data.count <= BrowserBridgeProtocol.maximumMessage,
              var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["protocol", "type", "nonce", "extensionVersion", "jobID"]),
              object["type"] as? String == "mediaStatus", let raw = object.removeValue(forKey: "jobID") as? String,
              let id = UUID(uuidString: raw), let nonce = object["nonce"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        object["type"] = "hello"
        _ = try BrowserBridgeProtocol.response(JSONSerialization.data(withJSONObject: object), origin: origin, enabled: true, version: "0.3.14")
        var state = "unknown", message = "Suivi indisponible. Vérifie les téléchargements dans EasyPaste."
        if let config, config.enabled,
           let record = BrowserExtensionFiles.read(Self.self, from: file(id, root: root)), record.id == id,
           record.generation == config.generation, abs(record.updated.timeIntervalSinceNow) < 86400 {
            state = record.state; message = record.message
            if ["queued", "preparing", "downloading"].contains(state), record.updated.timeIntervalSinceNow < -1900 {
                state = "unknown"; message = "Le suivi a été interrompu. Vérifie les téléchargements dans EasyPaste."
            }
        }
        return try JSONSerialization.data(withJSONObject: ["protocol": 1, "type": "mediaStatus", "nonce": nonce, "jobID": id.uuidString, "status": state, "message": message])
    }
}

// The same yt-dlp / FFmpeg / Node tools used by EasyMusic, without shell commands,
// account-cookie imports, user yt-dlp configuration, or arbitrary executable paths.
enum BrowserMediaEngine {
    static func executable(_ name: String, bundle: Bundle = .main) -> URL? {
        let nested = name == "yt-dlp" ? "yt-dlp-runtime/yt-dlp_macos" : name
        let resources = [bundle.resourceURL,
                         URL(fileURLWithPath: "/Applications/EasyMusic.app/Contents/Resources"),
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/EasyMusic.app/Contents/Resources")]
        let paths = resources.compactMap { $0?.appendingPathComponent("bin/" + nested) }
            + ["/opt/homebrew/bin/", "/usr/local/bin/"].map { URL(fileURLWithPath: $0 + name) }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    static var available: Bool { executable("yt-dlp") != nil && executable("ffmpeg") != nil }
    static func arguments(url: String, mode: String?, output: URL? = nil, quality: String? = nil) throws -> [String] {
        guard BrowserMediaRequest.webURL(url) != nil else { throw TextIssue(message: "Cette adresse de média n’est pas prise en charge.") }
        var args = ["--ignore-config", "--no-playlist", "--playlist-items", "1", "--no-colors", "--socket-timeout", "15", "--retries", "1", "--fragment-retries", "1", "--no-cache-dir", "--no-overwrites", "--newline", "--no-progress"]
        if let node = executable("node") { args += ["--js-runtimes", "node:" + node.path] }
        if let ffmpeg = executable("ffmpeg") { args += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path] }
        if let mode, let output {
            guard ["video", "audio"].contains(mode) else { throw TextIssue(message: "Format de téléchargement inconnu.") }
            args += ["--max-filesize", "2G", "--no-simulate", "--restrict-filenames", "-o", output.appendingPathComponent("media.%(ext)s").path]
            if mode == "audio" { args += ["-f", "bestaudio/best", "-x", "--audio-format", "mp3", "--audio-quality", "0"] }
            else {
                let chosen = quality ?? "1080"
                guard ["best", "1080", "720", "480"].contains(chosen) else { throw TextIssue(message: "Qualité vidéo inconnue.") }
                let format = chosen == "best" ? "bv*+ba/b" : "bv*[height<=?\(chosen)]+ba/b[height<=?\(chosen)]"
                args += ["-f", format, "--merge-output-format", "mp4", "--remux-video", "mp4"]
            }
        } else { args += ["--skip-download", "--dump-single-json"] }
        return args + ["--", url]
    }
    static func metadata(_ output: String, mode: String) throws -> String {
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix("{") }),
              let data = line.data(using: .utf8), let info = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TextIssue(message: "Aucun média exploitable trouvé sur cette page.") }
        guard info["_type"] as? String != "playlist", info["entries"] == nil else { throw TextIssue(message: "Cette page contient une liste. Ouvre un média précis ou choisis son flux dans l’extension.") }
        guard info["has_drm"] as? Bool != true else { throw TextIssue(message: "Ce média est protégé et ne peut pas être téléchargé.") }
        guard info["is_live"] as? Bool != true, info["live_status"] as? String != "is_live" else { throw TextIssue(message: "Ce flux est en direct. Réessaie lorsque l’enregistrement est terminé.") }
        let formats = info["formats"] as? [[String: Any]] ?? [info]
        let key = mode == "audio" ? "acodec" : "vcodec"
        guard formats.contains(where: { format in
            guard format["has_drm"] as? Bool != true else { return false }
            if let codec = format[key] as? String { return codec != "none" && !codec.isEmpty }
            // Generic direct files often have no codec metadata until FFmpeg reads them.
            let extensions = mode == "video" ? ["mp4", "webm", "mov", "mkv", "m3u8"] : ["mp3", "m4a", "aac", "wav", "ogg", "opus", "mp4", "webm", "mov", "mkv", "m3u8"]
            return extensions.contains(format["ext"] as? String ?? "")
        }) else { throw TextIssue(message: mode == "audio" ? "Aucune piste audio accessible dans ce média." : "Aucune piste vidéo accessible dans ce média.") }
        return String((info["title"] as? String ?? "Média web").prefix(180))
    }
    static func run(_ args: [String], timeout: TimeInterval, executable: URL? = nil) async throws -> String {
        guard let executable = executable ?? self.executable("yt-dlp") else { throw TextIssue(message: "Le moteur yt-dlp est absent. Installe EasyMusic ou yt-dlp avec FFmpeg sur ce Mac.") }
        let runner = BrowserMediaProcess()
        let worker = Task.detached(priority: .utility) { try runner.run(executable: executable, args: args, timeout: timeout) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { runner.stop(); worker.cancel() })
    }
}

private final class BrowserMediaProcess: @unchecked Sendable {
    private let lock = NSLock(), process = Process()
    private var cancelled = false
    func stop() {
        lock.lock(); cancelled = true
        if process.isRunning { process.interrupt() }
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            lock.lock(); defer { lock.unlock() }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    func run(executable: URL, args: [String], timeout: TimeInterval) throws -> String {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("easypaste-media-" + UUID().uuidString)
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
        process.executableURL = executable; process.arguments = args
        process.standardInput = FileHandle.nullDevice; process.standardOutput = handle; process.standardError = handle
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env
        lock.lock()
        if cancelled || Task.isCancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled { stop(); process.waitUntilExit(); throw CancellationError() }
            if Date() > deadline { stop(); process.waitUntilExit(); throw TextIssue(message: "Le média met trop de temps à répondre. Réessaie plus tard.") }
            let size = (try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 8_000_000 { stop(); process.waitUntilExit(); throw TextIssue(message: "La réponse du moteur dépasse la limite autorisée.") }
            Thread.sleep(forTimeInterval: 0.15)
        }
        process.waitUntilExit(); try Task.checkCancellation()
        guard (try log.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_000_000 else { throw TextIssue(message: "La réponse du moteur est trop volumineuse.") }
        let data = try Data(contentsOf: log)
        guard data.count <= 8_000_000 else { throw TextIssue(message: "La réponse du moteur est trop volumineuse.") }
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            // Do not surface tokens, signed media URLs or file paths from stderr.
            if output.localizedCaseInsensitiveContains("does not contain any stream") || output.localizedCaseInsensitiveContains("audio codec with ffprobe") { throw TextIssue(message: "Ce média ne contient pas de piste audio exploitable.") }
            if output.localizedCaseInsensitiveContains("requested format is not available") { throw TextIssue(message: "Le format demandé n’est pas disponible pour ce média.") }
            if output.localizedCaseInsensitiveContains("unsupported url") { throw TextIssue(message: "Ce site n’est pas pris en charge. Essaie un flux vidéo ou audio détecté dans l’extension.") }
            if output.localizedCaseInsensitiveContains("sign in") || output.contains("403") || output.contains("401") { throw TextIssue(message: "La source exige une connexion ou refuse l’accès. Les cookies du navigateur ne sont pas transmis.") }
            throw TextIssue(message: "Le site n’a pas permis le téléchargement. Réessaie avec un flux détecté ou vérifie que le moteur yt-dlp est à jour.")
        }
        return output
    }
}

@MainActor final class BrowserMediaDownloads: ObservableObject {
    struct Job: Identifiable {
        let id: UUID, mode: String
        var title: String, status: String, active = true
        var file: URL?
    }
    @Published private(set) var jobs: [Job] = []
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var waiting: [BrowserMediaRequest] = []
    private var generations: [UUID: String] = [:]
    private var observer: NSObjectProtocol?
    private var window: NSWindow?
    private let root: URL
    private let destinationRoot: URL
    private let revealOnRequest: Bool
    private let runner: @Sendable ([String], TimeInterval) async throws -> String
    private let toolsAvailable: () -> Bool
    init(root: URL = BrowserExtensionFiles.root, destinationRoot: URL? = nil, revealOnRequest: Bool = true,
         runner: @escaping @Sendable ([String], TimeInterval) async throws -> String = { args, timeout in try await BrowserMediaEngine.run(args, timeout: timeout) },
         toolsAvailable: @escaping () -> Bool = { BrowserMediaEngine.available }) {
        self.root = root
        self.destinationRoot = destinationRoot ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyPaste", isDirectory: true)
        self.revealOnRequest = revealOnRequest; self.runner = runner; self.toolsAvailable = toolsAvailable
    }
    var active: Bool { jobs.contains(where: \.active) }
    func start() {
        observer = DistributedNotificationCenter.default().addObserver(forName: BrowserMediaRequest.notification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.consume() } }
        consume()
    }
    func consume() {
        let config = BrowserExtensionFiles.read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))
        let files = ((try? FileManager.default.contentsOfDirectory(at: BrowserMediaRequest.folder(root: root), includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "json" }.prefix(20)
        for file in files {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let request = BrowserExtensionFiles.read(BrowserMediaRequest.self, from: file), config?.enabled == true,
                  request.generation == config?.generation, abs(request.created.timeIntervalSinceNow) < 300,
                  BrowserMediaRequest.webURL(request.url) != nil, ["video", "audio"].contains(request.mode), !jobs.contains(where: { $0.id == request.id }) else { continue }
            let id = request.id
            jobs.append(Job(id: id, mode: request.mode, title: URL(string: request.url)?.host ?? "Média web", status: "En attente…"))
            generations[id] = request.generation
            BrowserMediaStatus.save(id, generation: request.generation, state: "queued", message: "En attente…", root: root)
            if revealOnRequest { show(activate: false) }
            waiting.append(request)
        }
        pump()
    }
    private func pump() {
        while tasks.count < 2, !waiting.isEmpty {
            let request = waiting.removeFirst()
            tasks[request.id] = Task { [weak self] in await self?.download(request) }
        }
    }
    private func update(_ id: UUID, title: String? = nil, status: String, active: Bool = true, file: URL? = nil, state: String? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if let title { jobs[index].title = title }
        jobs[index].status = status; jobs[index].active = active; jobs[index].file = file
        BrowserMediaStatus.save(id, generation: generations[id], state: state ?? (active ? "downloading" : file != nil ? "completed" : "error"), message: status, root: root)
    }
    private func download(_ request: BrowserMediaRequest) async {
        var destination: URL?
        defer { tasks[request.id] = nil; pump() }
        update(request.id, status: "Analyse de la source…", state: "preparing")
        do {
            guard toolsAvailable() else { throw TextIssue(message: "Moteur absent : installe EasyMusic, ou yt-dlp et FFmpeg, puis relance le téléchargement.") }
            let metadata = try await runner(BrowserMediaEngine.arguments(url: request.url, mode: nil), 90)
            let title = try BrowserMediaEngine.metadata(metadata, mode: request.mode)
            try Task.checkCancellation()
            let folder = destinationRoot.appendingPathComponent(request.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            destination = folder
            update(request.id, title: title, status: request.mode == "audio" ? "Téléchargement et conversion en MP3…" : "Téléchargement et assemblage en MP4…")
            _ = try await runner(BrowserMediaEngine.arguments(url: request.url, mode: request.mode, output: folder, quality: request.quality), 1800)
            try Task.checkCancellation()
            let expected = folder.appendingPathComponent(request.mode == "audio" ? "media.mp3" : "media.mp4")
            let values = try expected.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else { throw TextIssue(message: "Le moteur n’a pas produit le fichier attendu.") }
            update(request.id, status: "Enregistré dans Téléchargements/EasyPaste", active: false, file: expected)
        } catch {
            if let destination { try? FileManager.default.removeItem(at: destination) }
            update(request.id, status: error is CancellationError ? "Téléchargement annulé." : error.localizedDescription, active: false, state: error is CancellationError ? "cancelled" : "error")
        }
    }
    func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) { waiting.remove(at: index); update(id, status: "Téléchargement annulé.", active: false, state: "cancelled") }
        tasks[id]?.cancel()
    }
    func shutdown() async { for request in waiting { update(request.id, status: "Téléchargement annulé.", active: false, state: "cancelled") }; waiting = []; let running = Array(tasks.values); running.forEach { $0.cancel() }; for task in running { await task.value } }
    func show(activate: Bool = true) {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            panel.title = "Téléchargements web"; panel.isOpaque = false; panel.backgroundColor = .clear; panel.titlebarAppearsTransparent = true; panel.isReleasedWhenClosed = false; panel.minSize = NSSize(width: 500, height: 320)
            panel.contentView = NSHostingView(rootView: BrowserMediaDownloadsView(model: self)); panel.center(); window = panel
        }
        if activate { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { window?.orderFront(nil) }
    }
}
struct BrowserMediaDownloadsView: View {
    @ObservedObject var model: BrowserMediaDownloads
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Téléchargements web").font(.title2.bold())
            Text("Vidéo MP4 · Audio MP3 · via yt-dlp").font(.callout).foregroundStyle(Theme.muted)
            if model.jobs.isEmpty { Text("Lance un téléchargement depuis l’extension EasyPaste · Web.").foregroundStyle(Theme.muted); Spacer() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.jobs) { job in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: job.mode == "audio" ? "music.note" : "video")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(job.title).fontWeight(.semibold).lineLimit(2)
                                    Text(job.status).font(.callout).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                    if job.active { ProgressView().controlSize(.small) }
                                }
                                Spacer()
                                if job.active { Button("Annuler") { model.cancel(job.id) }.buttonStyle(PasteButtonStyle()) }
                                if let file = job.file { Button("Afficher") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(PasteButtonStyle(primary: true)) }
                            }.padding(14).surface()
                        }
                    }
                }
            }
        }.padding(24).foregroundStyle(Theme.ink).chromeSurface(radius: 16)
    }
}

enum BrowserMediaBridge {
    static func accept(_ data: Data, origin: String, config: BrowserBridgeConfiguration?, root: URL, launch: () throws -> Void) throws -> Data {
        let request = try BrowserMediaRequest.validated(data, origin: origin)
        var response: [String: Any] = ["protocol": 1, "type": "media", "nonce": request.nonce, "status": "disabled"]
        if let config, config.enabled {
            var queued: URL?
            do {
                queued = try BrowserMediaRequest.enqueue(url: request.url, mode: request.mode, config: config, root: root, quality: request.quality)
                if let queued, let id = UUID(uuidString: queued.deletingPathExtension().lastPathComponent) {
                    let directory = BrowserMediaStatus.file(id, root: root).deletingLastPathComponent()
                    let old = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                    for file in old where file.pathExtension == "json" {
                        if let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date.timeIntervalSinceNow < -86400 { try? FileManager.default.removeItem(at: file) }
                    }
                    BrowserMediaStatus.save(id, generation: config.generation, state: "queued", message: "Demande reçue par EasyPaste.", root: root)
                    response["jobID"] = id.uuidString
                }
                try launch()
                response["status"] = "queued"
            } catch {
                if let queued { try? FileManager.default.removeItem(at: queued) }
                if let queued, let id = UUID(uuidString: queued.deletingPathExtension().lastPathComponent) { try? FileManager.default.removeItem(at: BrowserMediaStatus.file(id, root: root)) }
                response.removeValue(forKey: "jobID")
                response["status"] = "error"
                response["message"] = "Impossible de transmettre le téléchargement. Ouvre EasyPaste, vérifie sa connexion navigateur puis réessaie."
            }
        }
        return try JSONSerialization.data(withJSONObject: response)
    }
}
