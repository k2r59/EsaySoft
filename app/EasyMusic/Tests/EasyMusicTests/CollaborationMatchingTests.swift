import XCTest
@testable import EasyMusic

final class CollaborationMatchingTests: XCTestCase {
    private func song(_ title: String, artist: String, credits: [String]? = nil, duration: Double = 224, catalog: Bool = false) -> Track {
        Track(id: catalog ? "spotify:fixture" : "YouTube:fixture", title: title, artist: artist, duration: duration,
              url: catalog ? "https://open.spotify.com/track/fixture" : "https://www.youtube.com/watch?v=fixture",
              source: catalog ? "Spotify" : "YouTube", isCatalog: catalog, creditedArtist: catalog ? nil : artist, artistCredits: credits)
    }
    func testSpotifySeparatorsPreserveBandNamesAndCommasInsideArtistNames() {
        let target = song("Song", artist: "Tyler, The Creator,\u{00a0}White & Spirit", catalog: true)
        XCTAssertEqual(Matching.requestedArtists(target), ["Tyler, The Creator", "White & Spirit"])
        let candidate = song("Song", artist: "Tyler, The Creator, White & Spirit", credits: ["Tyler, The Creator", "White & Spirit"])
        XCTAssertGreaterThanOrEqual(Matching.score(candidate, for: target), 0.85)
        XCTAssertEqual(Matching.score(song("Song", artist: "Tyler"), for: target), 0)
    }
    func testFullOfficialCreditsMatchSpotifyCollaborations() {
        let target = song("Medley Thugs / Interlude (feat. Kool Shen & Nysay)", artist: "Les Sages Poètes de la rue,\u{00a0}Kool Shen,\u{00a0}Nysay", duration: 336.066, catalog: true)
        let candidate = song("Medley Thugs / Interlude", artist: "Les Sages Poètes De La Rue, Kool Shen, Nysay",
                             credits: ["Les Sages Poètes De La Rue", "Kool Shen", "Nysay"], duration: 336)
        XCTAssertGreaterThanOrEqual(Matching.score(candidate, for: target), 0.85)
    }
    func testSecondaryCatalogueSpellingsDoNotChangePrimaryIdentity() {
        let target = song("Beat de Boul est dans la sono", artist: "Mala,\u{00a0}Les Sages Poètes de la rue,\u{00a0}Sir Doum's", catalog: true)
        let candidate = song(target.title, artist: "Mala, Sages Poètes De La Rue, Sir Doums", credits: ["Mala", "Sages Poètes De La Rue", "Sir Doums"])
        XCTAssertGreaterThanOrEqual(Matching.score(candidate, for: target), 0.85)
        var wrong = candidate; wrong.artistCredits = ["Mala", "Different guest"]
        XCTAssertEqual(Matching.score(wrong, for: target), 0)
    }
    func testExplicitGuestAndPrimaryArtistContradictionsAreRejected() {
        let target = song("Song (feat. Guest)", artist: "Lead,\u{00a0}Guest", catalog: true)
        XCTAssertEqual(Matching.score(song("Song", artist: "Guest, Lead", credits: ["Guest", "Lead"]), for: target), 0)
        XCTAssertEqual(Matching.score(song("Song", artist: "Lead, Another", credits: ["Lead", "Another"]), for: target), 0)
        XCTAssertEqual(Matching.score(song("Song (feat. Another)", artist: "Lead"), for: target), 0)
    }
    func testGuestRemovalDoesNotRemoveVersionsOrRealTitleWords() {
        XCTAssertEqual(Matching.musicalTitle("A song (feat. Guest) - Medley"), "A song - Medley")
        XCTAssertEqual(Matching.musicalTitle("A song [ft. Guest] (Live)"), "A song (Live)")
        XCTAssertEqual(Matching.musicalTitle("Feat of Strength"), "Feat of Strength")
        let target = song("Song (feat. Guest) - Medley", artist: "Lead,\u{00a0}Guest", catalog: true)
        XCTAssertLessThan(Matching.score(song("Song (Audio)", artist: "Lead"), for: target), 0.85)
    }
    func testHomonymAndLocalDeduplicationStayStrict() {
        let target = song("Song", artist: "Renaud,\u{00a0}Guest", catalog: true)
        XCTAssertEqual(Matching.score(song("Song", artist: "Renaud Capuçon"), for: target), 0)
        let anotherGuest = song("Song", artist: "Renaud,\u{00a0}Another", catalog: true)
        XCTAssertFalse(Matching.sameRecording(target, anotherGuest))
    }
    func testStructuredCandidateNamesResolveGuestsMentionedOnlyInTitle() {
        let target = song("Song (feat. Nora & Léa)", artist: "Axel", catalog: true)
        let correct = song("Song", artist: "Axel, Nora, Léa", credits: ["Axel", "Nora", "Léa"])
        XCTAssertGreaterThanOrEqual(Matching.score(correct, for: target), 0.85)
        let band = song("Song (feat. White & Spirit)", artist: "Axel", catalog: true)
        XCTAssertGreaterThanOrEqual(Matching.score(song("Song", artist: "Axel, White & Spirit", credits: ["Axel", "White & Spirit"]), for: band), 0.85)
    }
    func testKnownMatchTransfersWithoutExtraInspection() async throws {
        let target = song("Song", artist: "Axel,\u{00a0}Nora", catalog: true)
        let candidate = song("Song", artist: "Axel", credits: ["Axel", "Nora"])
        _ = try await AudioDownload.run(target: target, preferred: nil, search: { _, _ in [candidate] },
            transfer: { _, _ in "/audio.m4a" }, inspect: { _ in XCTFail("Aucune inspection supplémentaire pour une correspondance déjà fiable"); return nil })
    }
    func testOnlyPlausibleFullLengthCandidatesAreInspected() {
        let target = song("Original Song", artist: "Lead,\u{00a0}Guest", catalog: true)
        XCTAssertTrue(AudioDownload.canInspect(song(target.title, artist: "Topic"), for: target))
        XCTAssertFalse(AudioDownload.canInspect(song(target.title, artist: "Topic", duration: 30), for: target))
        XCTAssertFalse(AudioDownload.canInspect(song("Something Else", artist: "Topic"), for: target))
    }
    func testMetadataEnrichmentPreservesThresholdAndStopsOnCancellation() async throws {
        let target = song("Original Song", artist: "Lead,\u{00a0}Guest", catalog: true)
        let snippet = song(target.title, artist: "Publishing channel")
        var inspections = 0, transfers = 0
        let result = try await AudioDownload.run(target: target, preferred: nil,
            search: { _, _ in [snippet] }, transfer: { track, _ in transfers += 1; return "/audio.m4a" },
            inspect: { _ in inspections += 1; return self.song(target.title, artist: "Lead, Guest", credits: ["Lead", "Guest"]) })
        XCTAssertEqual(inspections, 1); XCTAssertEqual(transfers, 1)
        XCTAssertGreaterThanOrEqual(Matching.score(result.0, for: target), 0.85)
        do {
            _ = try await AudioDownload.run(target: target, preferred: nil,
                search: { _, _ in [snippet] }, transfer: { _, _ in XCTFail("Annulé"); return "" },
                inspect: { _ in throw CancellationError() })
            XCTFail("Annulation attendue")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
