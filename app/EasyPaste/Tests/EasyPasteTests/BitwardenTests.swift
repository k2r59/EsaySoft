import XCTest
import AppKit
import SwiftUI
import CryptoKit
@testable import EasyPaste

final class BitwardenCryptoTests: XCTestCase {
    let key = Data((0..<64).map(UInt8.init))
    func testOfficialPBKDFAndArgon2PasswordHashVectors() throws {
        for email in ["test@bitwarden.com", " TEST@bitwarden.com "] {
            let master = try BWCrypto.masterKey(password: "asdfasdf", email: email, kdf: BWKDF(iterations: 100_000))
            XCTAssertEqual(try BWCrypto.passwordHash(master: master, password: "asdfasdf"), "wmyadRMyBZOH7P/a/ucTCbSghKgdzDpPqUnu/DAVtSw=")
        }
        let master = try BWCrypto.masterKey(password: "asdfasdf", email: "test_salt", kdf: BWKDF(type: 1, iterations: 4, memory: 32, parallelism: 2))
        XCTAssertEqual(try BWCrypto.passwordHash(master: master, password: "asdfasdf"), "PR6UjYmjmppTYcdyTiNbAhPJuQQOmynKbdEl1oyi/iQ=")
    }
    func testHKDFExpandRFC5869() {
        let prk = hex("077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5")
        // RFC test case 3 has empty info and the following PRK.
        let emptyPRK = hex("19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04")
        XCTAssertEqual(BWCrypto.expand(emptyPRK, info: "", count: 42), hex("8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"))
        XCTAssertEqual(prk.count, 32)
    }
    func testSendKeyHKDFUsesBitwardenSendSalt() throws {
        let seed = Data(repeating: 0x41, count: 16)
        let expected = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: seed), salt: Data("bitwarden-send".utf8), info: Data("send".utf8), outputByteCount: 64)
        XCTAssertEqual(try BWCrypto.sendKey(seed), expected.withUnsafeBytes { Data($0) })
        XCTAssertThrowsError(try BWCrypto.sendKey(Data(count: 15)))
    }
    func testCipherAuthenticationAndMalformedInputs() throws {
        let original = Data("Été 🐈 <script> & \0 secret".utf8)
        let cipher = try BWCrypto.encrypt(original, key: key)
        XCTAssertEqual(try BWCrypto.decrypt(cipher, key: key), original)
        XCTAssertNotEqual(try BWCrypto.encrypt(original, key: key), cipher)
        let parts = cipher.dropFirst(2).split(separator: "|").map(String.init)
        for field in 0..<3 {
            var values = parts; var bytes = Data(base64Encoded: values[field])!; bytes[bytes.startIndex] ^= 1; values[field] = bytes.base64EncodedString()
            XCTAssertThrowsError(try BWCrypto.decrypt("2." + values.joined(separator: "|"), key: key))
        }
        for invalid in ["", "2.", "0.abc|abc", "2.a|b|c", "2.||||", "6.abc", String(repeating: "!", count: 10000)] {
            XCTAssertThrowsError(try BWCrypto.decrypt(invalid, key: key))
        }
        for i in 0..<500 { XCTAssertThrowsError(try BWCrypto.decrypt(String(cipher.prefix(i % cipher.count)), key: key)) }
        XCTAssertThrowsError(try BWCrypto.decrypt(cipher, key: Data(repeating: 0, count: 64)))
    }
    func testHostileKDFCostsRejectedBeforeAllocation() {
        for kdf in [BWKDF(iterations: 0), BWKDF(iterations: Int.max), BWKDF(type: 4), BWKDF(type: 1, iterations: 10, memory: 10_000, parallelism: 4), BWKDF(type: 1, iterations: 1, memory: 32, parallelism: 0)] {
            XCTAssertThrowsError(try BWCrypto.masterKey(password: "secret", email: "test@example.com", kdf: kdf))
        }
        XCTAssertThrowsError(try BWKDF(json: ["kdf": true, "kdfIterations": 1000]))
    }
    func testChunkedFileRoundTripAndCancellationCleanup() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source"), encrypted = dir.appendingPathComponent("cipher")
        let data = Data((0..<(3 * 1024 * 1024 + 7)).map { UInt8($0 % 251) }); try data.write(to: source)
        let size = try BWCrypto.encryptFile(source, key: key, destination: encrypted)
        let bytes = try Data(contentsOf: encrypted)
        XCTAssertEqual(size, bytes.count); XCTAssertEqual(bytes[0], 2)
        let formatted = "2." + [Data(bytes[1..<17]), Data(bytes[49...]), Data(bytes[17..<49])].map { $0.base64EncodedString() }.joined(separator: "|")
        // Cipher parser has a deliberate small-text bound; validate the streamed file independently.
        let iv = Data(bytes[1..<17]), mac = Data(bytes[17..<49]), body = Data(bytes[49...])
        XCTAssertTrue(HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: iv + body, using: SymmetricKey(data: key.suffix(32))))
        XCTAssertEqual(try BWCrypto.aes(body, key: key.prefix(32), iv: iv, decrypt: true), data)
        XCTAssertTrue(formatted.hasPrefix("2."))
        let cancelled = dir.appendingPathComponent("cancelled")
        XCTAssertThrowsError(try BWCrypto.encryptFile(source, key: key, destination: cancelled, cancelled: { true }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.path))
        let link = dir.appendingPathComponent("symlink"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try BWCrypto.fileSize(link)); XCTAssertThrowsError(try BWCrypto.fileSize(dir))
    }
    func testPublicEmailAndPasswordPayloadsAreExclusiveAndEncrypted() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        var options = BWSendOptions(name: "Titre confidentiel")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let publicSend = try BWCrypto.prepare(content: .text("Texte secret"), options: options, userKey: key, directory: dir, now: now)
        let payload = try JSONSerialization.jsonObject(with: publicSend.body) as! [String: Any]
        XCTAssertEqual(payload["authType"] as? Int, 2); XCTAssertNil(payload["emails"]); XCTAssertNil(payload["password"])
        XCTAssertEqual(try BWCrypto.decrypt(payload["key"] as! String, key: key), publicSend.secret)
        let sendKey = try BWCrypto.sendKey(publicSend.secret)
        XCTAssertEqual(try BWCrypto.decrypt(payload["name"] as! String, key: sendKey), Data(options.name.utf8))
        XCTAssertFalse(String(data: publicSend.body, encoding: .utf8)!.contains("confidentiel"))
        XCTAssertEqual(ISO8601DateFormatter().date(from: payload["deletionDate"] as! String), now.addingTimeInterval(7*86400))
        options.audience = .emails; options.emails = "ALICE@example.com, alice@example.com;bob@example.org"; options.password = "must-not-leak"
        let restricted = try BWCrypto.prepare(content: .text("Texte"), options: options, userKey: key, directory: dir)
        let emailJSON = try JSONSerialization.jsonObject(with: restricted.body) as! [String: Any]
        XCTAssertEqual(emailJSON["authType"] as? Int, 0); XCTAssertEqual(emailJSON["emails"] as? String, "alice@example.com,bob@example.org"); XCTAssertNil(emailJSON["password"])
        options.audience = .link
        let protected = try BWCrypto.prepare(content: .text("Texte"), options: options, userKey: key, directory: dir)
        let passwordJSON = try JSONSerialization.jsonObject(with: protected.body) as! [String: Any]
        XCTAssertEqual(passwordJSON["authType"] as? Int, 1); XCTAssertNil(passwordJSON["emails"])
        XCTAssertEqual(passwordJSON["password"] as? String, try BWCrypto.pbkdf(Data(options.password.utf8), salt: protected.secret, iterations: 100000).base64EncodedString())
    }
    func testEmailLimitsAndTextLimits() throws {
        var options = BWSendOptions(name: "Test", audience: .emails)
        for email in ["", "bad", "a@", "@test.com", "a@b.com\r\nBcc:evil@x.com", String(repeating: "a", count: 260) + "@x.com"] {
            options.emails = email; XCTAssertThrowsError(try options.recipients())
        }
        options.emails = "alice@example.com\nbob@example.org"; XCTAssertEqual(try options.recipients().count, 2)
        options.days = 31; XCTAssertThrowsError(try options.validate())
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try BWCrypto.prepare(content: .text(String(repeating: "é", count: 500)), options: BWSendOptions(name: "Test"), userKey: key, directory: dir))
    }
    func testShareLinksAndUploadHostsAreStrict() throws {
        let url = try BWRegion.europe.link(accessID: "abc_123-xyz", secret: Data(repeating: 0xff, count: 16))
        XCTAssertEqual(url.host, "send.bitwarden.eu"); XCTAssertTrue(url.fragment!.contains("/")); XCTAssertNil(url.query)
        for id in ["", "../../secret", "evil?token=", "x/y", "x#y"] { XCTAssertThrowsError(try BWRegion.europe.link(accessID: id, secret: Data(count: 16))) }
        for bad in ["http://example.blob.core.windows.net/f", "https://blob.core.windows.net/f", "https://x.blob.core.windows.net.evil.org/f", "https://a:pwd@x.blob.core.windows.net/f", "https://x.blob.core.windows.net:444/f", "https://localhost/f"] { XCTAssertFalse(BWClient.safeUploadURL(URL(string: bad)!)) }
        XCTAssertTrue(BWClient.safeUploadURL(URL(string: "https://bitwardeneu.blob.core.windows.net/send/123?sv=2024-01-01&sig=abc")!))
    }
    func testFormEncodingProtectsPlusAmpersandAndUnicode() {
        let text = String(data: BWClient.form(["password": "a+b&é=", "email": "me+x@example.com"]), encoding: .utf8)!
        XCTAssertEqual(text, "email=me%2Bx%40example.com&password=a%2Bb%26%C3%A9%3D")
    }
    private func directory() throws -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    private func hex(_ s: String) -> Data { Data(stride(from: 0, to: s.count, by: 2).map { let a=s.index(s.startIndex, offsetBy:$0), b=s.index(a,offsetBy:2);return UInt8(s[a..<b],radix:16)! }) }
}

actor BWMemoryStore: BWSessionStore {
    var value: BWSession?; var reads = 0; var writes = 0; var removals = 0
    init(_ value: BWSession? = nil) { self.value = value }
    func read() throws -> BWSession { reads += 1; guard let value else { throw BWError.keychain(-25300) }; return value }
    func write(_ value: BWSession) { writes += 1; self.value = value }
    func remove() { removals += 1; value = nil }
    func counts() -> [Int] { [reads, writes, removals] }
}
actor BWTestTransport: BWTransport {
    var requests: [URLRequest] = []
    var uploadFails = false
    var delaySend = false
    var failToken = false
    func configure(uploadFails: Bool = false, delaySend: Bool = false, failToken: Bool = false) { self.uploadFails = uploadFails; self.delaySend = delaySend; self.failToken = failToken }
    func execute(_ request: URLRequest, file: URL?, progress: @escaping @Sendable (Double) -> Void) async throws -> BWHTTPResponse {
        requests.append(request)
        let path = request.url!.path
        if path.contains("prelogin") { return response(["kdf": 0, "kdfIterations": 100000]) }
        if path == "/connect/token" {
            if failToken { return response(["error":"invalid_grant"], status: 400) }
            let master = try BWCrypto.masterKey(password: "password-test", email: "me@example.com", kdf: BWKDF(iterations: 100000))
            return response(["access_token":"FAKE-ACCESS", "refresh_token":"FAKE-REFRESH", "expires_in":3600, "Key":try BWCrypto.encrypt(Data(repeating: 7, count: 64), key: BWCrypto.stretched(master))])
        }
        if request.httpMethod == "DELETE" { return response([:]) }
        if request.httpMethod == "GET" { return response(["data":[]]) }
        if request.httpMethod == "PUT" {
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-ms-blob-type"), "BlockBlob")
            XCTAssertNotNil(file); XCTAssertTrue(FileManager.default.fileExists(atPath: file!.path))
            progress(0.5); progress(1)
            return response([:], status: uploadFails ? 500 : 201)
        }
        if delaySend { try await Task.sleep(for: .seconds(1)) }
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body["id"] = "12345678-1234-1234-1234-123456789012"; body["accessId"] = "abcdef"; body["accessCount"] = 0
        if path == "/sends/file/v2" { return response(["sendResponse":body, "fileUploadType":1, "url":"https://bitwarden.blob.core.windows.net/sends/fake?sv=2024-01-01&sig=FAKE"]) }
        return response(body)
    }
    func snapshot() -> [URLRequest] { requests }
    private func response(_ json: [String: Any], status: Int = 200) -> BWHTTPResponse { BWHTTPResponse(status: status, data: try! JSONSerialization.data(withJSONObject: json)) }
}

@MainActor final class BitwardenIntegrationTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var folder: URL!
    private var history: History!
    private var transport: BWTestTransport!
    private var store: BWMemoryStore!
    private var model: BitwardenModel!
    override func setUp() async throws {
        suite = "EasyPaste.BitwardenTests." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)!
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        history = History(vault: try ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        transport = BWTestTransport(); store = BWMemoryStore(BWSession(email:"me@example.com", region:.europe, refreshToken:"FAKE",userKey:Data(repeating:7,count:64),accessToken:"",expires:.distantPast))
        model = BitwardenModel(defaults: defaults, client: BWClient(transport: transport), store: store); model.attach(history: history)
        model.copyLink = { _ in true }
    }
    override func tearDown() async throws {
        await model.shutdown(); history.stopMonitoring(); await history.flush(); defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    private func settle() async throws {
        for _ in 0..<600 { if !model.busy { return }; try await Task.sleep(for: .milliseconds(10)) }; XCTFail("Operation did not finish")
    }
    private func unlock() async throws { model.setEnabled(true); model.unlock(); try await settle(); XCTAssertTrue(model.unlocked, model.error ?? ""); XCTAssertNil(model.error) }
    private func clip(_ text: String = "Bonjour") async throws -> Clip { try await history.saveOCR(text) }
    func testDisabledByDefaultDoesNotReadKeychainOrMakeRequests() async throws {
        XCTAssertFalse(model.enabled); XCTAssertFalse(model.publicOnly); model.unlock(); model.showSends(); model.showAccount()
        model.share(try await clip()); try await Task.sleep(for: .milliseconds(30))
        let counts = await store.counts(), requests = await transport.snapshot()
        XCTAssertEqual(counts, [0,0,0]); XCTAssertTrue(requests.isEmpty)
    }
    func testActivationDoesNotConnectUntilRequested() async throws {
        model.setEnabled(true); try await Task.sleep(for: .milliseconds(30))
        let counts = await store.counts(), requests = await transport.snapshot()
        XCTAssertEqual(counts, [0,0,0]); XCTAssertTrue(requests.isEmpty)
        try await unlock(); model.lock(); XCTAssertFalse(model.unlocked); XCTAssertEqual(model.account, "me@example.com")
    }
    func testNativeLoginUsesOnlyPasswordHashAndPersistsSession() async throws {
        model.setEnabled(true); model.login(email:"me@example.com", password:"password-test", code:"",provider:0)
        try await settle(); XCTAssertTrue(model.unlocked, model.error ?? "")
        let requests = await transport.snapshot(); let token = requests.first { $0.url?.path == "/connect/token" }!
        XCTAssertEqual(token.url?.host, "identity.bitwarden.com")
        XCTAssertFalse(String(data: token.httpBody!, encoding:.utf8)!.contains("password-test"))
        let counts = await store.counts(); XCTAssertEqual(counts[1], 1)
    }
    func testNewLoginAlwaysUsesInternationalDespiteAnOldRegionPreference() async throws {
        XCTAssertEqual(model.region, .international)
        defaults.set(BWRegion.europe.rawValue, forKey: "bitwarden.region")
        model.setEnabled(true)
        model.login(email: "me@example.com", password: "password-test", code: "", provider: 0)
        try await settle()
        XCTAssertTrue(model.unlocked, model.error ?? "")
        XCTAssertEqual(model.region, .international)
        let requests = await transport.snapshot()
        XCTAssertTrue(requests.allSatisfy { $0.url?.host?.hasSuffix(".bitwarden.com") == true })
        XCTAssertEqual(defaults.string(forKey: "bitwarden.region"), BWRegion.international.rawValue)
    }
    func testQuickShareCopiesOnceOnlyAfterServerSuccessWithSevenDaysAndDateTitle() async throws {
        try await unlock(); model.publicOnly = true
        var copied: [URL] = []; model.copyLink = { copied.append($0); return true }
        let item = try await clip(); await transport.configure(delaySend:true)
        model.share(item); model.share(item); XCTAssertTrue(copied.isEmpty)
        try await settle(); XCTAssertEqual(copied.count, 1); XCTAssertEqual(copied[0].host, "send.bitwarden.eu")
        let requests = await transport.snapshot(), sends = requests.filter { $0.url?.path == "/sends" && $0.httpMethod == "POST" }
        XCTAssertEqual(sends.count, 1)
        let body = try JSONSerialization.jsonObject(with:sends[0].httpBody!) as! [String:Any]
        XCTAssertEqual(body["authType"] as? Int, 2); XCTAssertNil(body["emails"]); XCTAssertNil(body["password"])
        let secret = try BWCrypto.decrypt(body["key"] as! String, key: Data(repeating:7,count:64))
        let title = String(data:try BWCrypto.decrypt(body["name"] as! String,key:BWCrypto.sendKey(secret)),encoding:.utf8)!
        XCTAssertNotEqual(title, item.title); XCTAssertTrue(title.contains(" à "))
        let deletion = ISO8601DateFormatter().date(from:body["deletionDate"] as! String)!
        XCTAssertEqual(deletion.timeIntervalSinceNow, 7*86400, accuracy: 5)
    }
    func testOptionsOverrideNeverAutoUploadsAndEmailPolicyIsPreserved() async throws {
        try await unlock(); model.publicOnly = true
        model.share(try await clip(), forceOptions:true); try await settle()
        var requests = await transport.snapshot(); XCTAssertFalse(requests.contains { $0.httpMethod == "POST" && $0.url?.path == "/sends" })
        model.options.audience = .emails; model.options.emails = "alice@example.com"; model.options.days = 3; model.create(); try await settle()
        requests = await transport.snapshot(); let send = try XCTUnwrap(requests.last { $0.url?.path == "/sends" && $0.httpMethod == "POST" }, model.error ?? "")
        let body = try JSONSerialization.jsonObject(with:send.httpBody!) as! [String:Any]
        XCTAssertEqual(body["authType"] as? Int, 0); XCTAssertEqual(body["emails"] as? String,"alice@example.com"); XCTAssertTrue(model.publicOnly)
    }
    func testDisableDuringRequestNeverCopiesAndRemovesCredentials() async throws {
        try await unlock(); model.publicOnly = true; var copies = 0; model.copyLink = { _ in copies += 1; return true }
        await transport.configure(delaySend:true); model.share(try await clip())
        try await Task.sleep(for:.milliseconds(60)); model.setEnabled(false); try await Task.sleep(for:.milliseconds(100))
        XCTAssertFalse(model.unlocked); XCTAssertFalse(model.enabled); XCTAssertEqual(copies,0); XCTAssertEqual(model.account,"")
        let counts = await store.counts(); XCTAssertEqual(counts[2],1)
    }
    func testFailedFileUploadDoesNotCopyAndDeletesReservation() async throws {
        try await unlock(); model.publicOnly = true; await transport.configure(uploadFails:true)
        let item = try await clip(String(repeating:"long text ",count:90)); var copies = 0; model.copyLink = { _ in copies += 1;return true }
        model.share(item); try await settle(); XCTAssertEqual(copies,0); XCTAssertNotNil(model.error)
        let requests = await transport.snapshot(); XCTAssertTrue(requests.contains { $0.httpMethod == "DELETE" })
        XCTAssertTrue(requests.contains { $0.httpMethod == "PUT" })
    }
    func testRefreshFailureRequiresLoginWithoutTouchingClipboard() async throws {
        model.setEnabled(true); await transport.configure(failToken:true); model.unlock(); try await settle()
        XCTAssertFalse(model.unlocked); XCTAssertNotNil(model.error)
    }
    func testQuickOptionsCannotRetainEmailOrPassword() {
        let options = BitwardenModel.fastOptions(now:Date(timeIntervalSince1970:1_700_000_000))
        XCTAssertEqual(options.days,7); XCTAssertEqual(options.audience,.link); XCTAssertEqual(options.emails,""); XCTAssertEqual(options.password,"")
    }
    func testSuccessfulFileIsCopiedAfterUploadAndStagingIsRemoved() async throws {
        try await unlock(); model.publicOnly = true
        var copies = 0; model.copyLink = { _ in copies += 1; return true }
        model.share(try await clip(String(repeating: "abc", count: 400))); try await settle()
        XCTAssertNil(model.error); XCTAssertEqual(copies, 1)
        let requests = await transport.snapshot()
        XCTAssertEqual(requests.filter { $0.httpMethod == "PUT" }.count, 1)
        XCTAssertFalse(requests.contains { $0.httpMethod == "DELETE" })
    }
    func testClosingDoesNotLeakStagingOrAutoSend() async throws {
        try await unlock(); model.share(try await clip(String(repeating: "abc", count: 400))); try await settle()
        guard case .file(let url, _) = model.content else { return XCTFail("Missing file") }
        XCTAssertTrue(FileManager.default.fileExists(atPath:url.path)); model.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        let requests = await transport.snapshot(); XCTAssertFalse(requests.contains { $0.url?.path == "/sends/file/v2" })
    }
    func testLockErasesPendingContentAndDoesNotLogOut() async throws {
        try await unlock(); model.share(try await clip(String(repeating: "abc", count: 400))); try await settle()
        guard case .file(let url, _) = model.content else { return XCTFail("Missing file") }
        model.lock(); XCTAssertNil(model.content); XCTAssertFalse(model.unlocked); XCTAssertFalse(model.account.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path)); let counts = await store.counts(); XCTAssertEqual(counts[2],0)
    }
    func testShareWindowNativeLayoutsAndOptions() async throws {
        try await unlock(); model.publicOnly = true; model.share(try await clip(),forceOptions:true); try await settle()
        model.options.audience = .emails; model.options.emails = "alice@example.com"
        let host = NSHostingView(rootView: BitwardenWindowView(model:model))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host; host.frame=NSRect(x:0,y:0,width:540,height:620)
        defer { window.close() }; host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width,540); XCTAssertEqual(host.fittingSize.height,620)
        if let dir = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:dir).appendingPathComponent("Bitwarden-partage.png"))
        }
    }
    func testNativeSettingsAndAccountLayout() throws {
        let host = NSHostingView(rootView: BitwardenWindowView(model:model))
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:540,height:620),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false; window.contentView=host; host.frame=NSRect(x:0,y:0,width:540,height:620)
        defer { window.close() }; host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width,540); XCTAssertLessThanOrEqual(host.fittingSize.height,620)
        if let dir = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            model.setEnabled(true); host.layoutSubtreeIfNeeded(); try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds)); host.cacheDisplay(in:host.bounds,to:bitmap)
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:dir).appendingPathComponent("Bitwarden-connexion.png"))
        }
    }
    func testQuickProgressNativeLayout() async throws {
        try await unlock(); model.publicOnly = true
        await transport.configure(delaySend: true)
        model.share(try await clip())
        let host = NSHostingView(rootView: BitwardenQuickView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; host.frame = NSRect(x: 0, y: 0, width: 380, height: 240)
        defer { window.close() }; host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, 380); XCTAssertEqual(host.fittingSize.height, 240)
        if let dir = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("Bitwarden-rapide.png"))
        }
        model.cancel(); try await settle()
    }
}

final class BitwardenSessionStoreTests: XCTestCase {
    func testAuthenticationFailureStopsBeforeReadingKeychain() async throws {
        let store = BWKeychainSessionStore(service: "app.easypaste.invalid-fixture", authenticate: { throw BWError.locked })
        do { _ = try await store.read(); XCTFail("Unauthorized restoration") }
        catch { XCTAssertEqual(error as? BWError, .locked) }
    }
    func testCancellationDoesNotPresentAuthentication() async throws {
        let store = BWKeychainSessionStore(service: "app.easypaste.invalid-fixture", authenticate: { XCTFail("Authentication after cancellation") })
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await store.read() }
        do { _ = try await task.value; XCTFail("Cancelled restoration") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testInvalidCredentialsAreRejectedBeforeKeychainWrite() async throws {
        let store = BWKeychainSessionStore(service: "app.easypaste.invalid-fixture")
        let invalid = BWSession(email: "fixture@example.invalid", region: .europe, refreshToken: "", userKey: Data(), accessToken: "", expires: .distantPast)
        do { try await store.write(invalid); XCTFail("Invalid credentials stored") }
        catch { XCTAssertEqual(error as? BWError, .invalidCipher) }
    }
}

actor BWScriptedTransport: BWTransport {
    var replies: [BWHTTPResponse]; var requests: [URLRequest] = []
    init(_ replies: [BWHTTPResponse]) { self.replies = replies }
    func execute(_ request: URLRequest, file: URL?, progress: @escaping @Sendable (Double) -> Void) async throws -> BWHTTPResponse {
        requests.append(request); guard !replies.isEmpty else { throw BWError.network }; return replies.removeFirst()
    }
    func snapshot() -> [URLRequest] { requests }
}
final class BitwardenAuthenticationTests: XCTestCase {
    private func response(_ value: [String:Any], status:Int = 200) -> BWHTTPResponse { BWHTTPResponse(status:status,data:try! JSONSerialization.data(withJSONObject:value)) }
    private var prelogin: BWHTTPResponse { response(["kdf":0,"kdfIterations":100000]) }
    func testRequiredClientHeadersOnBothRegionsAndRefresh() async throws {
        for region in BWRegion.allCases {
            let transport = BWScriptedTransport([prelogin, response(["error": "version_header_missing"], status: 400),
                                                response(["access_token": "TEST-ACCESS", "expires_in": 3600])])
            let client = BWClient(transport: transport)
            do {
                _ = try await client.login(email: "me@example.com", password: "password-test", region: region, device: "test")
                XCTFail("Server refusal should fail")
            } catch { XCTAssertEqual(error as? BWError, .clientUpdateRequired) }
            let session = BWSession(email: "me@example.com", region: region, refreshToken: "TEST-REFRESH",
                                    userKey: Data(repeating: 7, count: 64), accessToken: "", expires: .distantPast)
            _ = try await client.refresh(session)
            let requests = await transport.snapshot()
            XCTAssertEqual(requests.count, 3)
            for request in requests {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Bitwarden-Client-Name"), "desktop")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Bitwarden-Client-Version"), "0.2.11")
                XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "EasyPaste/0.2.11")
                XCTAssertEqual(request.url?.host, region.identity.host)
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            }
        }
    }
    func testLoginRefusalsDistinguishClientErrorsFromWrongCredentials() async throws {
        let cases: [([String: Any], BWError)] = [
            (["error": "version_header_missing"], .clientUpdateRequired),
            (["error": "invalid_client_version"], .unsupportedEncryption),
            (["error": "invalid_client"], .clientUpdateRequired),
            (["error": "invalid_scope"], .clientUpdateRequired),
            (["error": "invalid_grant", "error_description": "invalid_username_or_password"], .invalidCredentials),
            (["ErrorModel": ["Message": "Username or password is incorrect. Try again."]], .invalidCredentials),
            (["error": "invalid_grant"], .loginRejected(400)),
            (["error": "unknown", "error_description": "SECRET-TOKEN", "ErrorModel": ["Message": "SECRET-TOKEN"]], .loginRejected(400))
        ]
        for (body, expected) in cases {
            let transport = BWScriptedTransport([prelogin, response(body, status: 400)])
            do {
                _ = try await BWClient(transport: transport).login(email: "me@example.com", password: "password-test", region: .europe, device: "test")
                XCTFail("Refused login must fail")
            } catch {
                XCTAssertEqual(error as? BWError, expected)
                XCTAssertFalse(error.localizedDescription.contains("SECRET-TOKEN"))
            }
            let requests = await transport.snapshot()
            XCTAssertEqual(requests.count, 2, "No automatic retry or alternate-region credential forwarding")
        }
    }
    func testRateLimitAndNonJSONLoginRefusalsRemainActionable() async throws {
        for (status, expected) in [(429, BWError.tooManyAttempts), (403, .loginRejected(403)), (503, .loginRejected(503))] {
            let transport = BWScriptedTransport([prelogin, BWHTTPResponse(status: status, data: Data("<html>SECRET-TOKEN</html>".utf8))])
            do {
                _ = try await BWClient(transport: transport).login(email: "me@example.com", password: "password-test", region: .europe, device: "test")
                XCTFail("Refused login must fail")
            } catch {
                XCTAssertEqual(error as? BWError, expected)
                XCTAssertFalse(error.localizedDescription.contains("SECRET-TOKEN"))
            }
        }
    }
    func testRejectedOTPIsNotReportedAsBadMasterPassword() {
        let value: [String: Any] = ["error": "invalid_grant", "ErrorModel": ["Message": "Two-step token is invalid. Try again."]]
        XCTAssertEqual(BWClient.loginFailure(value, status: 400, hasCode: true), .invalidVerificationCode)
        XCTAssertEqual(BWClient.loginFailure(value, status: 400, hasCode: false), .loginRejected(400))
    }
    func testTwoFactorAndNewDeviceChallenges() async throws {
        for (reply, expected) in [
            (response(["twoFactorProviders2":["0":[:],"1":[:]]], status:400), BWError.twoFactor([0,1])),
            (response(["TwoFactorProviders2":["7":[:]]], status:400), BWError.unsupportedAuthentication),
            (response(["DeviceVerified":false], status:400), BWError.newDevice),
            (response(["ErrorModel":["Message":"new device verification required"]], status:400), BWError.newDevice),
            (response(["HCaptcha_SiteKey":"test"], status:400), BWError.captcha)
        ] {
            let transport = BWScriptedTransport([prelogin, reply])
            do { _ = try await BWClient(transport:transport).login(email:"me@example.com",password:"password-test",region:.europe,device:"test"); XCTFail("Expected challenge") }
            catch { XCTAssertEqual(error as? BWError, expected) }
        }
    }
    func testDeviceCodeIsNotConfusedWithAuthenticatorCode() async throws {
        let transport = BWScriptedTransport([prelogin,response(["error":"invalid_grant"],status:400)])
        _ = try? await BWClient(transport:transport).login(email:"me@example.com",password:"password-test",region:.europe,device:"test",code:"123456",provider:0,newDevice:true)
        let requests = await transport.snapshot(), body = String(data:requests[1].httpBody!,encoding:.utf8)!
        XCTAssertTrue(body.contains("newDeviceOtp=123456")); XCTAssertFalse(body.contains("twoFactorToken"))
    }
    func testPreloginCompatibilityFallbackAndKeyScope() async throws {
        let transport = BWScriptedTransport([response([:],status:404),prelogin,response(["error":"invalid_grant"],status:400)])
        _ = try? await BWClient(transport:transport).login(email:"me@example.com",password:"password-test",region:.international,device:"test")
        let requests = await transport.snapshot()
        XCTAssertEqual(requests.map { $0.url!.path },["/accounts/prelogin/password","/accounts/prelogin","/connect/token"])
        XCTAssertTrue(requests.allSatisfy { $0.url!.host == "identity.bitwarden.com" })
    }
    func testMalformedLoginResponseCannotCreateSession() async throws {
        for value in [["access_token":"fake"], ["access_token":"fake","refresh_token":"fake","Key":"2.bad|bad|bad"]] {
            let transport = BWScriptedTransport([prelogin,response(value)])
            do { _ = try await BWClient(transport:transport).login(email:"me@example.com",password:"password-test",region:.europe,device:"test"); XCTFail("Invalid session accepted") } catch { XCTAssertNotNil(error as? BWError) }
        }
    }
    func testServerRefusalDoesNotExposeServerMessage() throws {
        let client = BWClient()
        XCTAssertThrowsError(try client.check(response(["message":"TOP-SECRET"],status:500))) { error in XCTAssertFalse(error.localizedDescription.contains("TOP-SECRET")) }
        XCTAssertThrowsError(try client.check(response(["message":"Premium membership required"],status:400))) { error in XCTAssertEqual(error as? BWError,.premium) }
    }
    func testEmailCodeRequestUsesHashOnly() async throws {
        let transport = BWScriptedTransport([prelogin,response([:])])
        try await BWClient(transport:transport).sendLoginEmail(email:"me@example.com",password:"password-test",region:.europe,device:"test")
        let requests = await transport.snapshot(); XCTAssertEqual(requests.last?.url?.path,"/two-factor/send-email-login")
        let body = try JSONSerialization.jsonObject(with:requests.last!.httpBody!) as! [String:Any]
        XCTAssertNotNil(body["masterPasswordHash"]); XCTAssertFalse(String(data:requests.last!.httpBody!,encoding:.utf8)!.contains("password-test"))
    }
}

private final class BWMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let mutex = NSLock()
    static var bodySize = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.mutex.lock(); let size = Self.bodySize; Self.mutex.unlock()
        let response = HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Length":String(size)])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(repeating:0x20,count:min(size,1024)))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class BitwardenTransportTests: XCTestCase {
    func testNativeTransportBoundsResponsesAndSupportsCancellation() async throws {
        let transport = BWURLTransport(configuration: { let c=URLSessionConfiguration.ephemeral; c.protocolClasses=[BWMockURLProtocol.self]; return c })
        let request = URLRequest(url:URL(string:"https://api.bitwarden.eu/test-fixture")!)
        BWMockURLProtocol.mutex.withLock { BWMockURLProtocol.bodySize=5 }
        let response = try await transport.execute(request); XCTAssertEqual(response.status,200); XCTAssertEqual(response.data.count,5)
        BWMockURLProtocol.mutex.withLock { BWMockURLProtocol.bodySize=3*1024*1024 }
        do { _ = try await transport.execute(request); XCTFail("Oversize response accepted") } catch { XCTAssertEqual(error as? BWError,.invalidResponse) }
        let task = Task { try await transport.execute(request) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request completed") } catch { XCTAssertTrue(error is CancellationError) }
    }
}
