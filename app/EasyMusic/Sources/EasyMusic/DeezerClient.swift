import Foundation

/// Public metadata requests share a small cache and a cadence below the service's quota.
actor DeezerClient {
    static let shared = DeezerClient()
    private var nextRequest = Date.distantPast
    private var cache: [URL: (Date, Data)] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]

    func request(_ url: URL, session: URLSession = .shared) async throws -> Data {
        if let cached = cache[url], Date().timeIntervalSince(cached.0) < 120 { return cached.1 }
        if let existing = inFlight[url] { return try await existing.value }
        let task = Task { try await self.fetch(url, session: session) }
        inFlight[url] = task
        do {
            let data = try await task.value
            inFlight[url] = nil
            if !Self.hasServiceError(data) {
                cache[url] = (Date(), data)
                if cache.count > 500 { cache = cache.filter { Date().timeIntervalSince($0.value.0) < 120 } }
            }
            return data
        } catch { inFlight[url] = nil; throw error }
    }
    private func fetch(_ url: URL, session: URLSession) async throws -> Data {
        for attempt in 0..<3 {
            let scheduled = max(Date(), nextRequest)
            nextRequest = scheduled.addingTimeInterval(0.18)
            let delay = scheduled.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            try Task.checkCancellation()
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            // Error JSON must not be served from Foundation's HTTP cache on subsequent attempts.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw MusicError.message("Le catalogue est temporairement indisponible.") }
            if http.statusCode == 429 || Self.isQuotaError(data) {
                if attempt < 2 { try await Task.sleep(nanoseconds: UInt64(2 + attempt * 2) * 1_000_000_000); continue }
                throw MusicError.message("Le catalogue reçoit trop de demandes. Réessayez dans quelques secondes.")
            }
            guard (200..<300).contains(http.statusCode) else { throw MusicError.message("Le catalogue est temporairement indisponible.") }
            return data
        }
        throw MusicError.message("Le catalogue est temporairement indisponible.")
    }
    static func hasServiceError(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] != nil
    }
    static func isQuotaError(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return false }
        let message = (error["message"] as? String ?? "").lowercased()
        return error["code"] as? Int == 4 || message.contains("quota") || message.contains("too many")
    }
}
