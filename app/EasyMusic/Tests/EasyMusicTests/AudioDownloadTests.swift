import XCTest
@testable import EasyMusic

final class AudioDownloadTests: XCTestCase {
    func song(_ id: String, source: String = "YouTube", catalog: Bool = false) -> Track {
        Track(id: id, title: "Original Song", artist: "Artist", duration: 200,
              url: "https://example.com/\(id)", source: source, isCatalog: catalog)
    }
    func testDirectSuccessNeedsNoSearchOrSecondInspection() async throws {
        let target = song("direct")
        var calls = 0
        let result = try await AudioDownload.run(target: target, preferred: "140", search: { _, _ in
            XCTFail("Un lien audio direct ne nécessite aucune recherche"); return []
        }, transfer: { source, format in
            calls += 1; XCTAssertEqual(source.id, target.id); XCTAssertEqual(format, "140"); return "/audio.m4a"
        })
        XCTAssertEqual(result.1, "/audio.m4a")
        XCTAssertEqual(calls, 1)
    }
    func testProtectedSoundCloudFallsBackToMatchingYouTubeAudio() async throws {
        let target = song("protected", source: "SoundCloud"), replacement = song("replacement")
        var attempted: [String] = []
        let result = try await AudioDownload.run(target: target, preferred: "soundcloud-format", search: { _, service in
            XCTAssertEqual(service, "YouTube"); return [replacement]
        }, transfer: { source, format in
            attempted.append(source.id)
            if source.id == target.id { throw AudioFailure.protectedAudio }
            XCTAssertNil(format, "Les identifiants de format ne se réutilisent pas entre sources")
            return "/replacement.m4a"
        })
        XCTAssertEqual(attempted, ["protected", "replacement"])
        XCTAssertEqual(result.0.id, replacement.id)
    }
    func testFailedCandidateTriesNextAndRejectsCovers() async throws {
        var cover = song("cover"); cover.title += " cover"
        let first = song("first"), second = song("second")
        var attempted: [String] = []
        let result = try await AudioDownload.run(target: song("catalog", catalog: true), preferred: nil,
            search: { _, _ in [cover, first, second] }, transfer: { source, _ in
                attempted.append(source.id)
                if source.id == "first" { throw AudioFailure.network }
                return "/audio.m4a"
            })
        XCTAssertEqual(attempted, ["first", "second"])
        XCTAssertEqual(result.0.id, "second")
    }
    func testNoReliableAlternativeFailsClearlyWithoutDownloadingWrongSong() async {
        var unrelated = song("wrong"); unrelated.title = "Unrelated"; unrelated.artist = "Someone else"
        do {
            _ = try await AudioDownload.run(target: song("catalog", catalog: true), preferred: nil,
                search: { _, _ in [unrelated] }, transfer: { _, _ in XCTFail("Mauvais morceau"); return "" })
            XCTFail("Doit signaler l’absence de correspondance")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Aucune version audio")) }
    }
    func testLocalDiskFailureDoesNotTryOtherServices() async {
        do {
            _ = try await AudioDownload.run(target: song("direct"), preferred: nil,
                search: { _, _ in XCTFail("Le disque plein n’est pas une erreur de source"); return [] },
                transfer: { _, _ in throw AudioFailure.localFile })
            XCTFail("Doit signaler l’erreur disque")
        } catch { XCTAssertTrue(error.localizedDescription.contains("espace disponible")) }
    }
    func testAudioOnlyEvenWhenExplicitFormatIsRequested() {
        let args = Engine.downloadArguments(track: song("direct"), format: "137", folder: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(args[args.firstIndex(of: "-f")! + 1], "137[vcodec=none][acodec!=none]")
        XCTAssertFalse(args.contains("--allow-unplayable-formats"))
        XCTAssertEqual(AudioFailure.classify("ERROR: [soundcloud] This video is DRM protected").localizedDescription, "Cette source audio est protégée.")
    }
    func testFileLockAllowsDifferentSourcesButSerializesSameSource() async {
        let lock = DownloadFileLock()
        await lock.acquire("same")
        await lock.acquire("different")
        let waiting = Task { await lock.acquire("same"); await lock.release("same") }
        await lock.release("different")
        await lock.release("same")
        await waiting.value
        await lock.acquire("same")
        await lock.release("same")
    }
    func testOptionalArtworkFailureRetriesAudioAndTagsOnce() async throws {
        var options: [Bool] = []
        let result = try await AudioDownload.withOptionalArtwork(include: true) { artwork in
            options.append(artwork)
            if artwork { throw AudioFailure.other }
            return "FILE:/complete-audio.m4a"
        }
        XCTAssertEqual(options, [true, false])
        XCTAssertEqual(result, "FILE:/complete-audio.m4a")
    }
    func testArtworkFallbackDoesNotIgnoreDRMNetworkDiskOrCancellation() async {
        let errors: [Error] = [AudioFailure.protectedAudio, AudioFailure.network, AudioFailure.localFile, CancellationError()]
        for error in errors {
            var calls = 0
            do {
                _ = try await AudioDownload.withOptionalArtwork(include: true) { _ in calls += 1; throw error }
                XCTFail("Une erreur audio ne doit pas devenir un succès sans pochette")
            } catch { XCTAssertEqual(calls, 1) }
        }
    }
    func testArtworkFallbackRemainsBoundedAndIsAbsentForOriginalExport() async {
        for include in [true, false] {
            var calls = 0
            do {
                _ = try await AudioDownload.withOptionalArtwork(include: include) { _ in calls += 1; throw AudioFailure.other }
                XCTFail("Échec attendu")
            } catch { XCTAssertEqual(calls, include ? 2 : 1) }
        }
    }
}
