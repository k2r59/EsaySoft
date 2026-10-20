import Foundation

enum BWRegion: String, Codable, CaseIterable {
    case europe, international
    var label: String { self == .europe ? "Europe · bitwarden.eu" : "International · bitwarden.com" }
    var domain: String { self == .europe ? "bitwarden.eu" : "bitwarden.com" }
    var api: URL { URL(string: "https://api.\(domain)")! }
    var identity: URL { URL(string: "https://identity.\(domain)")! }
    var vault: URL { URL(string: "https://vault.\(domain)/#/sends")! }
    func link(accessID: String, secret: Data) throws -> URL {
        guard !accessID.isEmpty, accessID.count < 150,
              accessID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }), secret.count == 16 else { throw BWError.invalidResponse }
        return URL(string: "https://send.\(domain)/#\(accessID)/\(secret.base64URLEncoded)")!
    }
}

enum BWError: LocalizedError, Equatable {
    case disabled, locked, invalidResponse, invalidCipher, unsupportedKDF, invalidCredentials
    case twoFactor([Int]), newDevice, captcha, unsupportedAuthentication, expiredSession
    case clientUpdateRequired, unsupportedEncryption, loginRejected(Int), invalidVerificationCode, tooManyAttempts
    case premium, server(Int), network, tooLarge, textTooLarge, invalidFile, emptyText, invalidEmails, cancelled
    case keychain(Int32), storage, partialUpload(String), unknownCreation
    var errorDescription: String? {
        switch self {
        case .disabled: return "Active Bitwarden dans les réglages."
        case .locked: return "Déverrouille Bitwarden pour continuer."
        case .invalidResponse: return "Réponse Bitwarden non reconnue. Aucun nouveau lien n’a été copié."
        case .invalidCipher: return "Le contenu chiffré n’a pas pu être vérifié."
        case .unsupportedKDF: return "Les paramètres de chiffrement de ce compte dépassent les limites prises en charge par EasyPaste."
        case .invalidCredentials: return "Bitwarden ne reconnaît pas cette adresse ou ce mot de passe maître sur le serveur choisi. Vérifie-les dans l’app officielle."
        case .clientUpdateRequired: return "Bitwarden refuse la version du client EasyPaste. Une mise à jour d’EasyPaste est nécessaire ; ce refus ne signale pas un mauvais mot de passe."
        case .unsupportedEncryption: return "Ce compte utilise une version de chiffrement que cette intégration ne prend pas encore en charge. Utilise Bitwarden pour créer le partage."
        case .loginRejected(let status): return "Bitwarden refuse la connexion (HTTP \(status)). La cause n’est pas identifiée ; ce message ne confirme pas un mauvais mot de passe."
        case .invalidVerificationCode: return "Le code de vérification a été refusé. Saisis un nouveau code."
        case .tooManyAttempts: return "Bitwarden limite temporairement les tentatives. Patiente avant de réessayer."
        case .twoFactor: return "Saisis le code de vérification Bitwarden."
        case .newDevice: return "Bitwarden a envoyé un code par e-mail pour vérifier ce nouvel appareil."
        case .captcha: return "Bitwarden demande une vérification CAPTCHA. Connecte-toi dans son application officielle avant de réessayer."
        case .unsupportedAuthentication: return "Cette méthode de connexion n’est pas prise en charge ici. EasyPaste accepte le mot de passe maître et les codes d’authentification ou d’e-mail."
        case .expiredSession: return "La session Bitwarden n’est plus valide. Reconnecte ton compte."
        case .premium: return "Cette option nécessite Bitwarden Premium ou un abonnement compatible."
        case .server(let code): return "Bitwarden a refusé la demande (\(code)). Réessaie plus tard."
        case .network: return "Connexion à Bitwarden impossible. Vérifie ta connexion Internet."
        case .tooLarge: return "Ce fichier dépasse la limite de 500 Mo."
        case .textTooLarge: return "Ce texte dépasse la limite de Bitwarden Send. Partage-le sous forme de fichier."
        case .invalidFile: return "Choisis un seul fichier local, disponible sur ce Mac. Les dossiers ne sont pas pris en charge."
        case .emptyText: return "Le contenu à partager est vide."
        case .invalidEmails: return "Saisis de 1 à 20 adresses e-mail valides, séparées par des virgules ou des retours à la ligne."
        case .cancelled: return "Opération annulée."
        case .keychain: return "Accès au trousseau refusé. Réessaie et valide la demande macOS."
        case .storage: return "Impossible de mémoriser la connexion dans le trousseau."
        case .partialUpload: return "L’envoi a échoué et le partage incomplet n’a pas pu être supprimé. Retrouve-le dans « Mes partages »."
        case .unknownCreation: return "La confirmation du serveur n’a pas été reçue. Vérifie « Mes partages » avant de réessayer pour éviter un doublon."
        }
    }
}

struct BWKDF: Sendable {
    var type: Int; var iterations: Int; var memory: Int?; var parallelism: Int?
    init(json: [String: Any]) throws {
        guard let type = json.bwInt("kdf"), let iterations = json.bwInt("kdfIterations") else { throw BWError.invalidResponse }
        self.type = type; self.iterations = iterations; memory = json.bwInt("kdfMemory"); parallelism = json.bwInt("kdfParallelism")
    }
    init(type: Int = 0, iterations: Int = 600_000, memory: Int? = nil, parallelism: Int? = nil) {
        self.type = type; self.iterations = iterations; self.memory = memory; self.parallelism = parallelism
    }
}

struct BWSession: Codable, Sendable {
    var email: String; var region: BWRegion; var refreshToken: String; var userKey: Data
    var accessToken: String; var expires: Date
}

enum BWAudience: String, CaseIterable, Sendable { case link, emails
    var title: String { self == .link ? "Toute personne disposant du lien" : "Adresses e-mail précises" }
}
struct BWSendOptions: Sendable {
    var name = ""; var days = 7; var audience: BWAudience = .link; var emails = ""; var password = ""
    func recipients() throws -> [String] {
        guard audience == .emails else { return [] }
        let parts = emails.split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        var seen = Set<String>()
        let values = parts.filter { seen.insert($0).inserted }
        guard !values.isEmpty, values.count <= 20, values.joined(separator: ",").count <= 2500, values.allSatisfy({ email in
            email.utf8.count <= 254 && email.range(of: #"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$"#, options: [.caseInsensitive, .regularExpression]) != nil
        }) else { throw BWError.invalidEmails }
        return values
    }
    func validate() throws {
        guard [1, 3, 7, 14, 30].contains(days), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 400, password.utf8.count <= 1024 else { throw BWError.invalidResponse }
        _ = try recipients()
    }
}

enum BWContent: Sendable {
    case text(String)
    case file(URL, name: String)
    var isFile: Bool { if case .file = self { return true }; return false }
}
struct BWSend: Identifiable, Sendable {
    let id: String; let name: String; let link: URL; let deletion: Date?; let isFile: Bool; let accessCount: Int
}
struct BWPreparedSend: Sendable {
    let body: Data; let secret: Data; let encryptedFile: URL?
}

extension Data {
    var base64URLEncoded: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
extension Dictionary where Key == String, Value == Any {
    func bwValue(_ key: String) -> Any? { self[key] ?? first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value }
    func bwString(_ key: String) -> String? { bwValue(key) as? String }
    func bwInt(_ key: String) -> Int? { guard let n = bwValue(key) as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue, abs(n.doubleValue) < 1e10 else { return nil }; return n.intValue }
}
