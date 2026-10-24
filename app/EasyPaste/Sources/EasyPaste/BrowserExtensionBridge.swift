import AppKit
import SwiftUI
import Darwin

/// Deliberately separate from History/Vault: this bridge can only verify the
/// application version. Page contents still travel through the clipboard.
enum BrowserBridgeProtocol {
    static let host = "app.easypaste.web"
    static let extensionID = "nmkechbpakkenabambdbpnaahhdlgpej"
    static let origin = "chrome-extension://\(extensionID)/"
    static let maximumMessage = 4096
    static func authorized(_ origin: String) -> Bool {
        origin == self.origin || origin == String(self.origin.dropLast())
    }
    static func response(_ data: Data, origin: String, enabled: Bool, version: String) throws -> Data {
        guard authorized(origin), data.count <= maximumMessage,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["protocol", "type", "nonce", "extensionVersion"]),
              let proto = object["protocol"] as? NSNumber, CFGetTypeID(proto) != CFBooleanGetTypeID(), proto.intValue == 1, proto.doubleValue == 1,
              object["type"] as? String == "hello",
              let nonce = object["nonce"] as? String, (16...128).contains(nonce.utf8.count),
              nonce.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              let extensionVersion = object["extensionVersion"] as? String,
              extensionVersion.utf8.count <= 32,
              extensionVersion.range(of: #"^[0-9]+(?:\.[0-9]+){1,3}$"#, options: .regularExpression) != nil else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONSerialization.data(withJSONObject: [
            "protocol": 1, "type": "hello", "nonce": nonce, "bridgeVersion": 1,
            "appVersion": String(version.prefix(32)), "status": enabled ? "ready" : "disabled"
        ], options: [.sortedKeys])
    }
    static func framed(_ payload: Data) throws -> Data {
        guard !payload.isEmpty, payload.count <= maximumMessage else { throw CocoaError(.fileReadTooLarge) }
        var length = UInt32(payload.count).littleEndian
        var result = withUnsafeBytes(of: &length) { Data($0) }
        result.append(payload); return result
    }
    static func read(_ input: FileHandle) throws -> Data {
        func exact(_ length: Int) throws -> Data {
            var data = Data()
            while data.count < length {
                guard let piece = try input.read(upToCount: length - data.count), !piece.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                data.append(piece)
            }
            return data
        }
        let header = try exact(4)
        let size = header.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << UInt32($1.offset * 8) }
        guard size > 0, size <= maximumMessage else { throw CocoaError(.fileReadTooLarge) }
        return try exact(Int(size))
    }
}

enum BrowserExtensionTarget: String, CaseIterable, Identifiable, Codable {
    case arc, chrome
    var id: Self { self }
    var title: String { self == .arc ? "Arc" : "Google Chrome" }
    var bundleID: String { self == .arc ? "company.thebrowser.Browser" : "com.google.Chrome" }
    func registries(home: URL) -> [URL] {
        let base = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        // Arc also resolves the shared Chrome registry on macOS (verified by a
        // real hello). Keep its own path for versions using the user-data path.
        let paths = self == .arc ? ["Arc/User Data/NativeMessagingHosts", "Google/Chrome/NativeMessagingHosts"] : ["Google/Chrome/NativeMessagingHosts"]
        return paths.map { base.appendingPathComponent($0, isDirectory: true) }
    }
}

struct BrowserBridgeConfiguration: Codable {
    var enabled: Bool
    var browser: BrowserExtensionTarget
    var generation: String? = nil
}
struct BrowserBridgeExchange: Codable {
    let extensionID: String
    let extensionVersion: String
    let appVersion: String
    let date: Date
    var generation: String? = nil
}
enum BrowserExtensionFiles {
    static var root: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyPaste/BrowserExtension", isDirectory: true) }
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8192,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func prepare(resources: URL, application: URL, target: BrowserExtensionTarget, root: URL = root, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let manager = FileManager.default
        let helper = application.appendingPathComponent("Contents/MacOS/EasyPaste")
        guard manager.isExecutableFile(atPath: helper.path),
              let manifest = try? Data(contentsOf: resources.appendingPathComponent("manifest.json")),
              let object = try JSONSerialization.jsonObject(with: manifest) as? [String: Any],
              object["name"] as? String == "EasyPaste · Web", object["key"] is String else {
            throw NSError(domain: "EasyPaste.Web", code: 1, userInfo: [NSLocalizedDescriptionKey: "L’extension fournie est indisponible. Réinstalle EasyPaste depuis son installateur."])
        }
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = root.appendingPathComponent(".prepared-" + UUID().uuidString)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        // Ship runtime files only, never development fixtures or node_modules.
        for name in ["manifest.json", "popup.html", "popup.css", "popup.js", "src", "icons", "LICENSE"] {
            try manager.copyItem(at: resources.appendingPathComponent(name), to: staging.appendingPathComponent(name))
        }
        let installed = root.appendingPathComponent("Extension", isDirectory: true)
        if manager.fileExists(atPath: installed.path) {
            try manager.moveItem(at: installed, to: root.appendingPathComponent("Extension-backup-" + UUID().uuidString))
        }
        try manager.moveItem(at: staging, to: installed)
        let native: [String: Any] = ["name": BrowserBridgeProtocol.host, "description": "Vérification locale EasyPaste", "path": helper.path, "type": "stdio", "allowed_origins": [BrowserBridgeProtocol.origin]]
        let data = try JSONSerialization.data(withJSONObject: native, options: [.prettyPrinted, .sortedKeys])
        for directory in target.registries(home: home) {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = directory.appendingPathComponent(BrowserBridgeProtocol.host + ".json")
            try data.write(to: destination, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        try write(BrowserBridgeConfiguration(enabled: true, browser: target, generation: UUID().uuidString), to: root.appendingPathComponent("configuration.json"))
        try? manager.removeItem(at: root.appendingPathComponent("last-exchange.json"))
    }
    static func disable(root: URL = root, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        let current = read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))
        // Revoke first, even if a browser still has the manifest cached.
        try write(BrowserBridgeConfiguration(enabled: false, browser: current?.browser ?? .arc), to: root.appendingPathComponent("configuration.json"))
        try? FileManager.default.removeItem(at: root.appendingPathComponent("last-exchange.json"))
        for target in BrowserExtensionTarget.allCases {
            for directory in target.registries(home: home) {
                let path = directory.appendingPathComponent(BrowserBridgeProtocol.host + ".json")
                if let data = try? Data(contentsOf: path), data.count <= 8192,
                   let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   manifest["name"] as? String == BrowserBridgeProtocol.host,
                   manifest["allowed_origins"] as? [String] == [BrowserBridgeProtocol.origin] {
                    try FileManager.default.removeItem(at: path)
                }
            }
        }
    }
}

enum BrowserBridgeHost {
    static func runIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard args.contains("--browser-bridge") || (args.count == 2 && BrowserBridgeProtocol.authorized(args[1])) else { return false }
        // A corrupt/truncated frame must not leave a background helper waiting.
        alarm(6)
        defer { alarm(0) }
        do {
            let origin = CommandLine.arguments.last ?? ""
            guard BrowserBridgeProtocol.authorized(origin) else { return true }
            let data = try BrowserBridgeProtocol.read(.standardInput)
            let root = BrowserExtensionFiles.root
            let config = BrowserExtensionFiles.read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "local"
            let response = try BrowserBridgeProtocol.response(data, origin: origin, enabled: config?.enabled == true, version: version)
            if config?.enabled == true,
               let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let extensionVersion = request["extensionVersion"] as? String {
                try BrowserExtensionFiles.write(BrowserBridgeExchange(extensionID: BrowserBridgeProtocol.extensionID, extensionVersion: extensionVersion, appVersion: version, date: Date(), generation: config?.generation), to: root.appendingPathComponent("last-exchange.json"))
            }
            try FileHandle.standardOutput.write(contentsOf: BrowserBridgeProtocol.framed(response))
        } catch {
            // stdout is exclusively the framed protocol, never logs or app UI.
        }
        return true
    }
}

@MainActor final class BrowserExtensionModel: ObservableObject {
    @Published var target = BrowserExtensionTarget.arc
    @Published private(set) var enabled = false
    @Published private(set) var exchange: BrowserBridgeExchange?
    @Published private(set) var busy = false
    @Published var message = ""
    private let root: URL
    private let home: URL
    var folder: URL { root.appendingPathComponent("Extension", isDirectory: true) }
    init(root: URL = BrowserExtensionFiles.root, home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.root = root; self.home = home; refresh() }
    func refresh() {
        let config = BrowserExtensionFiles.read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))
        enabled = config?.enabled ?? false
        if let config { target = config.browser }
        exchange = enabled ? BrowserExtensionFiles.read(BrowserBridgeExchange.self, from: root.appendingPathComponent("last-exchange.json")) : nil
        if exchange?.extensionID != BrowserBridgeProtocol.extensionID || exchange?.generation != config?.generation { exchange = nil }
    }
    func prepare() async {
        guard !busy else { return }
        busy = true; message = ""
        defer { busy = false }
        guard let resources = Bundle.main.url(forResource: "BrowserExtension", withExtension: nil) else { message = "L’extension n’est pas fournie dans cette copie d’EasyPaste."; return }
        let application = Bundle.main.bundleURL, selected = target, root = self.root, home = self.home
        do {
            try await Task.detached(priority: .utility) { try BrowserExtensionFiles.prepare(resources: resources, application: application, target: selected, root: root, home: home) }.value
            refresh(); message = "Prêt. Charge le dossier dans \(selected.title), puis clique sur Connecter dans l’extension."
        } catch { message = error.localizedDescription }
    }
    func disable() {
        do { try BrowserExtensionFiles.disable(root: root, home: home); refresh(); message = "Lien désactivé. Les copies de l’extension restent utilisables." }
        catch { message = error.localizedDescription }
    }
    func openExtensions() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.bundleID), let url = URL(string: "chrome://extensions") else { message = "\(target.title) n’est pas installé."; return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

struct BrowserExtensionSettings: View {
    @StateObject private var model = BrowserExtensionModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreferenceRow("Navigateur") {
                Picker("Navigateur", selection: $model.target) {
                    ForEach(BrowserExtensionTarget.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 170)
            }
            HStack(spacing: 8) {
                Image(systemName: model.exchange != nil ? "checkmark.circle.fill" : "puzzlepiece.extension")
                if let exchange = model.exchange {
                    Text("Lien vérifié · extension \(exchange.extensionVersion)")
                    Spacer()
                    Text(exchange.date, style: .relative).foregroundStyle(Theme.muted)
                } else { Text(model.enabled ? "Prête à associer" : "Non configurée") }
            }.font(.system(size: 12, weight: .medium))
            HStack(spacing: 10) {
                Button(model.busy ? "Préparation…" : "Préparer l’installation") { Task { await model.prepare() } }
                    .buttonStyle(PasteButtonStyle(primary: true)).disabled(model.busy)
                if model.enabled {
                    Button("Ouvrir les extensions") { model.openExtensions() }.buttonStyle(PasteButtonStyle())
                    Button("Afficher le dossier") { NSWorkspace.shared.activateFileViewerSelecting([model.folder]) }.buttonStyle(PasteButtonStyle())
                }
            }
            if model.enabled {
                HStack {
                    Button("Actualiser l’état") { model.refresh() }.buttonStyle(FullAreaButtonStyle(minimumSize: 28))
                    Spacer()
                    Button("Désactiver le lien") { model.disable() }.buttonStyle(FullAreaButtonStyle(minimumSize: 28))
                }.font(.system(size: 11))
            }
            Text("Copie mise en forme et sous-titres YouTube. Vérification locale à la demande, sans accès à l’historique.").font(.system(size: 11)).foregroundStyle(Theme.muted)
            if !model.message.isEmpty { Text(model.message).font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }.onAppear { model.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
