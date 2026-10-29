import XCTest
@testable import EasyMusic
final class UpdatesAndPlayerTests: XCTestCase {
    @MainActor func testUpdaterDoesNotConnectDuringConstruction() {
        let updates = AppUpdates()
        XCTAssertFalse(updates.available)
        XCTAssertFalse(updates.canCheck)
        XCTAssertFalse(updates.automaticChecks)
    }
    @MainActor func testBusyOperationsDelayInstallationUntilExplicitRetry() {
        let updates = AppUpdates()
        var busy = true, installed = 0
        updates.busy = { busy }
        XCTAssertTrue(updates.postponeIfBusy { installed += 1 })
        updates.installWhenReady(); XCTAssertEqual(installed, 0)
        busy = false; XCTAssertEqual(installed, 0)
        updates.installWhenReady(); XCTAssertEqual(installed, 1)
        updates.installWhenReady(); XCTAssertEqual(installed, 1)
    }
    func testPlaybackOrderDoesNotWrapUnlessRepeatEnabled() {
        XCTAssertNil(PlaybackOrder.nextIndex(2, count: 3, offset: 1, repeats: false))
        XCTAssertEqual(PlaybackOrder.nextIndex(2, count: 3, offset: 1, repeats: true), 0)
        XCTAssertEqual(PlaybackOrder.nextIndex(0, count: 3, offset: -1, repeats: true), 2)
        XCTAssertNil(PlaybackOrder.nextIndex(0, count: 0, offset: 1, repeats: true))
        XCTAssertEqual(PlaybackOrder.nextIndex(0, count: 1, offset: 1, repeats: true), 0)
    }
}
