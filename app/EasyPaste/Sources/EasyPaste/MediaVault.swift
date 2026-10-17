import Foundation
import CryptoKit

/// Video files are authenticated in bounded chunks: neither playback nor import loads a movie into RAM.
enum MediaVault {
    static let chunkSize = 1_048_576
    static let limit = 1_000_000_000
    struct Header: Codable { let version: Int; let bytes: Int; let chunks: Int }
    static func invalid() -> NSError { NSError(domain: "EasyPaste.Media", code: 1, userInfo: [NSLocalizedDescriptionKey: "La vidéo est incomplète ou son intégrité ne peut pas être vérifiée."]) }
    static func context(_ id: UUID, _ index: Int) -> Data { Data("EasyPaste.video.v1.\(id.uuidString).\(index)".utf8) }
    static func writeRecord(_ data: Data, to file: FileHandle) throws {
        var size = UInt32(data.count).bigEndian
        try file.write(contentsOf: withUnsafeBytes(of: &size) { Data($0) })
        try file.write(contentsOf: data)
    }
    static func exact(_ count: Int, from file: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let part = try file.read(upToCount: count - result.count), !part.isEmpty else { throw invalid() }
            result.append(part)
        }
        return result
    }
    static func readRecord(from file: FileHandle) throws -> Data {
        let size = try exact(4, from: file).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size >= 28, size <= chunkSize + 1024 else { throw invalid() }
        return try exact(Int(size), from: file)
    }
    static func encrypt(_ source: URL, to destination: URL, id: UUID, key: SymmetricKey) throws -> Int {
        // A recorder URL may still cache the zero-byte size observed while recording.
        // Read the finalized file itself, using the same handle that will be encrypted.
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        guard length > 0 else { throw CaptureFailure.message("L’enregistrement est vide. Relance une courte capture vidéo.") }
        guard length <= UInt64(limit) else { throw CaptureFailure.message("La vidéo doit faire moins de 1 Go.") }
        let size = Int(length)
        try input.seek(toOffset: 0)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        let header = Header(version: 1, bytes: size, chunks: (size + chunkSize - 1) / chunkSize)
        try writeRecord(AES.GCM.seal(JSONEncoder().encode(header), using: key, authenticating: context(id, -1)).combined!, to: output)
        var consumed = 0
        for index in 0..<header.chunks {
            let block = try exact(min(chunkSize, size - consumed), from: input)
            try writeRecord(AES.GCM.seal(block, using: key, authenticating: context(id, index)).combined!, to: output)
            consumed += block.count
        }
        guard (try input.read(upToCount: 1))?.isEmpty != false else { throw invalid() }
        try output.synchronize(); try output.close()
        try FileManager.default.moveItem(at: temporary, to: destination)
        return size
    }
    static func decrypt(_ source: URL, to destination: URL, id: UUID, key: SymmetricKey) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: temporary)
        defer { try? input.close(); try? output.close() }
        let headerData = try AES.GCM.open(AES.GCM.SealedBox(combined: readRecord(from: input)), using: key, authenticating: context(id, -1))
        let header = try JSONDecoder().decode(Header.self, from: headerData)
        guard header.version == 1, header.bytes > 0, header.bytes <= limit, header.chunks == (header.bytes + chunkSize - 1) / chunkSize else { throw invalid() }
        var written = 0
        for index in 0..<header.chunks {
            let block = try AES.GCM.open(AES.GCM.SealedBox(combined: readRecord(from: input)), using: key, authenticating: context(id, index))
            guard block.count == min(chunkSize, header.bytes - written) else { throw invalid() }
            try output.write(contentsOf: block); written += block.count
        }
        guard (try input.read(upToCount: 1))?.isEmpty != false else { throw invalid() }
        try output.synchronize(); try output.close()
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
}
