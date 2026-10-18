import Foundation
import CloudKit

struct CloudCheckpoint: Codable {
    var sequence: UInt64 = 0
    var account: String?
    var engine: CKSyncEngine.State.Serialization?
    var acknowledged: [String: CloudHeader] = [:]
    var systemFields: [String: Data] = [:]
    var movieFingerprints: [String: String] = [:]
}

struct PreparedCloudContent: Sendable {
    let header: CloudHeader
    let directory: URL
    let content: URL?
    let movie: URL?
    let movieFingerprint: String?
}

extension ClipVault {
    func notifyCloud(_ key: CloudKey) {
        NotificationCenter.default.post(name: .easyPasteCloudChange, object: self, userInfo: ["key": key.name])
    }
    func hasCloudTombstone(_ key: CloudKey) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(key.name + ".deleted.enc").path)
    }
    func writeCloudTombstone(_ header: CloudHeader) throws {
        try write(header, name: header.key.name + ".deleted.enc")
    }
    func cloudHeader(_ key: CloudKey) throws -> CloudHeader? {
        try locked {
            if hasCloudTombstone(key) { return try read(CloudHeader.self, name: key.name + ".deleted.enc") }
            switch key.kind {
            case .clip:
                let name = key.id.uuidString + ".clip"
                guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) else { return nil }
                let clip = try read(Clip.self, name: name)
                guard clip.kind != .file else { return nil } // Finder references point to this Mac, not transferable files.
                return .init(key: key, revision: clip.cloudRevision ?? .init(date: clip.date, nonce: key.name))
            case .board:
                guard let board = try loadBoards().first(where: { $0.id == key.id }) else { return nil }
                return .init(key: key, revision: board.cloudRevision ?? .init(date: .distantPast, nonce: key.name))
            }
        }
    }
    func saveBoards(_ input: [Pinboard], replacing snapshot: [Pinboard]? = nil) throws {
        try locked {
            let previous = try loadBoards()
            let baseline = snapshot ?? previous
            let removed = baseline.filter { old in !input.contains { $0.id == old.id } }
            for board in removed {
                try writeCloudTombstone(.init(key: CloudKey(.board,board.id), revision: .next(after: board.cloudRevision), deleted: true))
            }
            var boards = previous.filter { old in !removed.contains { $0.id == old.id } }
            for board in input where !hasCloudTombstone(CloudKey(.board,board.id)) {
                let original = baseline.first { $0.id == board.id }
                // A stale UI snapshot is not permission to overwrite an unrelated remote collection.
                guard original?.name != board.name || original?.color != board.color || original?.shared != board.shared else { continue }
                var value = board
                let old = previous.first { $0.id == board.id }
                if original?.name == board.name, let old { value.name = old.name }
                if original?.color == board.color, let old { value.color = old.color }
                if original?.shared == board.shared, let old { value.shared = old.shared }
                value.cloudRevision = old?.name == value.name && old?.color == value.color
                    ? old?.cloudRevision : .next(after: old?.cloudRevision)
                boards.removeAll { $0.id == board.id }; boards.append(value)
            }
            try write(boards, name: "boards.json.enc")
            for board in removed { notifyCloud(CloudKey(.board,board.id)) }
            for board in boards where board.cloudRevision != previous.first(where: { $0.id == board.id })?.cloudRevision {
                notifyCloud(CloudKey(.board,board.id))
            }
        }
    }
    func cloudInventory() throws -> [CloudHeader] {
        try locked {
            var items = try load(metadataOnly: true).filter { $0.kind != .file }.map { clip in
                CloudHeader(key: CloudKey(.clip,clip.id), revision: clip.cloudRevision ?? .init(date: clip.date, nonce: CloudKey(.clip,clip.id).name))
            }
            items += try loadBoards().map { board in
                CloudHeader(key: CloudKey(.board,board.id), revision: board.cloudRevision ?? .init(date: .distantPast, nonce: CloudKey(.board,board.id).name))
            }
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where url.lastPathComponent.hasSuffix(".deleted.enc") {
                items.append(try read(CloudHeader.self, name: url.lastPathComponent))
            }
            return items
        }
    }
    func cloudCheckpoint() throws -> CloudCheckpoint {
        try locked {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("cloud-state.enc").path) else { return .init() }
            return try read(CloudCheckpoint.self, name: "cloud-state.enc")
        }
    }
    func saveCloudCheckpoint(_ checkpoint: CloudCheckpoint) throws {
        try locked {
            guard checkpoint.sequence > (try cloudCheckpoint()).sequence else { return }
            try write(checkpoint, name: "cloud-state.enc")
        }
    }
    var cloudStaging: URL { directory.appendingPathComponent("CloudTransfers", isDirectory: true) }
    func cleanCloudStaging() throws {
        if FileManager.default.fileExists(atPath: cloudStaging.path) { try FileManager.default.removeItem(at: cloudStaging) }
    }
    func prepareCloudContent(_ key: CloudKey, uploadedMovie: String?) throws -> PreparedCloudContent? {
        try locked {
            guard let header = try cloudHeader(key) else { return nil }
            let folder = cloudStaging.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            do {
                if header.deleted { return .init(header: header, directory: folder, content: nil, movie: nil, movieFingerprint: nil) }
                var content = CloudContent()
                var movie: URL?, fingerprint: String?
                if key.kind == .clip {
                    var clip = try read(Clip.self, name: key.id.uuidString + ".clip")
                    clip.cloudRevision = header.revision
                    if clip.kind == .video {
                        fingerprint = clip.fingerprint
                        if uploadedMovie != clip.fingerprint {
                            let url = folder.appendingPathComponent("video.mp4")
                            try requireCloudSpace(clip.byteCount + 64 * 1024 * 1024)
                            // Stream-decrypt in bounded chunks; do not load a video into RAM.
                            try exportCloudMovie(key.id, to: url)
                            movie = url
                        }
                    }
                    content.clip = clip
                } else {
                    guard var board = try loadBoards().first(where: { $0.id == key.id }) else { throw CloudFailure.invalidData }
                    board.shared = false // MCP authorizations remain per-Mac and never travel through iCloud.
                    board.cloudRevision = header.revision; content.board = board
                }
                let data = try JSONEncoder().encode(content)
                guard data.count <= 64 * 1024 * 1024 else { throw CloudFailure.invalidData }
                let url = folder.appendingPathComponent("content.json")
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                return .init(header: header, directory: folder, content: url, movie: movie, movieFingerprint: fingerprint)
            } catch { try? FileManager.default.removeItem(at: folder); throw error }
        }
    }
    func requireCloudSpace(_ bytes: Int) throws {
        let info = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let free = info.volumeAvailableCapacityForImportantUsage, free < Int64(bytes) + 128 * 1024 * 1024 { throw CloudFailure.storageFull }
    }
    /// Returns the winning header. All work is serialized with normal local writes.
    func applyCloud(_ header: CloudHeader, contentURL: URL?, movieURL: URL?) throws -> CloudHeader {
        try locked {
            guard header.format == 1 else { throw CloudFailure.unsupportedVersion }
            let local = try cloudHeader(header.key)
            guard header.wins(over: local) else { return local ?? header }
            if header.deleted {
                try writeCloudTombstone(header) // Durable before removing files; a crash cannot resurrect this ID.
                if header.key.kind == .clip { try removeClipFiles(header.key.id) }
                else {
                    let boards = try loadBoards().filter { $0.id != header.key.id }
                    try write(boards, name: "boards.json.enc")
                }
                return header
            }
            guard let contentURL,
                  let size = try URL(fileURLWithPath: contentURL.path).resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 64 * 1024 * 1024 else { throw CloudFailure.invalidData }
            let content = try JSONDecoder().decode(CloudContent.self, from: Data(contentsOf: contentURL))
            if header.key.kind == .clip {
                guard var clip = content.clip, content.board == nil, clip.id == header.key.id, clip.kind != .file,
                      clip.payload.representations.flatMap({$0}).reduce(0, { $0 + $1.data.count }) <= ClipboardReader.limit,
                      clip.cloudRevision == header.revision, clip.byteCount >= 0, clip.byteCount <= MediaVault.limit,
                      clip.thumbnail?.count ?? 0 <= ClipboardReader.limit,
                      clip.duration == nil || (clip.duration!.isFinite && clip.duration! >= 0 && clip.duration! < Double(Int.max / 2)) else { throw CloudFailure.invalidData }
                clip.boards = clip.boards.filter { !hasCloudTombstone(CloudKey(.board,$0)) }
                try requireCloudSpace(clip.byteCount + size)
                if clip.kind == .video {
                    let existingMedia = FileManager.default.fileExists(atPath: mediaURL(clip.id).path)
                    if existingMedia, let local, !local.deleted {
                        let old = try read(Clip.self, name: clip.id.uuidString + ".clip")
                        // Videos are immutable; annotation and edited media use a fresh UUID.
                        // Avoid rewriting a whole movie for a title, collection or favorite change.
                        guard old.kind == .video, old.fingerprint == clip.fingerprint else { throw CloudFailure.invalidData }
                        clip.storedBytes = old.storedBytes
                    } else if let movieURL {
                        let incoming = mediaURL(clip.id).appendingPathExtension("incoming")
                        if FileManager.default.fileExists(atPath: incoming.path) { try FileManager.default.removeItem(at: incoming) }
                        defer { try? FileManager.default.removeItem(at: incoming) }
                        clip.storedBytes = try encryptCloudMovie(movieURL, to: incoming, id: clip.id)
                        if FileManager.default.fileExists(atPath: mediaURL(clip.id).path) {
                            _ = try FileManager.default.replaceItemAt(mediaURL(clip.id), withItemAt: incoming)
                        } else { try FileManager.default.moveItem(at: incoming, to: mediaURL(clip.id)) }
                    } else { throw CloudFailure.invalidData }
                }
                try write(clip, name: clip.id.uuidString + ".clip")
            } else {
                guard var board = content.board, content.clip == nil, board.id == header.key.id,
                      board.cloudRevision == header.revision, (0...3).contains(board.color), board.name.count <= 40 else { throw CloudFailure.invalidData }
                var boards = try loadBoards()
                board.shared = boards.first(where: { $0.id == board.id })?.shared ?? false
                boards.removeAll { $0.id == board.id }; boards.append(board)
                try write(boards, name: "boards.json.enc")
            }
            return header
        }
    }
}
