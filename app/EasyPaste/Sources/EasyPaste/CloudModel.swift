import Foundation

/// Monotonic on one Mac; the UUID provides a deterministic tie-break on other Macs.
struct CloudRevision: Codable, Equatable, Comparable, Sendable {
    var date: Date
    var nonce: String
    static func next(after old: CloudRevision? = nil, now: Date = Date()) -> Self {
        .init(date: max(now, (old?.date ?? .distantPast).addingTimeInterval(0.001)), nonce: UUID().uuidString)
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.date == rhs.date ? lhs.nonce < rhs.nonce : lhs.date < rhs.date
    }
}

struct CloudKey: Hashable, Codable, Sendable {
    enum Kind: String, Codable { case clip, board }
    let kind: Kind
    let id: UUID
    var name: String { kind.rawValue + "_" + id.uuidString }
    init(_ kind: Kind, _ id: UUID) { self.kind = kind; self.id = id }
    init?(name: String) {
        let parts = name.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, let kind = Kind(rawValue: String(parts[0])), let id = UUID(uuidString: String(parts[1])) else { return nil }
        self.init(kind, id)
    }
}

struct CloudHeader: Codable, Equatable, Sendable {
    var format = 1
    var key: CloudKey
    var revision: CloudRevision
    var deleted = false
    /// A permanent deletion wins over edits from a Mac that was offline.
    func wins(over local: Self?) -> Bool {
        guard let local else { return true }
        if deleted != local.deleted { return deleted }
        return revision > local.revision
    }
}

struct CloudContent: Codable {
    var clip: Clip?
    var board: Pinboard?
}

enum CloudFailure: LocalizedError {
    case invalidData, unsupportedVersion, storageFull, unavailable, accountChanged, remoteRemoved
    var errorDescription: String? {
        switch self {
        case .invalidData: return "Un élément iCloud est invalide. La copie locale est conservée."
        case .unsupportedVersion: return "Un autre Mac utilise une version plus récente d’EasyPaste. Mets l’application à jour pour reprendre la synchronisation."
        case .storageFull: return "L’espace disponible sur ce Mac est insuffisant pour recevoir cet élément."
        case .unavailable: return "Cette version ne possède pas encore la configuration Apple nécessaire à iCloud. Ton historique reste sur ce Mac."
        case .accountChanged: return "Le compte Apple a changé. La synchronisation est arrêtée et ton historique reste sur ce Mac. Réactive iCloud pour choisir de l’envoyer au compte actuel."
        case .remoteRemoved: return "Un élément a été retiré d’iCloud pendant le transfert. Tes copies locales sont conservées. Relance la synchronisation pour récupérer les changements."
        }
    }
}

extension Notification.Name {
    static let easyPasteCloudChange = Notification.Name("EasyPaste.cloudChange")
}
