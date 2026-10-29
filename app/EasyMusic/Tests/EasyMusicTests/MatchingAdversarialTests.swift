import XCTest
@testable import EasyMusic

final class MatchingAdversarialTests: XCTestCase {
    private func target(_ title: String, artist: String) -> Track {
        Track(id: "requested", title: title, artist: artist, duration: 210,
              url: "https://open.spotify.com/track/requested", source: "Spotify", isCatalog: true)
    }

    private func candidate(_ title: String, artist: String, credit: String? = nil) -> Track {
        Track(id: "candidate", title: title, artist: artist, duration: 210,
              url: "https://www.youtube.com/watch?v=fixture", source: "YouTube", creditedArtist: credit)
    }

    func testPrincipalAndFeaturedArtistCannotBeSwapped() {
        let requested = target("Notre monde (feat. Nora)", artist: "Axel,\u{00A0}Nora")
        let swapped = candidate("Notre monde (feat. Axel)", artist: "Nora - Topic", credit: "Nora feat. Axel")
        XCTAssertLessThan(Matching.score(swapped, for: requested), 0.85)
    }

    func testContradictoryFeaturedArtistInCreditsIsRejected() {
        let requested = target("Notre monde (feat. Nora)", artist: "Axel,\u{00A0}Nora")
        let wrong = candidate("Notre monde (feat. Léa)", artist: "Axel - Topic", credit: "Axel feat. Léa")
        XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85)
    }

    func testContradictoryFeaturedArtistInTitleWithoutMetadataIsRejected() {
        let requested = target("Notre monde (feat. Nora)", artist: "Axel,\u{00A0}Nora")
        for title in ["Notre monde (feat. Léa)", "Notre monde [ft. Léa]", "Notre monde featuring Léa"] {
            let wrong = candidate(title, artist: "Axel")
            XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85, title)
        }
    }

    func testSecondaryArtistAloneIsNotEvidenceForTheRequestedPrincipal() {
        let requested = target("Notre monde", artist: "Axel,\u{00A0}Nora")
        let wrong = candidate("Notre monde", artist: "Nora - Topic", credit: "Nora")
        XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85)
    }

    func testRequestedTitleGuestCannotContradictStructuredCandidateCredits() {
        let requested = target("Notre monde (feat. Nora)", artist: "Axel")
        var wrong = candidate("Notre monde", artist: "Axel", credit: "Axel")
        wrong.artistCredits = ["Axel", "Léa"]
        XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85)
    }

    func testCandidateTitleGuestCannotContradictRequestedArtistList() {
        let requested = target("Notre monde", artist: "Axel,\u{00A0}Nora")
        let wrong = candidate("Notre monde (feat. Léa)", artist: "Axel")
        XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85)
    }

    func testSameFeaturedGuestsInDifferentOrderRemainAValidRecording() {
        let requested = target("Notre monde (feat. Nora & Léa)", artist: "Axel,\u{00A0}Nora,\u{00A0}Léa")
        var same = candidate("Notre monde (feat. Léa & Nora)", artist: "Axel", credit: "Axel")
        same.artistCredits = ["Axel", "Léa", "Nora"]
        XCTAssertGreaterThanOrEqual(Matching.score(same, for: requested), 0.85)
    }

    func testAmpersandArtistNameStaysWholeWhenGuestIsSeparate() {
        let requested = target("Notre monde (feat. IAM)", artist: "White & Spirit,\u{00A0}IAM")
        let correct = candidate("Notre monde (feat. IAM)", artist: "White & Spirit - Topic", credit: "White & Spirit feat. IAM")
        XCTAssertGreaterThanOrEqual(Matching.score(correct, for: requested), 0.85)
        let unrelated = candidate("White & Spirit - Notre monde (feat. IAM)", artist: "White - Topic", credit: "White feat. Spirit feat. IAM")
        XCTAssertLessThan(Matching.score(unrelated, for: requested), 0.85)
    }

    func testCommaInsideArtistNameIsNotSpotifyCollaboratorSeparator() {
        let requested = target("See You Again (feat. Kali Uchis)", artist: "Tyler, The Creator,\u{00A0}Kali Uchis")
        let correct = candidate("See You Again (feat. Kali Uchis)", artist: "Tyler, The Creator", credit: "Tyler, The Creator feat. Kali Uchis")
        XCTAssertGreaterThanOrEqual(Matching.score(correct, for: requested), 0.85)
        let unrelated = candidate("Tyler, The Creator - See You Again (feat. Kali Uchis)", artist: "The Creator", credit: "The Creator feat. Kali Uchis")
        XCTAssertLessThan(Matching.score(unrelated, for: requested), 0.85)
    }

    func testCreditedHomonymCannotBeOverruledByTitleOrUploader() {
        let requested = target("Notre monde", artist: "Renaud")
        let wrong = candidate("Renaud - Notre monde", artist: "Renaud", credit: "Renaud Capuçon")
        XCTAssertLessThan(Matching.score(wrong, for: requested), 0.85)
    }

    func testLiveRemixAndMedleyRemainDistinctAtIdenticalDuration() {
        let original = target("Notre monde", artist: "Axel")
        for version in ["Live", "Remix", "Medley"] {
            let alternate = candidate("Notre monde (\(version))", artist: "Axel", credit: "Axel")
            XCTAssertLessThan(Matching.score(alternate, for: original), 0.85, version)
            let requestedVersion = target("Notre monde (\(version))", artist: "Axel")
            let plain = candidate("Notre monde", artist: "Axel", credit: "Axel")
            XCTAssertLessThan(Matching.score(plain, for: requestedVersion), 0.85, version)
        }
    }

    func testFeaturingWordOutsideACreditStillBelongsToTheSongTitle() {
        let requested = target("Featuring You", artist: "Axel")
        XCTAssertGreaterThanOrEqual(Matching.score(candidate("Featuring You", artist: "Axel", credit: "Axel"), for: requested), 0.85)
        XCTAssertLessThan(Matching.score(candidate("You", artist: "Axel", credit: "Axel"), for: requested), 0.85)
    }

    func testUnparenthesizedGuestKeepsTrailingVersionAndDoesNotMatchShortEdit() {
        let title = "Notre monde featuring Nora - Extended Mix"
        XCTAssertEqual(Matching.musicalTitle(title), "Notre monde - Extended Mix")
        let requested = target(title, artist: "Axel,\u{00A0}Nora")
        let short = candidate("Notre monde feat. Nora", artist: "Axel", credit: "Axel feat. Nora")
        XCTAssertLessThan(Matching.score(short, for: requested), 0.85)
        let same = candidate(title, artist: "Axel", credit: "Axel feat. Nora")
        XCTAssertGreaterThanOrEqual(Matching.score(same, for: requested), 0.85)
        let different = candidate("Autre horizon featuring Nora - Extended Mix", artist: "Axel", credit: "Axel feat. Nora")
        XCTAssertLessThan(Matching.score(different, for: requested), 0.85)
    }
}
