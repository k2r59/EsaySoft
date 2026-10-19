import Foundation

struct BWHTTPResponse { let status: Int; let data: Data }
protocol BWTransport: Sendable {
    func execute(_ request: URLRequest, file: URL?, progress: @escaping @Sendable (Double) -> Void) async throws -> BWHTTPResponse
}
struct BWURLTransport: BWTransport {
    let configuration: @Sendable () -> URLSessionConfiguration
    init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) { self.configuration = configuration }
    func execute(_ request: URLRequest, file: URL? = nil, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> BWHTTPResponse {
        let operation = BWNetworkOperation(progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { operation.start(request, file: file, configuration: configuration(), continuation: $0) }
        } onCancel: { operation.cancel() }
    }
}
private final class BWNetworkOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let mutex = NSLock()
    private var cancelled = false
    private var task: URLSessionTask?
    private var continuation: CheckedContinuation<BWHTTPResponse, Error>?
    private var received = Data()
    private var failure: Error?
    private var lastProgress = -1
    private let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }
    func start(_ request: URLRequest, file: URL?, configuration config: URLSessionConfiguration, continuation: CheckedContinuation<BWHTTPResponse, Error>) {
        mutex.lock()
        guard !cancelled else { mutex.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false; config.urlCache = nil; config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 600
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        let task: URLSessionTask = file.map { session.uploadTask(with: request, fromFile: $0) } ?? session.dataTask(with: request)
        self.task = task; mutex.unlock(); task.resume()
    }
    func cancel() { mutex.lock(); cancelled = true; let current = task; mutex.unlock(); current?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward tokens, passwords or ciphertext to a redirect target.
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if response.expectedContentLength > 2 * 1024 * 1024 { failure = BWError.invalidResponse; completionHandler(.cancel) }
        else { completionHandler(.allow) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard received.count + data.count <= 2 * 1024 * 1024 else { failure = BWError.invalidResponse; dataTask.cancel(); return }
        received.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let value = min(100, Int(Double(totalBytesSent) / Double(totalBytesExpectedToSend) * 100))
        if value != lastProgress { lastProgress = value; progress(Double(value) / 100) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        mutex.lock(); let continuation = continuation; self.continuation = nil; self.task = nil; let wasCancelled = cancelled; mutex.unlock()
        defer { session.finishTasksAndInvalidate() }
        if let failure { continuation?.resume(throwing: failure) }
        else if wasCancelled || (error as? URLError)?.code == .cancelled { continuation?.resume(throwing: CancellationError()) }
        else if error != nil { continuation?.resume(throwing: BWError.network) }
        else if let response = task.response as? HTTPURLResponse { continuation?.resume(returning: BWHTTPResponse(status: response.statusCode, data: received)) }
        else { continuation?.resume(throwing: BWError.invalidResponse) }
    }
}

struct BWClient: Sendable {
    let transport: any BWTransport
    init(transport: any BWTransport = BWURLTransport()) { self.transport = transport }
    static func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(values.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    }
    private func request(_ url: URL, method: String = "POST", body: Data? = nil, token: String? = nil, form: Bool = false) -> URLRequest {
        var r = URLRequest(url: url); r.httpMethod = method; r.httpBody = body
        r.setValue(form ? "application/x-www-form-urlencoded" : "application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("EasyPaste/0.2.9", forHTTPHeaderField: "User-Agent")
        r.setValue("7", forHTTPHeaderField: "Device-Type")
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }
    func json(_ response: BWHTTPResponse) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw BWError.invalidResponse }
        return value
    }
    func check(_ response: BWHTTPResponse) throws {
        guard (200...299).contains(response.status) else {
            if response.status == 401 { throw BWError.expiredSession }
            // Error text is inspected for classification, never displayed or logged (may contain secrets).
            let text = String(data: response.data.prefix(8000), encoding: .utf8)?.lowercased() ?? ""
            if text.contains("premium") || text.contains("paid membership") { throw BWError.premium }
            throw BWError.server(response.status)
        }
    }
    func login(email: String, password: String, region: BWRegion, device: String, code: String = "", provider: Int = 0, newDevice: Bool = false) async throws -> BWSession {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !password.isEmpty else { throw BWError.invalidCredentials }
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        var prelogin = try await transport.execute(request(region.identity.appendingPathComponent("accounts/prelogin/password"), body: body), file: nil, progress: { _ in })
        if prelogin.status == 404 { prelogin = try await transport.execute(request(region.identity.appendingPathComponent("accounts/prelogin"), body: body), file: nil, progress: { _ in }) }
        try check(prelogin)
        let kdf = try BWKDF(json: json(prelogin))
        let worker = Task.detached(priority: .userInitiated) { try await BWDerivation.shared.masterKey(password: password, email: email, kdf: kdf) }
        let master = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        var form = ["grant_type": "password", "username": email, "password": try BWCrypto.passwordHash(master: master, password: password),
                    "scope": "api offline_access", "client_id": "desktop", "deviceType": "7", "deviceIdentifier": device, "deviceName": "EasyPaste"]
        if !code.isEmpty {
            guard [0, 1].contains(provider), code.utf8.count <= 100 else { throw BWError.unsupportedAuthentication }
            if newDevice { form["newDeviceOtp"] = code.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { form["twoFactorToken"] = code.trimmingCharacters(in: .whitespacesAndNewlines); form["twoFactorProvider"] = String(provider); form["twoFactorRemember"] = "0" }
        }
        let response = try await transport.execute(request(region.identity.appendingPathComponent("connect/token"), body: Self.form(form), form: true), file: nil, progress: { _ in })
        let value = try json(response)
        let errorModel = value.bwValue("errorModel") as? [String: Any]
        if errorModel?.bwString("message")?.lowercased() == "new device verification required" { throw BWError.newDevice }
        if let verified = value.bwValue("deviceVerified") as? Bool, !verified { throw BWError.newDevice }
        if value.bwValue("ssoOrganizationIdentifier") != nil { throw BWError.unsupportedAuthentication }
        if let providers = value.bwValue("twoFactorProviders2") as? [String: Any], !providers.isEmpty {
            let supported = providers.keys.compactMap(Int.init).filter { [0, 1].contains($0) }.sorted()
            guard !supported.isEmpty else { throw BWError.unsupportedAuthentication }; throw BWError.twoFactor(supported)
        }
        if value.bwValue("HCaptcha_SiteKey") != nil || value.bwValue("hCaptchaSiteKey") != nil { throw BWError.captcha }
        guard (200...299).contains(response.status) else {
            if response.status == 400 || response.status == 401 { throw BWError.invalidCredentials }; try check(response); throw BWError.invalidResponse
        }
        let unlock = (value.bwValue("userDecryptionOptions") as? [String: Any])?.bwValue("masterPasswordUnlock") as? [String: Any]
        guard let encrypted = value.bwString("key") ?? unlock?.bwString("masterKeyWrappedUserKey"), let access = value.bwString("access_token"), !access.isEmpty,
              let refresh = value.bwString("refresh_token"), !refresh.isEmpty else { throw BWError.invalidResponse }
        let userKey = try BWCrypto.decrypt(encrypted, key: BWCrypto.stretched(master))
        guard userKey.count == 64 else { throw BWError.invalidCipher }
        return BWSession(email: email, region: region, refreshToken: refresh, userKey: userKey, accessToken: access, expires: Date().addingTimeInterval(Double(min(86400, max(60, value.bwInt("expires_in") ?? 3600)))))
    }
    func sendLoginEmail(email: String, password: String, region: BWRegion, device: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let prelogin = try await transport.execute(request(region.identity.appendingPathComponent("accounts/prelogin/password"), body: try JSONSerialization.data(withJSONObject: ["email": email])), file: nil, progress: { _ in })
        try check(prelogin); let kdf = try BWKDF(json: json(prelogin))
        let worker = Task.detached(priority: .userInitiated) { try await BWDerivation.shared.masterKey(password: password, email: email, kdf: kdf) }
        let master = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        let body: [String: Any] = ["email": email, "masterPasswordHash": try BWCrypto.passwordHash(master: master, password: password), "deviceIdentifier": device]
        let response = try await transport.execute(request(region.api.appendingPathComponent("two-factor/send-email-login"), body: try JSONSerialization.data(withJSONObject: body)), file: nil, progress: { _ in })
        try check(response)
    }
    func refresh(_ session: BWSession) async throws -> BWSession {
        let response = try await transport.execute(request(session.region.identity.appendingPathComponent("connect/token"), body: Self.form(["grant_type": "refresh_token", "refresh_token": session.refreshToken, "client_id": "desktop"]), form: true), file: nil, progress: { _ in })
        if [400, 401].contains(response.status) { throw BWError.expiredSession }
        try check(response); let json = try json(response)
        guard let access = json.bwString("access_token"), !access.isEmpty else { throw BWError.invalidResponse }
        var value = session; value.accessToken = access; value.refreshToken = json.bwString("refresh_token") ?? session.refreshToken
        value.expires = Date().addingTimeInterval(Double(min(86400, max(60, json.bwInt("expires_in") ?? 3600)))); return value
    }
    func send(_ prepared: BWPreparedSend, session: BWSession, progress: @escaping @Sendable (Double) -> Void) async throws -> BWSend {
        let path = prepared.encryptedFile == nil ? "sends" : "sends/file/v2"
        let response: BWHTTPResponse
        do { response = try await transport.execute(request(session.region.api.appendingPathComponent(path), body: prepared.body, token: session.accessToken), file: nil, progress: { _ in }) }
        catch { throw BWError.unknownCreation } // No automatic POST retry: the server may have created it.
        try check(response); let value = try json(response)
        let record = prepared.encryptedFile == nil ? value : (value.bwValue("sendResponse") as? [String: Any] ?? [:])
        guard let returnedKey = record.bwString("key"), try BWCrypto.decrypt(returnedKey, key: session.userKey) == prepared.secret else { throw BWError.invalidResponse }
        let send = try decodeSend(record, session: session)
        if let file = prepared.encryptedFile {
            do {
                try Task.checkCancellation()
                guard value.bwInt("fileUploadType") == 1, let raw = value.bwString("url"), let url = URL(string: raw), Self.safeUploadURL(url) else { throw BWError.invalidResponse }
                var request = URLRequest(url: url); request.httpMethod = "PUT"
                request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type"); request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
                if let version = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "sv" })?.value { request.setValue(version, forHTTPHeaderField: "x-ms-version") }
                // Deliberately no Bitwarden bearer token on the storage host.
                let upload = try await transport.execute(request, file: file, progress: progress); try check(upload)
            } catch {
                let originalError = error
                // Cancellation must still remove the server reservation. Bounded independent cleanup.
                let cleanup = Task.detached { try await self.delete(id: send.id, session: session) }
                do { try await cleanup.value } catch { throw BWError.partialUpload(send.id) }
                throw originalError
            }
        }
        return send
    }
    static func safeUploadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased(), host.hasSuffix(".blob.core.windows.net"), url.fragment == nil else { return false }
        return !host.dropLast(".blob.core.windows.net".count).isEmpty
    }
    func list(session: BWSession) async throws -> [BWSend] {
        let response = try await transport.execute(request(session.region.api.appendingPathComponent("sends"), method: "GET", token: session.accessToken), file: nil, progress: { _ in })
        try check(response); let value = try json(response)
        guard let records = value.bwValue("data") as? [[String: Any]], records.count <= 2000 else { throw BWError.invalidResponse }
        return try records.map { try decodeSend($0, session: session) }.sorted { ($0.deletion ?? .distantFuture) > ($1.deletion ?? .distantFuture) }
    }
    func delete(id: String, session: BWSession) async throws {
        guard UUID(uuidString: id) != nil else { throw BWError.invalidResponse }
        let response = try await transport.execute(request(session.region.api.appendingPathComponent("sends/\(id)"), method: "DELETE", token: session.accessToken), file: nil, progress: { _ in })
        if response.status != 404 { try check(response) }
    }
    func decodeSend(_ value: [String: Any], session: BWSession) throws -> BWSend {
        guard let id = value.bwString("id"), UUID(uuidString: id) != nil, let access = value.bwString("accessId"),
              let encryptedKey = value.bwString("key"), let encryptedName = value.bwString("name") else { throw BWError.invalidResponse }
        let secret = try BWCrypto.decrypt(encryptedKey, key: session.userKey)
        let nameBytes = try BWCrypto.decrypt(encryptedName, key: BWCrypto.sendKey(secret))
        guard let name = String(data: nameBytes, encoding: .utf8) else { throw BWError.invalidResponse }
        let date = value.bwString("deletionDate").flatMap { s -> Date? in
            let f = ISO8601DateFormatter(); f.formatOptions.insert(.withFractionalSeconds)
            return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
        }
        return BWSend(id: id, name: name, link: try session.region.link(accessID: access, secret: secret), deletion: date, isFile: value.bwInt("type") == 1, accessCount: value.bwInt("accessCount") ?? 0)
    }
}
