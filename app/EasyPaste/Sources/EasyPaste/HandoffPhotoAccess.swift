import AppKit
import SwiftUI

/// Explicit, read-only access to the Handoff transfer folder selected by the
/// user. Never requests Full Disk Access or enumerates unrelated app data.
final class HandoffPhotoAccess {
    static let shared = HandoffPhotoAccess()
    static let bookmarkKey = "handoffPhotoReadBookmark"
    static var transferDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard", isDirectory: true)
    }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var configured: Bool { defaults.data(forKey: Self.bookmarkKey) != nil }
    func forget() { defaults.removeObject(forKey: Self.bookmarkKey) }

    static func contains(_ file: URL, in directory: URL) -> Bool {
        guard file.isFileURL, directory.isFileURL else { return false }
        let root = canonical(directory).pathComponents
        let child = canonical(file).pathComponents
        return child.count > root.count && child.starts(with: root)
    }

    // Resolving a whole URL can leave parent symlinks unresolved when the
    // promised leaf does not exist yet. Resolve each existing component first.
    private static func canonical(_ url: URL) -> URL {
        var value = URL(fileURLWithPath: "/", isDirectory: true)
        for part in url.pathComponents where part != "/" && part != "." {
            if part == ".." { value.deleteLastPathComponent() }
            else { value.appendPathComponent(part); value = value.resolvingSymlinksInPath() }
        }
        return value.standardizedFileURL
    }

    func withAccess<T>(to file: URL, operation: () throws -> T) rethrows -> T {
        guard Self.contains(file, in: Self.transferDirectory), let data = defaults.data(forKey: Self.bookmarkKey) else { return try operation() }
        var stale = false
        guard let directory = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
              directory.resolvingSymlinksInPath().standardizedFileURL == Self.transferDirectory.resolvingSymlinksInPath().standardizedFileURL,
              Self.contains(file, in: directory) else { return try operation() }
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        return try operation()
    }

    @MainActor func request() async throws -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Photos reçues d’un appareil Apple"
        panel.message = "Autorise la lecture du dossier de transfert du presse-papiers. EasyPaste pourra conserver les photos reçues dans ton historique local. Aucun accès complet au disque n’est demandé."
        panel.prompt = "Autoriser ce dossier"
        panel.directoryURL = Self.transferDirectory
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = false
        panel.showsHiddenFiles = true
        let validator = HandoffFolderValidator()
        panel.delegate = validator
        defer { withExtendedLifetime(validator) {} }
        let response: NSApplication.ModalResponse = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
        }
        guard response == .OK, let directory = panel.url else { return false }
        guard directory.resolvingSymlinksInPath().standardizedFileURL == Self.transferDirectory.resolvingSymlinksInPath().standardizedFileURL else {
            throw CaptureFailure.message("Sélectionne uniquement le dossier shared-pasteboard proposé.")
        }
        let accessing = directory.startAccessingSecurityScopedResource()
        defer { if accessing { directory.stopAccessingSecurityScopedResource() } }
        let data = try directory.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: Self.bookmarkKey)
        return true
    }
}

final class HandoffFolderValidator: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, validate url: URL) throws {
        guard url.resolvingSymlinksInPath().standardizedFileURL == HandoffPhotoAccess.transferDirectory.resolvingSymlinksInPath().standardizedFileURL else {
            throw CaptureFailure.message("Choisis uniquement le dossier shared-pasteboard proposé.")
        }
    }
}

struct HandoffPhotoSettings: View {
    @ObservedObject var history: History
    @State private var configured = HandoffPhotoAccess.shared.configured
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Photos d’iPhone et d’iPad").fontWeight(.medium)
                    Text("Si macOS bloque les aperçus, autorise uniquement le dossier de transfert.")
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button(configured ? "Réessayer" : "Autoriser…") {
                    busy = true
                    Task {
                        defer { busy = false; configured = HandoffPhotoAccess.shared.configured }
                        do {
                            if !configured { guard try await HandoffPhotoAccess.shared.request() else { return } }
                            let count = await history.recoverHandoffPhotos()
                            message = count > 0 ? "\(count) photo(s) ajoutée(s) avec aperçu." : "Autorisation enregistrée. Aucun aperçu récupéré pour le moment."
                        } catch { message = error.localizedDescription }
                    }
                }.buttonStyle(PasteButtonStyle(primary: !configured)).disabled(busy)
                if configured {
                    Button("Retirer") { HandoffPhotoAccess.shared.forget(); configured = false; message = "Autorisation oubliée par EasyPaste." }
                        .buttonStyle(PasteButtonStyle()).disabled(busy)
                }
            }
            if busy { ProgressView().controlSize(.small) }
            if !message.isEmpty { Text(message).font(.system(size: 11)).foregroundStyle(Theme.muted) }
        }
    }
}
