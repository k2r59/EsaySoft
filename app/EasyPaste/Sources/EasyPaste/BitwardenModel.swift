import AppKit
import SwiftUI

@MainActor final class BitwardenModel: ObservableObject {
    enum Page { case account, create, sends }
    @Published private(set) var enabled: Bool
    @Published var publicOnly: Bool { didSet { defaults.set(publicOnly, forKey: "bitwarden.publicOnly"); visibilityChanged?() } }
    @Published private(set) var account: String
    @Published private(set) var unlocked = false
    @Published private(set) var busy = false
    @Published private(set) var progress: Double?
    @Published private(set) var status = ""
    @Published private(set) var error: String?
    @Published private(set) var providers: [Int] = []
    @Published private(set) var needsDeviceCode = false
    @Published var page: Page = .account
    @Published var options = BWSendOptions()
    @Published private(set) var content: BWContent?
    @Published private(set) var contentLabel = ""
    @Published private(set) var sends: [BWSend] = []
    @Published private(set) var created: BWSend?
    @Published private(set) var copied = false
    var present: (() -> Void)?
    var dismiss: (() -> Void)?
    var visibilityChanged: (() -> Void)?
    var notify: ((String) -> Void)?
    var quickFeedback: ((String) -> Void)?
    var copyLink: (URL) -> Bool = BitwardenModel.writeLink
    private let defaults: UserDefaults
    private let client: BWClient
    private let store: any BWSessionStore
    private var session: BWSession?
    private var work: Task<Void, Never>?
    private var idle: Task<Void, Never>?
    private var generation = UUID()
    private var quick = false
    private var pendingClip: Clip?
    private weak var history: History?
    private var temporary: BWTemporaryDirectory?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    // Existing sessions retain their original host; new sign-ins use bitwarden.com.
    var region: BWRegion { session?.region ?? BWRegion(rawValue: defaults.string(forKey: "bitwarden.region") ?? "") ?? .international }
    var canShare: Bool { enabled && !busy }
    init(defaults: UserDefaults = .standard, client: BWClient = BWClient(), store: any BWSessionStore = BWKeychainSessionStore()) {
        self.defaults = defaults; self.client = client; self.store = store
        enabled = defaults.bool(forKey: "bitwarden.enabled"); publicOnly = defaults.bool(forKey: "bitwarden.publicOnly")
        account = defaults.bool(forKey: "bitwarden.enabled") ? defaults.string(forKey: "bitwarden.account") ?? "" : ""
        // No Keychain read, network session restoration, timer or polling at initialization.
    }
    func attach(history: History) {
        self.history = history
        notify = { [weak history] in history?.report($0) }
        guard observers.isEmpty else { return }
        let nc = NSWorkspace.shared.notificationCenter
        observers.append((nc, nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock() } }))
        let dc = DistributedNotificationCenter.default()
        observers.append((dc, dc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.lock() } }))
    }
    deinit { for (center, token) in observers { center.removeObserver(token) } }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; defaults.set(value, forKey: "bitwarden.enabled")
        if !value { disconnect(); dismiss?() }
        visibilityChanged?()
    }
    func clearError() { error = nil }
    func cancel() {
        work?.cancel() // Keep the task until cleanup completes; no concurrent re-entry.
        status = "Annulation…"
    }
    func lock() {
        guard enabled else { return }
        generation = UUID(); work?.cancel(); work = nil; idle?.cancel(); idle = nil
        session = nil; unlocked = false; busy = false; progress = nil; providers = []; needsDeviceCode = false; sends = []; created = nil; copied = false
        content = nil; pendingClip = nil; temporary = nil; quick = false; page = .account
        options = BWSendOptions(); dismiss?()
        // Retain any in-flight encrypted staging until its worker exits.
    }
    func disconnect() {
        generation = UUID(); work?.cancel(); work = nil; idle?.cancel(); idle = nil
        session = nil; unlocked = false; busy = false; account = ""; content = nil; sends = []; created = nil; copied = false
        pendingClip = nil; temporary = nil; quick = false; providers = []; needsDeviceCode = false; error = nil; page = .account
        options = BWSendOptions()
        defaults.removeObject(forKey: "bitwarden.account")
        Task { do { try await store.remove() } catch { self.notify?("La session Bitwarden n’a pas pu être effacée du trousseau.") } }
    }
    func showAccount() { guard enabled, !busy else { return }; page = .account; error = nil; created = nil; content = nil; pendingClip = nil; temporary = nil; options = BWSendOptions(); present?() }
    private func begin(_ text: String, operation: @escaping (UUID) async throws -> Void) {
        guard enabled, !busy else { return }
        error = nil; status = text; progress = nil; busy = true
        let ticket = UUID(); generation = ticket
        work = Task { [weak self] in
            guard let self else { return }
            do { try await operation(ticket) }
            catch {
                guard self.generation == ticket else { return }
                if error is CancellationError { self.status = "Annulé" }
                else { self.error = (error as? BWError)?.errorDescription ?? "L’opération a échoué. Réessaie." }
                if case BWError.twoFactor(let values) = error { self.providers = values; self.needsDeviceCode = false }
                if case BWError.newDevice = error { self.needsDeviceCode = true }
                if case BWError.expiredSession = error { self.session = nil; self.unlocked = false; self.page = .account }
            }
            guard self.generation == ticket else { return }
            self.busy = false; self.work = nil; self.progress = nil
            self.scheduleLock()
        }
    }
    private func check(_ ticket: UUID) throws { try Task.checkCancellation(); guard enabled, generation == ticket else { throw CancellationError() } }
    private func saveSession(_ value: BWSession, ticket: UUID) async throws {
        try check(ticket); try await store.write(value); try check(ticket)
        session = value; unlocked = true; account = value.email; providers = []; needsDeviceCode = false
        defaults.set(value.email, forKey: "bitwarden.account"); defaults.set(value.region.rawValue, forKey: "bitwarden.region")
    }
    func login(email: String, password: String, code: String, provider: Int) {
        begin("Connexion…") { ticket in
            let device = self.defaults.string(forKey: "bitwarden.device") ?? UUID().uuidString
            self.defaults.set(device, forKey: "bitwarden.device")
            let value = try await self.client.login(email: email, password: password, region: .international, device: device, code: code, provider: provider, newDevice: self.needsDeviceCode)
            try await self.saveSession(value, ticket: ticket)
            try await self.afterUnlock(ticket)
        }
    }
    func sendEmailCode(email: String, password: String) {
        guard providers.contains(1), !needsDeviceCode else { return }
        begin("Envoi du code…") { ticket in
            let device = self.defaults.string(forKey: "bitwarden.device") ?? UUID().uuidString
            try await self.client.sendLoginEmail(email: email, password: password, region: .international, device: device)
            try self.check(ticket); self.status = "Code envoyé par e-mail"
        }
    }
    func unlock() {
        begin("Déverrouillage…") { ticket in
            let stored = try await self.store.read(); try self.check(ticket)
            let value = try await self.client.refresh(stored)
            try await self.saveSession(value, ticket: ticket)
            try await self.afterUnlock(ticket)
        }
    }
    private func afterUnlock(_ ticket: UUID) async throws {
        if let clip = pendingClip { try await loadClip(clip, ticket: ticket); pendingClip = nil; page = .create; if quick { try await upload(ticket) } }
        else { page = .sends; try await loadSends(ticket) }
    }
    private func activeSession(_ ticket: UUID) async throws -> BWSession {
        try check(ticket); guard var value = session else { throw BWError.locked }
        if value.expires.timeIntervalSinceNow < 90 { value = try await client.refresh(value); try await saveSession(value, ticket: ticket) }
        return value
    }
    static func datedTitle(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "dd MMM yyyy 'à' HH:mm:ss"; return f.string(from: date)
    }
    static func fastOptions(now: Date = Date()) -> BWSendOptions { BWSendOptions(name: datedTitle(now), days: 7, audience: .link, emails: "", password: "") }
    func share(_ clip: Clip, forceOptions: Bool = false) {
        guard canShare, clip.trashedAt == nil else { return }
        quick = publicOnly && !forceOptions; pendingClip = clip; created = nil; copied = false; error = nil
        options = quick ? Self.fastOptions() : BWSendOptions(name: String(clip.title.prefix(90)))
        page = unlocked ? .create : .account; status = "Préparation…"; present?()
        guard unlocked else { return }
        begin("Préparation…") { ticket in
            try await self.loadClip(clip, ticket: ticket); self.pendingClip = nil
            if self.quick { try await self.upload(ticket) }
        }
    }
    private func loadClip(_ clip: Clip, ticket: UUID) async throws {
        guard let history else { throw BWError.invalidFile }
        let full = try await history.fullClip(clip); try check(ticket)
        contentLabel = clip.kind == .image ? "Image originale" : clip.kind == .video ? "Vidéo originale" : clip.title
        let folder = try BWTemporaryDirectory(); temporary = folder
        switch full.kind {
        case .text, .link, .color:
            if full.text.utf8.count <= 650 { content = .text(full.text) }
            else {
                let url = folder.url.appendingPathComponent("Texte.txt")
                try await Task.detached { defer { withExtendedLifetime(folder) {} }; try Data(full.text.utf8).write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }.value
                try check(ticket); content = .file(url, name: "Texte.txt"); contentLabel = "Texte.txt · texte long"
            }
        case .image:
            guard let data = full.imageData else { throw BWError.invalidFile }
            let ext = data.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "png" : "tiff"
            let url = folder.url.appendingPathComponent("Capture.\(ext)")
            try await Task.detached { defer { withExtendedLifetime(folder) {} }; try data.write(to: url, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }.value
            try check(ticket); content = .file(url, name: url.lastPathComponent)
        case .video:
            let url = try await history.videoURL(full); try check(ticket); content = .file(url, name: "Capture.mp4")
        case .file:
            let paths = full.text.split(separator: "\n")
            guard paths.count == 1 else { throw BWError.invalidFile }
            let url = URL(fileURLWithPath: String(paths[0])); _ = try BWCrypto.fileSize(url)
            content = .file(url, name: url.lastPathComponent); contentLabel = url.lastPathComponent
        }
    }
    func create() { begin("Chiffrement…") { ticket in try await self.upload(ticket) } }
    private func upload(_ ticket: UUID) async throws {
        guard let content else { throw BWError.emptyText }
        let session = try await activeSession(ticket)
        // Quick mode is a fixed contract, never reuse a previous private-share form.
        let options = quick ? Self.fastOptions() : options
        let folder = try BWTemporaryDirectory(), sourceLease = temporary
        defer { withExtendedLifetime(folder) {}; withExtendedLifetime(sourceLease) {} }
        status = "Chiffrement…"
        let worker = Task.detached(priority: .utility) { defer { withExtendedLifetime(sourceLease) {} }; return try BWCrypto.prepare(content: content, options: options, userKey: session.userKey, directory: folder.url) }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try check(ticket); status = "Création du lien…"
        let send = try await client.send(prepared, session: session) { [weak self] value in
            Task { @MainActor in guard let self, self.generation == ticket else { return }; self.status = "Envoi…"; self.progress = value }
        }
        do { try check(ticket) }
        catch {
            let cleanup = Task.detached { try await self.client.delete(id: send.id, session: session) }
            try await cleanup.value; throw CancellationError()
        }
        created = send; copied = copyLink(send.link)
        if copied { history?.sounds.play(.copy) }
        sends.insert(send, at: 0)
        do {
            guard let history else { throw CocoaError(.fileWriteUnknown) }
            _ = try await history.saveBitwardenLink(send)
        } catch {
            // The remote Send already exists: retain it and its copied link, never upload again here.
            try check(ticket)
            self.error = "Lien créé, mais l’ajout à la pile a échoué. Le lien reste disponible dans Bitwarden."
            status = copied ? "Lien copié · ajout à la pile impossible" : "Lien créé · copie et ajout à la pile impossibles"
            notify?(status)
            temporary = nil; self.options.password = ""
            return
        }
        try check(ticket)
        status = copied ? "Lien copié" : "Lien créé · copie impossible"
        if copied { notify?("Lien copié · \(options.days) jours") }
        if quick && copied { dismiss?(); quickFeedback?("Lien copié · 7 jours"); self.content = nil; created = nil }
        temporary = nil; self.options.password = ""
    }
    func showSends() {
        guard canShare else { return }; pendingClip = nil; content = nil; created = nil; error = nil; quick = false; temporary = nil; options = BWSendOptions()
        page = unlocked ? .sends : .account; present?()
        if unlocked { begin("Chargement…") { ticket in try await self.loadSends(ticket) } }
    }
    private func loadSends(_ ticket: UUID) async throws {
        let session = try await activeSession(ticket), values = try await client.list(session: session)
        try check(ticket); sends = values
    }
    func delete(_ send: BWSend) {
        begin("Suppression…") { ticket in
            let session = try await self.activeSession(ticket); try await self.client.delete(id: send.id, session: session)
            try self.check(ticket); self.sends.removeAll { $0.id == send.id }
        }
    }
    func recopy(_ send: BWSend) { copied = copyLink(send.link); if copied { history?.sounds.play(.copy); notify?("Lien copié") } }
    var quickPresentation: Bool { quick }
    func close() {
        guard !busy else { cancel(); return }
        error = nil; providers = []; pendingClip = nil; content = nil; created = nil
        temporary = nil; options = BWSendOptions()
        dismiss?()
    }
    func shutdown() async {
        work?.cancel(); await work?.value; idle?.cancel(); session = nil
        temporary = nil
    }
    private func scheduleLock() {
        idle?.cancel(); guard unlocked else { return }
        idle = Task { [weak self] in do { try await Task.sleep(for: .seconds(15 * 60)) } catch { return }; self?.lock() }
    }
    static func writeLink(_ url: URL) -> Bool {
        let item = NSPasteboardItem(); item.setString(url.absoluteString, forType: .string)
        item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        NSPasteboard.general.clearContents(); return NSPasteboard.general.writeObjects([item])
    }
}

/// A worker retains its staging directory even if the user disables the integration.
/// This prevents cancellation/cleanup from racing a pending write or upload.
final class BWTemporaryDirectory: @unchecked Sendable {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-Bitwarden-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
