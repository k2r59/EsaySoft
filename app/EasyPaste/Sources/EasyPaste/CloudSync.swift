import AppKit
import CloudKit
import CryptoKit
import Security

enum CloudConfiguration {
    static let container = "iCloud.app.easypaste.mac"
    static let zone = CKRecordZone.ID(zoneName: "EasyPasteHistory")
    static let recordType = "EasyPasteItem"
    static var available: Bool {
        var code: SecCode?, staticCode: SecStaticCode?, info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
              let containers = entitlements["com.apple.developer.icloud-container-identifiers"] as? [String],
              let services = entitlements["com.apple.developer.icloud-services"] as? [String],
              let push = entitlements["com.apple.developer.aps-environment"] as? String else { return false }
        return containers.contains(container) && services.contains("CloudKit") && ["development", "production"].contains(push)
    }
    static func accountKey(_ name: String) -> String { SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined() }
}

@MainActor final class CloudSync: ObservableObject, CKSyncEngineDelegate {
    @Published private(set) var enabled: Bool
    @Published private(set) var working = false
    @Published private(set) var message = "Ton historique reste sur ce Mac."
    @Published private(set) var lastSync: Date?
    @Published private(set) var pending = 0
    let available: Bool
    private let defaults: UserDefaults
    private var vault: ClipVault?
    private var engine: CKSyncEngine?
    private var checkpoint = CloudCheckpoint()
    private var prepared: [String: PreparedCloudContent] = [:]
    private var observation: NSObjectProtocol?
    private var accountObservation: NSObjectProtocol?
    private var reload: (@MainActor () async -> Void)?
    private var needsInventory = false
    private var session = UUID()
    private var starting = false
    private var lastError: String?

    init(defaults: UserDefaults, allowed: Bool) {
        self.defaults = defaults; available = allowed && CloudConfiguration.available
        enabled = defaults.bool(forKey: "iCloudEnabled")
        lastSync = defaults.object(forKey: "iCloudLastSync") as? Date
        if !available { enabled = false }
    }
    func attach(_ vault: ClipVault, reload: @escaping @MainActor () async -> Void) {
        self.vault = vault; self.reload = reload
        observation = NotificationCenter.default.addObserver(forName: .easyPasteCloudChange, object: vault, queue: nil) { [weak self] note in
            guard let name = note.userInfo?["key"] as? String else { return }
            Task { @MainActor in self?.changed(name) }
        }
        accountObservation = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor in guard let self, self.enabled else { return }; await self.checkAccount() }
        }
        if enabled { Task { await start(allowAccountChange: false) } }
    }
    deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
        if let accountObservation { NotificationCenter.default.removeObserver(accountObservation) }
    }
    func setEnabled(_ value: Bool) async {
        if !value {
            enabled = false; defaults.set(false, forKey: "iCloudEnabled")
            await stop(); message = "Synchronisation arrêtée sur ce Mac. Tes copies locales et iCloud sont conservées."
            return
        }
        guard available, vault != nil else { message = CloudFailure.unavailable.localizedDescription; return }
        enabled = true; defaults.set(true, forKey: "iCloudEnabled")
        await start(allowAccountChange: true)
    }
    private func start(allowAccountChange: Bool) async {
        guard available, enabled, !starting, engine == nil, let vault else { return }
        starting = true; working = true; lastError = nil; message = "Connexion à iCloud…"
        let ticket = session
        defer { starting = false; if ticket == session { working = false } }
        do {
            let container = CKContainer(identifier: CloudConfiguration.container)
            guard try await container.accountStatus() == .available else { message = "Connecte-toi à iCloud dans les Réglages Système pour synchroniser."; return }
            let account = CloudConfiguration.accountKey(try await container.userRecordID().recordName)
            var stored = try await Task.detached(priority: .utility) { try vault.cloudCheckpoint() }.value
            guard enabled, ticket == session else { return }
            if let previous = stored.account, previous != account {
                guard allowAccountChange else { await accountChanged(); return }
                stored = CloudCheckpoint(sequence: stored.sequence, account: account)
            }
            stored.account = account; checkpoint = stored
            try await persist()
            try await Task.detached(priority: .utility) { try vault.cleanCloudStaging() }.value
            guard enabled, ticket == session else { return }
            var configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase, stateSerialization: checkpoint.engine, delegate: self)
            configuration.automaticallySync = true
            let sync = CKSyncEngine(configuration); engine = sync; needsInventory = true
            message = "Récupération de l’historique iCloud…"
            try await sync.fetchChanges()
            guard engine === sync else { return }
            try await sync.sendChanges()
            showProgress()
        } catch { if ticket == session { report(error) } }
    }
    func synchronize() async {
        guard enabled, !working else { return }
        guard let engine else { await start(allowAccountChange: false); return }
        working = true; lastError = nil; message = "Synchronisation en cours…"
        defer { working = false }
        do { try await engine.fetchChanges(); try await engine.sendChanges(); showProgress() }
        catch { report(error) }
    }
    func stop() async {
        session = UUID()
        let old = engine; engine = nil
        await old?.cancelOperations()
        for item in prepared.values { try? FileManager.default.removeItem(at: item.directory) }
        prepared.removeAll(); working = false; pending = 0
    }
    private func changed(_ name: String) {
        guard enabled, let engine, CloudKey(name: name) != nil else { return }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID(name))]); showProgress()
    }
    private func recordID(_ name: String) -> CKRecord.ID { .init(recordName: name, zoneID: CloudConfiguration.zone) }
    private func persist() async throws {
        guard let vault else { return }
        checkpoint.sequence += 1
        let value = checkpoint
        try await Task.detached(priority: .utility) { try vault.saveCloudCheckpoint(value) }.value
    }
    private func inventory(_ sync: CKSyncEngine) async throws {
        guard needsInventory, let vault else { return }
        let items = try await Task.detached(priority: .utility) { try vault.cloudInventory() }.value
        guard engine === sync else { return }
        sync.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CloudConfiguration.zone))])
        let changes = items.filter { checkpoint.acknowledged[$0.key.name] != $0 }.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID($0.key.name)) }
        sync.state.add(pendingRecordZoneChanges: changes); needsInventory = false
    }
    private func showProgress() {
        guard enabled else { return }
        pending = engine?.state.pendingRecordZoneChanges.count ?? 0
        if let lastError { message = lastError }
        else if engine != nil, !needsInventory { message = pending > 0 ? "\(pending) élément(s) en attente de synchronisation." : "Ton historique est à jour sur iCloud." }
    }
    private func report(_ error: Error) {
        let description: String
        switch (error as? CKError)?.code {
        case .quotaExceeded: description = "Ton espace iCloud est plein. Libère de la place, puis relance la synchronisation."
        case .networkFailure, .networkUnavailable: description = "Hors connexion. Les modifications sont conservées et seront réessayées."
        case .notAuthenticated, .accountTemporarilyUnavailable: description = "iCloud est indisponible. Vérifie ton compte Apple dans les Réglages Système."
        case .permissionFailure, .missingEntitlement, .badContainer, .badDatabase: description = "La configuration Apple d’EasyPaste ne permet pas encore la synchronisation. Ton historique local est conservé."
        default: description = "Synchronisation en pause : \(error.localizedDescription)"
        }
        lastError = description; message = description
    }
    private func checkAccount() async {
        guard available, enabled else { return }
        do {
            let container = CKContainer(identifier: CloudConfiguration.container)
            let status = try await container.accountStatus()
            if status == .noAccount { await accountChanged(); return }
            guard status == .available else { report(CKError(.accountTemporarilyUnavailable)); return }
            let current = CloudConfiguration.accountKey(try await container.userRecordID().recordName)
            if let previous = checkpoint.account, previous != current { await accountChanged() }
            else if engine == nil { await start(allowAccountChange: false) }
        } catch { report(error) }
    }
    private func accountChanged() async {
        enabled = false; defaults.set(false, forKey: "iCloudEnabled")
        await stop(); message = CloudFailure.accountChanged.localizedDescription
    }
    private func header(_ record: CKRecord) throws -> CloudHeader {
        guard record.recordID.zoneID == CloudConfiguration.zone, record.recordType == CloudConfiguration.recordType,
              let bytes = record.encryptedValues["header"] as? Data else { throw CloudFailure.invalidData }
        let value = try JSONDecoder().decode(CloudHeader.self, from: bytes)
        guard value.format == 1 else { throw CloudFailure.unsupportedVersion }
        guard value.key.name == record.recordID.recordName else { throw CloudFailure.invalidData }
        return value
    }
    private func remember(_ record: CKRecord, header: CloudHeader) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder); coder.finishEncoding()
        checkpoint.systemFields[header.key.name] = coder.encodedData
        checkpoint.acknowledged[header.key.name] = header
    }
    private func receive(_ record: CKRecord, sync: CKSyncEngine) async throws {
        guard let vault, enabled, engine === sync else { return }
        let remote = try header(record)
        let content = (record["content"] as? CKAsset)?.fileURL
        let movie = (record["movie"] as? CKAsset)?.fileURL
        let winner = try await Task.detached(priority: .utility) { try vault.applyCloud(remote, contentURL: content, movieURL: movie) }.value
        guard engine === sync else { return }
        remember(record, header: remote)
        if let fingerprint = record.encryptedValues["movieFingerprint"] as? String { checkpoint.movieFingerprints[remote.key.name] = fingerprint }
        if winner != remote { sync.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
    }
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine sync: CKSyncEngine) async {
        guard engine === sync, enabled else { return }
        do {
            switch event {
            case .stateUpdate(let event): checkpoint.engine = event.stateSerialization; try await persist()
            case .accountChange(let event):
                switch event.changeType {
                case .signIn(let user) where CloudConfiguration.accountKey(user.recordName) == checkpoint.account: break
                default:
                    // Cancel after returning from the delegate; waiting for our own callback would deadlock.
                    enabled = false; defaults.set(false, forKey: "iCloudEnabled")
                    Task { await self.accountChanged() }
                }
            case .fetchedDatabaseChanges(let event):
                if event.deletions.contains(where: { $0.zoneID == CloudConfiguration.zone }) {
                    // An explicit iCloud reset must not silently upload the entire local history again.
                    enabled = false; defaults.set(false, forKey: "iCloudEnabled")
                    message = "L’historique iCloud a été supprimé. Tes copies locales sont conservées. Réactive iCloud pour les synchroniser à nouveau."
                    checkpoint.engine = nil; checkpoint.acknowledged = [:]; checkpoint.systemFields = [:]; checkpoint.movieFingerprints = [:]
                    try await persist(); Task { await self.stop() }
                }
            case .fetchedRecordZoneChanges(let event):
                for modification in event.modifications where modification.record.recordID.zoneID == CloudConfiguration.zone { try await receive(modification.record, sync: sync) }
                if let vault {
                    for deletion in event.deletions {
                        guard deletion.recordID.zoneID == CloudConfiguration.zone, let key = CloudKey(name: deletion.recordID.recordName) else { continue }
                        let tombstone = CloudHeader(key: key, revision: .next(), deleted: true)
                        _ = try await Task.detached(priority: .utility) { try vault.applyCloud(tombstone, contentURL: nil, movieURL: nil) }.value
                        checkpoint.acknowledged[key.name] = tombstone; checkpoint.systemFields[key.name] = nil
                    }
                }
                try await persist(); await reload?()
            case .sentRecordZoneChanges(let event):
                for record in event.savedRecords {
                    let sent = try header(record); remember(record, header: sent)
                    if let item = prepared.removeValue(forKey: sent.key.name) {
                        if let fingerprint = item.movieFingerprint { checkpoint.movieFingerprints[sent.key.name] = fingerprint }
                        try? FileManager.default.removeItem(at: item.directory)
                    }
                    if let vault {
                        let current = try await Task.detached(priority: .utility) { try vault.cloudHeader(sent.key) }.value
                        if current != sent { sync.state.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)]) }
                    }
                }
                for failure in event.failedRecordSaves {
                    let id = failure.record.recordID
                    if let item = prepared.removeValue(forKey: id.recordName) { try? FileManager.default.removeItem(at: item.directory) }
                    switch failure.error.code {
                    case .serverRecordChanged:
                        // Conflict records may omit downloaded asset URLs. Fetch the complete record before importing.
                        let server = try await sync.database.record(for: id)
                        try await receive(server, sync: sync)
                        sync.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                        await reload?()
                    case .unknownItem:
                        // A failed save alone is not evidence authorizing deletion of local data.
                        // A new fetch must deliver a deletion event before removing a live item.
                        if let key = CloudKey(name: id.recordName), let vault,
                           try await Task.detached(priority: .utility, operation: { try vault.cloudHeader(key)?.deleted == true }).value {
                            checkpoint.systemFields[id.recordName] = nil
                            sync.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
                        } else { throw CloudFailure.remoteRemoved }
                    case .zoneNotFound, .userDeletedZone:
                        throw failure.error
                    default: report(failure.error)
                    }
                }
                try await persist()
            case .sentDatabaseChanges(let event):
                if let error = event.failedZoneSaves.first?.error { report(error) }
            case .didFetchRecordZoneChanges(let event): if let error = event.error { report(error) }
            case .didFetchChanges:
                try await inventory(sync); showProgress()
            case .didSendChanges:
                if lastError == nil, sync.state.pendingRecordZoneChanges.isEmpty {
                    lastSync = Date(); defaults.set(lastSync, forKey: "iCloudLastSync")
                }
                showProgress()
            case .willFetchChanges, .willSendChanges: lastError = nil; message = "Synchronisation en cours…"
            case .willFetchRecordZoneChanges: break
            @unknown default: break
            }
        } catch {
            report(error)
            // Fail closed: do not persist a later engine token after a local import failed.
            engine = nil
            Task { await sync.cancelOperations() }
        }
    }
    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine sync: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard engine === sync, enabled, !needsInventory, let vault else { return nil }
        let changes = sync.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }.prefix(2)
        var records: [CKRecord] = []
        do {
            for change in changes {
                guard case .saveRecord(let id) = change, let key = CloudKey(name: id.recordName) else { continue }
                let uploadedMovie = checkpoint.movieFingerprints[key.name]
                guard let item = try await Task.detached(priority: .utility, operation: { try vault.prepareCloudContent(key, uploadedMovie: uploadedMovie) }).value else {
                    sync.state.remove(pendingRecordZoneChanges: [change]); continue
                }
                guard engine === sync, enabled else { try? FileManager.default.removeItem(at: item.directory); return nil }
                let record: CKRecord
                if let fields = checkpoint.systemFields[key.name] {
                    let decoder = try NSKeyedUnarchiver(forReadingFrom: fields); decoder.requiresSecureCoding = true
                    guard let restored = CKRecord(coder: decoder) else { throw CloudFailure.invalidData }
                    decoder.finishDecoding(); record = restored
                } else { record = CKRecord(recordType: CloudConfiguration.recordType, recordID: id) }
                record.encryptedValues["header"] = try JSONEncoder().encode(item.header)
                record["content"] = item.content.map(CKAsset.init(fileURL:))
                if item.header.deleted { record["movie"] = nil; record.encryptedValues["movieFingerprint"] = nil }
                else if let movie = item.movie { record["movie"] = CKAsset(fileURL: movie); record.encryptedValues["movieFingerprint"] = item.movieFingerprint }
                if let old = prepared.updateValue(item, forKey: key.name) { try? FileManager.default.removeItem(at: old.directory) }
                records.append(record)
            }
            return records.isEmpty ? nil : .init(recordsToSave: records, atomicByZone: false)
        } catch { report(error); engine = nil; Task { await sync.cancelOperations() }; return nil }
    }
}
