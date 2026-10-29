import XCTest
@testable import EasyMusic

final class RecommendationTests: XCTestCase {
    func testColdStartStaysGeneralAndHasNoPersonalSuggestions() throws {
        let old = try JSONDecoder().decode(Library.self, from: Data("{\"tracks\":[],\"playlists\":[]}".utf8))
        XCTAssertNil(old.interests)
        XCTAssertTrue(Recommendations.queries(old.interests ?? []).isEmpty)
        XCTAssertEqual(Recommendations.generalQueries.count, 8)
        XCTAssertTrue(Recommendations.generalQueries.contains("rock"))
        XCTAssertTrue(Recommendations.generalQueries.contains("jazz"))
    }
    func testListensOutweighSearchesAndRecentInterestReplacesOldTaste() {
        let now = Date()
        var interests = Recommendations.record("Rock", weight: 1, in: [], now: now)
        interests = Recommendations.record("Jazz", weight: 3, in: interests, now: now)
        XCTAssertEqual(Recommendations.queries(interests, now: now).first, "Jazz")
        interests = Recommendations.record("Soul", weight: 1, in: interests, now: now.addingTimeInterval(120 * 86400))
        XCTAssertEqual(Recommendations.queries(interests, now: now.addingTimeInterval(120 * 86400)), ["Soul"])
    }
    func testDuplicateSearchesLinksAndUnboundedHistoryAreAvoided() {
        let now = Date()
        var interests = Recommendations.record("Électro", weight: 1, in: [], now: now)
        interests = Recommendations.record(" electro ", weight: 1, in: interests, now: now)
        XCTAssertEqual(interests.count, 1)
        XCTAssertEqual(interests[0].weight, 1)
        interests = Recommendations.record("https://example.com/private-link", weight: 3, in: interests, now: now)
        XCTAssertEqual(interests.count, 1)
        for index in 0..<100 { interests = Recommendations.record("Artist \(index)", weight: 3, in: interests, now: now) }
        XCTAssertEqual(interests.count, 64)
    }
    @MainActor func testListeningThresholdPersistenceAndReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("library.json")
        let store = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        store.previewing = Track(id: "test", title: "Song", artist: "Artist", url: "https://example.com", source: "Test")
        store.accountForListening(seconds: 9)
        XCTAssertNil(store.library.interests)
        store.accountForListening(seconds: 1)
        XCTAssertEqual(store.library.interests?.first?.weight, 3)
        store.accountForListening(seconds: 20)
        XCTAssertEqual(store.library.interests?.first?.weight, 3)
        let restored = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        XCTAssertEqual(restored.library.interests?.first?.term, "Artist")
        // Avoid any catalogue request in this isolated test.
        restored.homeLoading = true
        restored.resetRecommendations()
        XCTAssertNil(restored.library.interests)
        XCTAssertTrue(restored.personalMixes.isEmpty)
        let clean = MusicStore(storageURL: storage, downloadFolder: root, observePlayback: false)
        XCTAssertNil(clean.library.interests)
    }
}
