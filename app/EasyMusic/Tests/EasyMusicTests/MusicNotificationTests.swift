import XCTest
@testable import EasyMusic

@MainActor final class MusicNotificationTests: XCTestCase {
    private func fixture() throws -> (store: MusicStore, root: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EasyMusic-Notifications-QA-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = MusicStore(storageURL: root.appendingPathComponent("library.json"),
                               downloadFolder: root.appendingPathComponent("Music"), observePlayback: false)
        store.downloadWorker = { _, _, _, _ in
            XCTFail("Un test de notification ne doit pas atteindre un vrai service")
            throw AudioFailure.network
        }
        return (store, root)
    }

    private func track(_ id: String) -> Track {
        Track(id: id, title: "Titre " + id, artist: "Artiste " + id, duration: 120,
              url: "https://example.com/" + id, source: "QA")
    }

    private func saveFixture(_ track: Track, folder: URL) throws -> (Track, String) {
        let file = folder.appendingPathComponent(track.id + ".m4a")
        try Data([1, 2, 3]).write(to: file)
        return (track, file.path)
    }

    private func eventually(timeout: TimeInterval = 3, _ predicate: () -> Bool,
                            file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(predicate(), "État attendu absent", file: file, line: line)
    }

    func testErrorsStayAheadOfCoalescedConfirmations() throws {
        let notices = MusicNotifications()
        notices.post("Premier titre enregistré")
        let oldConfirmation = try XCTUnwrap(notices.current)
        notices.post("Premier problème", warning: true)
        notices.post("Deuxième titre enregistré")
        notices.post("Deuxième problème", warning: true)
        notices.post("Troisième titre enregistré")
        XCTAssertEqual(notices.messages.map(\.message), ["Premier problème", "Deuxième problème", "Troisième titre enregistré"])
        XCTAssertEqual(notices.messages.map(\.warning), [true, true, false])
        notices.expire(oldConfirmation.id)
        XCTAssertEqual(notices.messages.count, 3)
        notices.dismiss(try XCTUnwrap(notices.current).id)
        XCTAssertEqual(notices.current?.message, "Deuxième problème")
        notices.dismiss(try XCTUnwrap(notices.current).id)
        XCTAssertEqual(notices.current?.message, "Troisième titre enregistré")
    }

    func testRepeatedErrorIsDeduplicatedUntilUserDismissesIt() throws {
        let notices = MusicNotifications()
        notices.post("Serveur distant fermé", warning: true)
        let first = try XCTUnwrap(notices.current)
        notices.post(first.message, warning: true)
        notices.post("Confirmation")
        notices.post(first.message, warning: true)
        XCTAssertEqual(notices.messages.filter(\.warning).count, 1)
        XCTAssertEqual(notices.current?.id, first.id)
        notices.expire(first.id)
        XCTAssertEqual(notices.current?.id, first.id)
        notices.dismiss(first.id)
        notices.post(first.message, warning: true)
        XCTAssertNotEqual(notices.current?.id, first.id)
        XCTAssertEqual(notices.current?.message, first.message)
    }

    func testOnlyCurrentConfirmationExpiresAndOldTimerCannotDismissNewMessage() throws {
        let notices = MusicNotifications()
        notices.post("Terminé")
        let first = try XCTUnwrap(notices.current)
        notices.post("Terminé")
        let second = try XCTUnwrap(notices.current)
        XCTAssertNotEqual(first.id, second.id)
        notices.expire(first.id)
        XCTAssertEqual(notices.current?.id, second.id)
        notices.post("Connexion fermée", warning: true)
        let failure = try XCTUnwrap(notices.current)
        notices.expire(second.id)
        XCTAssertEqual(notices.messages.count, 2)
        notices.expire(failure.id)
        XCTAssertEqual(notices.current?.id, failure.id)
        notices.dismiss(failure.id)
        notices.expire(second.id)
        XCTAssertNil(notices.current)
    }

    func testExplicitErrorDoesNotDependOnFrenchKeywords() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.store.showError(AudioFailure.unavailable.localizedDescription)
        let notice = try XCTUnwrap(f.store.notifications.current)
        XCTAssertTrue(notice.warning)
        XCTAssertEqual(notice.message, AudioFailure.unavailable.localizedDescription)
        f.store.notifications.expire(notice.id)
        XCTAssertEqual(f.store.notifications.current?.id, notice.id)
    }

    func testSuccessfulDownloadOfErrorWordTitleRemainsAnExpiringConfirmation() async throws {
        for title in ["Erreur", "Impossible"] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            var song = track(title.lowercased()); song.title = title
            f.store.downloadWorker = { requested, _, _, folder in try self.saveFixture(requested, folder: folder) }
            f.store.enqueue(song)
            try await eventually { f.store.activeDownloads.isEmpty }
            let confirmation = try XCTUnwrap(f.store.notifications.current)
            XCTAssertFalse(confirmation.warning)
            XCTAssertTrue(confirmation.message.contains(title))
            XCTAssertTrue(f.store.downloadErrors.isEmpty)
            XCTAssertNotNil(f.store.downloaded(song))
            f.store.notifications.expire(confirmation.id)
            XCTAssertNil(f.store.notifications.current)
        }
    }

    func testNavigationAndClearingLegacyNoticePreservePersistentError() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.store.showError("Connexion distante fermée")
        let error = try XCTUnwrap(f.store.notifications.current)
        f.store.notice = nil
        f.store.section = "search"
        f.store.query = ""
        f.store.changeMode(.albums)
        f.store.backFromCollection()
        f.store.section = "settings"
        f.store.notice = "Réglage enregistré"
        XCTAssertEqual(f.store.notifications.current?.id, error.id)
        XCTAssertTrue(f.store.notifications.current?.warning == true)
        XCTAssertEqual(f.store.notifications.messages.count, 2)
    }

    func testConcurrentDownloadSuccessCannotHideFailureInEitherCompletionOrder() async throws {
        for failureFirst in [true, false] {
            let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
            let failed = track("échec"), successful = track("réussite")
            var started = Set<String>(), released = Set<String>()
            f.store.downloadWorker = { song, _, _, folder in
                started.insert(song.id)
                while !released.contains(song.id) { try await Task.sleep(nanoseconds: 10_000_000) }
                if song.id == failed.id { throw AudioFailure.unavailable }
                return try self.saveFixture(song, folder: folder)
            }
            f.store.enqueue(failed); f.store.enqueue(successful)
            try await eventually { started.count == 2 }
            released.insert(failureFirst ? failed.id : successful.id)
            try await eventually { f.store.activeDownloads.count == 1 }
            released.formUnion([failed.id, successful.id])
            try await eventually { f.store.activeDownloads.isEmpty && f.store.pending.isEmpty }
            let error = try XCTUnwrap(f.store.notifications.current)
            XCTAssertTrue(error.warning)
            XCTAssertTrue(error.message.contains(failed.title))
            XCTAssertTrue(error.message.contains(AudioFailure.unavailable.localizedDescription))
            XCTAssertNotNil(f.store.downloadErrors[failed.id])
            XCTAssertNil(f.store.downloadErrors[successful.id])
            XCTAssertEqual(f.store.library.tracks.map { $0.track.id }, [successful.id])
            XCTAssertEqual(f.store.notifications.messages.filter { !$0.warning }.count, 1)
        }
    }

    func testConcurrentFailuresKeepBothTrackNamesAndCreateNoLocalMedia() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let songs = [track("alpha"), track("beta")]
        f.store.downloadWorker = { _, _, _, _ in throw AudioFailure.unavailable }
        songs.forEach { f.store.enqueue($0) }
        try await eventually { f.store.activeDownloads.isEmpty && f.store.pending.isEmpty }
        XCTAssertEqual(f.store.downloadErrors.count, 2)
        XCTAssertEqual(f.store.notifications.messages.count, 2)
        XCTAssertTrue(f.store.notifications.messages.allSatisfy(\.warning))
        for song in songs {
            XCTAssertTrue(f.store.notifications.messages.contains { $0.message.contains(song.title) })
        }
        XCTAssertTrue(f.store.library.tracks.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.store.folder.path), [])
    }

    func testRetryClearsTrackFailureAndQueuesSuccessBehindUndismissedError() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let song = track("retry")
        var attempts = 0
        f.store.downloadWorker = { requested, _, _, folder in
            attempts += 1
            if attempts == 1 { throw AudioFailure.unavailable }
            return try self.saveFixture(requested, folder: folder)
        }
        f.store.enqueue(song)
        try await eventually { f.store.activeDownloads.isEmpty }
        let firstError = try XCTUnwrap(f.store.notifications.current)
        XCTAssertNotNil(f.store.downloadErrors[song.id])
        f.store.enqueue(song)
        XCTAssertNil(f.store.downloadErrors[song.id])
        try await eventually { f.store.activeDownloads.isEmpty }
        XCTAssertEqual(attempts, 2)
        XCTAssertNotNil(f.store.downloaded(song))
        XCTAssertEqual(f.store.notifications.current?.id, firstError.id)
        XCTAssertEqual(f.store.notifications.messages.count, 2)
        f.store.notifications.dismiss(firstError.id)
        let success = try XCTUnwrap(f.store.notifications.current)
        XCTAssertFalse(success.warning)
        XCTAssertTrue(success.message.contains(song.title))
        f.store.notifications.expire(firstError.id)
        XCTAssertEqual(f.store.notifications.current?.id, success.id)
        f.store.notifications.expire(success.id)
        XCTAssertNil(f.store.notifications.current)
    }

    func testLibrarySaveErrorRemainsVisibleAfterDownloadSuccess() async throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        try FileManager.default.createDirectory(at: f.store.storage, withIntermediateDirectories: true)
        let song = track("save")
        f.store.downloadWorker = { requested, _, _, folder in try self.saveFixture(requested, folder: folder) }
        f.store.enqueue(song)
        try await eventually { f.store.activeDownloads.isEmpty }
        let failure = try XCTUnwrap(f.store.notifications.current)
        XCTAssertTrue(failure.warning)
        XCTAssertTrue(failure.message.hasPrefix("Impossible d’enregistrer la bibliothèque"))
        XCTAssertTrue(f.store.notifications.messages.contains { !$0.warning && $0.message.contains(song.title) })
        XCTAssertNotNil(f.store.downloaded(song))
        f.store.notifications.expire(failure.id)
        XCTAssertEqual(f.store.notifications.current?.id, failure.id)
    }

    func testMissingLocalFilePostsPersistentError() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        let local = LocalTrack(track: track("missing"), path: f.root.appendingPathComponent("missing.m4a").path)
        f.store.library.tracks = [local]
        f.store.play(local)
        let error = try XCTUnwrap(f.store.notifications.current)
        XCTAssertTrue(error.warning, "Un fichier manquant doit produire une erreur persistante")
        f.store.notifications.expire(error.id)
        XCTAssertEqual(f.store.notifications.current?.id, error.id)
        XCTAssertNil(f.store.currentTrack)
        XCTAssertFalse(f.store.isPlaying)
    }

    func testImportWarningPersistsIndependentlyOfConfirmationAndPriorError() throws {
        let f = try fixture(); defer { try? FileManager.default.removeItem(at: f.root) }
        f.store.showError("Connexion distante fermée")
        let oldError = try XCTUnwrap(f.store.notifications.current)
        let warning = "56 titres sur les 61 annoncés sont accessibles."
        f.store.acceptImport(ImportedPlaylist(name: "Import QA", sourceURL: "https://www.deezer.com/playlist/1",
                                              tracks: [track("import")], warning: warning))
        XCTAssertEqual(f.store.notifications.current?.id, oldError.id)
        XCTAssertEqual(f.store.currentPlaylist?.importWarning, warning)
        f.store.notice = nil
        f.store.section = "home"
        let restored = MusicStore(storageURL: f.store.storage, downloadFolder: f.store.folder, observePlayback: false)
        XCTAssertEqual(restored.library.playlists.first?.importWarning, warning)
        XCTAssertTrue(restored.library.tracks.isEmpty)
        XCTAssertTrue(restored.pending.isEmpty)
    }
}
