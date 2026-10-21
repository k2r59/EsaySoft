import XCTest
@testable import EasyTile

final class AppUpdatesTests: XCTestCase {
    @MainActor func testEveryActiveOperationBlocksUpdates() {
        XCTAssertFalse(AppUpdates.isBusy(editor: false, dragging: false, placement: false, palette: false))
        for index in 0..<4 {
            let flags = (0..<4).map { $0 == index }
            XCTAssertTrue(AppUpdates.isBusy(editor: flags[0], dragging: flags[1], placement: flags[2], palette: flags[3]))
        }
    }

    @MainActor func testNoNetworkOrAutomaticCheckOnConstruction() {
        let updates = AppUpdates()
        XCTAssertFalse(updates.available)
        XCTAssertFalse(updates.canCheck)
        XCTAssertFalse(updates.automaticChecks)
        updates.setAutomaticChecks(true)
        XCTAssertFalse(updates.automaticChecks)
        updates.setAutomaticInstall(true)
        XCTAssertFalse(updates.automaticInstall)
        updates.check()
        XCTAssertTrue(updates.message.isEmpty)
    }

    @MainActor func testInstallWaitsForExplicitRetryAndRunsOnlyOnce() {
        let updates = AppUpdates()
        var busy = true
        var installs = 0
        updates.busy = { busy }
        XCTAssertTrue(updates.postponeIfBusy { installs += 1 })
        XCTAssertTrue(updates.waitingToInstall)
        updates.installWhenReady()
        XCTAssertEqual(installs, 0)
        busy = false
        XCTAssertEqual(installs, 0, "Finishing a capture must not unexpectedly relaunch the app.")
        updates.installWhenReady()
        XCTAssertEqual(installs, 1)
        XCTAssertFalse(updates.waitingToInstall)
        updates.installWhenReady()
        XCTAssertEqual(installs, 1)
    }

    @MainActor func testIdleInstallIsLeftToSparkle() {
        let updates = AppUpdates()
        XCTAssertFalse(updates.postponeIfBusy { XCTFail("Sparkle owns an immediate install") })
        XCTAssertFalse(updates.waitingToInstall)
    }

    @MainActor func testBusyManualCheckExplainsWhyWithoutStartingNetwork() {
        let updates = AppUpdates()
        updates.busy = { true }
        updates.check()
        XCTAssertEqual(updates.message, AppUpdates.busyMessage)
        XCTAssertFalse(updates.canCheck)
    }
}
