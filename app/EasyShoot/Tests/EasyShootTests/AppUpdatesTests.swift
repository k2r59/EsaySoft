import XCTest
import AppKit
@testable import EasyShoot

final class AppUpdatesTests: XCTestCase {
    @MainActor func testCaptureSelectionAndScrollSessionBlockUpdates() {
        let owner = AppDelegate()
        XCTAssertFalse(owner.updateBusy)
        owner.busy = true; XCTAssertTrue(owner.updateBusy)
        owner.busy = false
        owner.selectors = [NSWindow()]; XCTAssertTrue(owner.updateBusy)
        owner.selectors = []
        let controller = ScrollingController(rect: CGRect(x: 0, y: 0, width: 320, height: 480), owner: owner)
        owner.scrolling = controller
        XCTAssertTrue(owner.updateBusy)
        controller.session.cancel()
        XCTAssertFalse(owner.updateBusy)
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
