import XCTest
@testable import EasyPaste

final class AppUpdatesTests: XCTestCase {
    @MainActor func testEveryActiveOperationBlocksUpdates() {
        XCTAssertFalse(AppUpdates.isBusy(recording: false, capture: false, annotation: false,
                                        editor: false, preview: false, sampling: false, sharing: false))
        for index in 0..<7 {
            let flags = (0..<7).map { $0 == index }
            XCTAssertTrue(AppUpdates.isBusy(recording: flags[0], capture: flags[1], annotation: flags[2],
                                           editor: flags[3], preview: flags[4], sampling: flags[5], sharing: flags[6]))
        }
    }

    @MainActor func testNoNetworkOrAutomaticCheckOnConstruction() {
        let updates = AppUpdates()
        XCTAssertFalse(updates.available)
        XCTAssertFalse(updates.canCheck)
        XCTAssertFalse(updates.automaticChecks)
        updates.setAutomaticChecks(true)
        XCTAssertFalse(updates.automaticChecks)
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
