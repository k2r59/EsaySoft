import Foundation
import CryptoKit
import CommonCrypto
import Security
import CArgon2

/// A single KDF at a time, even after rapid cancellation/reconnection attempts.
actor BWDerivation {
    static let shared = BWDerivation()
    func masterKey(password: String, email: String, kdf: BWKDF) throws -> Data {
        try Task.checkCancellation()
        let key = try BWCrypto.masterKey(password: password, email: email, kdf: kdf)
        try Task.checkCancellation(); return key
    }
}

/// Wire-format compatibility implemented with Apple cryptography primitives.
/// No Bitwarden SDK/client code is linked. See docs/bitwarden.md for protocol references.
enum BWCrypto {
    static let maxFileBytes = 500 * 1024 * 1024
    static func random(_ count: Int) throws -> Data {
        var data = Data(count: count)
        guard data.withUnsafeMutableBytes({ SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }) == errSecSuccess else { throw BWError.invalidCipher }
        return data
    }
    static func pbkdf(_ password: Data, salt: Data, iterations: Int) throws -> Data {
        guard (1...2_000_000).contains(iterations), !password.isEmpty else { throw BWError.unsupportedKDF }
        var result = Data(count: 32)
        let status = result.withUnsafeMutableBytes { out in password.withUnsafeBytes { pwd in salt.withUnsafeBytes { s in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwd.baseAddress!.assumingMemoryBound(to: CChar.self), password.count,
                                s.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), out.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
        } } }
        guard status == kCCSuccess else { throw BWError.invalidCipher }; return result
    }
    static func masterKey(password: String, email: String, kdf: BWKDF) throws -> Data {
        guard !password.isEmpty, password.utf8.count <= 4096, email.utf8.count <= 254 else { throw BWError.invalidCredentials }
        let pwd = Data(password.utf8), salt = Data(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().utf8)
        switch kdf.type {
        case 0: return try pbkdf(pwd, salt: salt, iterations: kdf.iterations)
        case 1:
            // Bound hostile or accidental KDF costs. Never run this on the main actor.
            guard (1...10).contains(kdf.iterations), let memory = kdf.memory, (16...256).contains(memory),
                  let lanes = kdf.parallelism, (1...16).contains(lanes) else { throw BWError.unsupportedKDF }
            let hashedSalt = Data(SHA256.hash(data: salt)); var result = Data(count: 32)
            let status = result.withUnsafeMutableBytes { out in pwd.withUnsafeBytes { p in hashedSalt.withUnsafeBytes { s in
                argon2id_hash_raw(UInt32(kdf.iterations), UInt32(memory * 1024), UInt32(lanes), p.baseAddress, pwd.count, s.baseAddress, hashedSalt.count, out.baseAddress, 32)
            } } }
            guard status == ARGON2_OK.rawValue else { throw BWError.invalidCipher }; return result
        default: throw BWError.unsupportedKDF
        }
    }
    static func passwordHash(master: Data, password: String) throws -> String { try pbkdf(master, salt: Data(password.utf8), iterations: 1).base64EncodedString() }
    static func expand(_ key: Data, info: String, count: Int) -> Data {
        let value = HKDF<SHA256>.expand(pseudoRandomKey: SymmetricKey(data: key), info: Data(info.utf8), outputByteCount: count)
        return value.withUnsafeBytes { Data($0) }
    }
    static func stretched(_ master: Data) -> Data { expand(master, info: "enc", count: 32) + expand(master, info: "mac", count: 32) }
    static func sendKey(_ secret: Data) throws -> Data {
        guard secret.count == 16 else { throw BWError.invalidCipher }
        let prk = Data(HMAC<SHA256>.authenticationCode(for: secret, using: SymmetricKey(data: Data("bitwarden-send".utf8))))
        return expand(prk, info: "send", count: 64)
    }
    static func aes(_ data: Data, key: Data, iv: Data, decrypt: Bool = false) throws -> Data {
        guard key.count == 32, iv.count == 16 else { throw BWError.invalidCipher }
        var output = Data(count: data.count + 16); let capacity = output.count; var length = 0
        let result = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, 32, v.baseAddress, input.baseAddress, data.count, out.baseAddress, capacity, &length)
        } } } }
        guard result == kCCSuccess else { throw BWError.invalidCipher }
        output.count = length; return output
    }
    static func encrypt(_ data: Data, key: Data, iv fixedIV: Data? = nil) throws -> String {
        guard key.count == 64 else { throw BWError.invalidCipher }
        let iv = try fixedIV ?? random(16), ciphertext = try aes(data, key: key.prefix(32), iv: iv)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: iv + ciphertext, using: SymmetricKey(data: key.suffix(32))))
        return "2." + [iv, ciphertext, mac].map { $0.base64EncodedString() }.joined(separator: "|")
    }
    static func decrypt(_ string: String, key: Data) throws -> Data {
        guard key.count == 64, string.hasPrefix("2."), string.utf8.count <= 2_000_000 else { throw BWError.invalidCipher }
        let parts = string.dropFirst(2).split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, let iv = Data(base64Encoded: String(parts[0])), iv.count == 16,
              let cipher = Data(base64Encoded: String(parts[1])), !cipher.isEmpty, cipher.count % 16 == 0,
              let mac = Data(base64Encoded: String(parts[2])), mac.count == 32,
              HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: iv + cipher, using: SymmetricKey(data: key.suffix(32))) else { throw BWError.invalidCipher }
        return try aes(cipher, key: key.prefix(32), iv: iv, decrypt: true)
    }
    static func fileSize(_ url: URL) throws -> Int {
        guard url.isFileURL else { throw BWError.invalidFile }
        let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard value.isRegularFile == true, value.isSymbolicLink != true, let size = value.fileSize else { throw BWError.invalidFile }
        guard size <= maxFileBytes else { throw BWError.tooLarge }; return size
    }
    /// 1 MiB chunks: memory stays bounded for videos. Only ciphertext is written to disk.
    static func encryptFile(_ source: URL, key: Data, destination: URL, cancelled: () -> Bool = { Task.isCancelled }) throws -> Int {
        guard key.count == 64 else { throw BWError.invalidCipher }
        let expected = try fileSize(source), iv = try random(16)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw BWError.storage }
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: destination) } }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { k in iv.withUnsafeBytes { v in CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), k.baseAddress, 32, v.baseAddress, &cryptor) } }
        guard status == kCCSuccess, let cryptor else { throw BWError.invalidCipher }
        defer { CCCryptorRelease(cryptor) }
        try output.write(contentsOf: Data([2]) + iv + Data(count: 32))
        var mac = HMAC<SHA256>(key: SymmetricKey(data: key.suffix(32))); mac.update(data: iv)
        var read = 0, written = 49
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            if cancelled() { throw CancellationError() }; read += chunk.count
            guard read <= expected else { throw BWError.invalidFile }
            var encrypted = Data(count: chunk.count + 16); let capacity = encrypted.count; var count = 0
            let result = encrypted.withUnsafeMutableBytes { out in chunk.withUnsafeBytes { data in CCCryptorUpdate(cryptor, data.baseAddress, chunk.count, out.baseAddress, capacity, &count) } }
            guard result == kCCSuccess else { throw BWError.invalidCipher }; encrypted.count = count
            mac.update(data: encrypted); try output.write(contentsOf: encrypted); written += count
        }
        guard read == expected else { throw BWError.invalidFile }
        if cancelled() { throw CancellationError() }
        var tail = Data(count: 16); var count = 0
        guard tail.withUnsafeMutableBytes({ CCCryptorFinal(cryptor, $0.baseAddress, 16, &count) }) == kCCSuccess else { throw BWError.invalidCipher }
        tail.count = count; mac.update(data: tail); try output.write(contentsOf: tail); written += count
        try output.seek(toOffset: 17); try output.write(contentsOf: Data(mac.finalize())); success = true; return written
    }
    static func prepare(content: BWContent, options: BWSendOptions, userKey: Data, directory: URL, now: Date = Date()) throws -> BWPreparedSend {
        try options.validate(); try Task.checkCancellation()
        let secret = try random(16), key = try sendKey(secret)
        let date = ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(options.days) * 86400))
        var body: [String: Any] = ["type": content.isFile ? 1 : 0, "name": try encrypt(Data(options.name.utf8), key: key),
                                  "key": try encrypt(secret, key: userKey), "deletionDate": date, "expirationDate": date,
                                  "disabled": false, "hideEmail": true, "authType": 2]
        let recipients = try options.recipients()
        if !recipients.isEmpty { body["authType"] = 0; body["emails"] = recipients.joined(separator: ",") }
        else if !options.password.isEmpty { body["authType"] = 1; body["password"] = try pbkdf(Data(options.password.utf8), salt: secret, iterations: 100_000).base64EncodedString() }
        var file: URL?
        switch content {
        case .text(let text):
            guard !text.isEmpty else { throw BWError.emptyText }
            guard text.utf8.count <= 700 else { throw BWError.textTooLarge }
            let encrypted = try encrypt(Data(text.utf8), key: key)
            guard encrypted.count <= 1000 else { throw BWError.textTooLarge }
            body["text"] = ["text": encrypted, "hidden": false]
        case .file(let source, let name):
            guard !name.isEmpty, name.utf8.count <= 255 else { throw BWError.invalidFile }
            let dest = directory.appendingPathComponent(UUID().uuidString + ".encrypted")
            body["fileLength"] = try encryptFile(source, key: key, destination: dest)
            body["file"] = ["fileName": try encrypt(Data(name.utf8), key: key)]; file = dest
        }
        do { return BWPreparedSend(body: try JSONSerialization.data(withJSONObject: body), secret: secret, encryptedFile: file) }
        catch { if let file { try? FileManager.default.removeItem(at: file) }; throw error }
    }
}
