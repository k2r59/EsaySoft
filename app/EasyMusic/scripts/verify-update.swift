import Foundation
import CryptoKit

// Public-key verification only: never opens the Keychain or reads a private key.
guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4,
      let keyData = Data(base64Encoded: CommandLine.arguments[1]) else {
    fatalError("Usage: swift verify-update.swift public-key file [signature]")
}
let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let signedData: Data
let signature: Data
if CommandLine.arguments.count == 4 {
    guard let decoded = Data(base64Encoded: CommandLine.arguments[3]) else { exit(1) }
    signature = decoded
    signedData = data
} else {
    let marker = Data("<!-- sparkle-signatures:".utf8)
    guard let range = data.range(of: marker, options: .backwards),
          let footer = String(data: data[range.lowerBound...], encoding: .utf8) else { exit(1) }
    let fields = footer.components(separatedBy: .newlines)
    guard let sigLine = fields.first(where: { $0.hasPrefix("edSignature: ") }),
          let lengthLine = fields.first(where: { $0.hasPrefix("length: ") }),
          let decoded = Data(base64Encoded: String(sigLine.dropFirst("edSignature: ".count))),
          let length = Int(lengthLine.dropFirst("length: ".count)),
          length == range.lowerBound,
          footer.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("-->") else { exit(1) }
    signature = decoded
    signedData = data.prefix(length)
}
guard key.isValidSignature(signature, for: signedData) else {
    fputs("Signature invalide.\n", stderr)
    exit(1)
}
print("Signature valide.")
