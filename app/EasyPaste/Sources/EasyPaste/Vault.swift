import Foundation
import CryptoKit
import Security

/// Individual encrypted records allow atomic updates without rewriting the entire history.
final class ClipVault: Sendable {
    let directory:URL
    private let key:SymmetricKey
    init(directory:URL?=nil,key:SymmetricKey?=nil)throws {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("EasyPaste/Vault",isDirectory:true)
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        self.key=try key ?? Self.loadKey()
    }
    static func loadKey()throws->SymmetricKey {
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.easypaste.mac.vault",kSecAttrAccount as String:"local-history",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result:CFTypeRef?
        let status=SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecSuccess,let data=result as? Data,data.count==32{return SymmetricKey(data:data)}
        guard status == errSecItemNotFound else {throw NSError(domain:"EasyPaste.Keychain",code:Int(status),userInfo:[NSLocalizedDescriptionKey:"Impossible d’ouvrir la clé de l’historique dans le trousseau (\(status)). Aucun historique n’a été remplacé."])}
        let key=SymmetricKey(size:.bits256);let data=key.withUnsafeBytes{Data($0)}
        let add:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"app.easypaste.mac.vault",kSecAttrAccount as String:"local-history",kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let inserted=SecItemAdd(add as CFDictionary,nil)
        guard inserted == errSecSuccess else{throw NSError(domain:"EasyPaste.Keychain",code:Int(inserted),userInfo:[NSLocalizedDescriptionKey:"Impossible de créer la clé locale du trousseau."])}
        return key
    }
    func write<T:Encodable>(_ value:T,name:String)throws {
        let clear=try JSONEncoder().encode(value)
        let box=try AES.GCM.seal(clear,using:key)
        try box.combined!.write(to:directory.appendingPathComponent(name),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:directory.appendingPathComponent(name).path)
    }
    func read<T:Decodable>(_ type:T.Type,name:String)throws->T {
        let data=try Data(contentsOf:directory.appendingPathComponent(name))
        let clear=try AES.GCM.open(AES.GCM.SealedBox(combined:data),using:key)
        return try JSONDecoder().decode(type,from:clear)
    }
    func load(metadataOnly:Bool=false)throws->[Clip] {
        let urls=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil).filter{$0.pathExtension=="clip"}
        return try urls.map{url in let c=try read(Clip.self,name:url.lastPathComponent);return metadataOnly ? c.metadata() : c}.sorted{$0.date>$1.date}
    }
    func loadBoards() throws -> [Pinboard] {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("boards.json.enc").path) ? try read([Pinboard].self, name: "boards.json.enc") : []
    }
    func save(_ c:Clip)throws {try write(c,name:c.id.uuidString+".clip")}
    func delete(_ id:UUID)throws {
        for item in [mediaURL(id), playbackDirectory.appendingPathComponent(id.uuidString + ".mp4")] where FileManager.default.fileExists(atPath: item.path) { try FileManager.default.removeItem(at: item) }
        let url=directory.appendingPathComponent(id.uuidString+".clip");if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)}}
}


extension ClipVault {
    func mediaURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".movie.enc") }
    var playbackDirectory: URL {
        let identifier = SHA256.hash(data: Data(directory.path.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-playback-" + identifier, isDirectory: true)
    }
    func importVideo(_ source: URL, id: UUID) throws -> Int {
        try MediaVault.encrypt(source, to: mediaURL(id), id: id, key: key)
    }
    func videoURL(_ id: UUID) throws -> URL {
        let folder = playbackDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent(id.uuidString + ".mp4")
        if !FileManager.default.fileExists(atPath: url.path) { try MediaVault.decrypt(mediaURL(id), to: url, id: id, key: key) }
        return url
    }
    func cleanPlaybackCache() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: playbackDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls {
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, Date().timeIntervalSince(date) > 86400 { try? FileManager.default.removeItem(at: url) }
        }
    }
}
