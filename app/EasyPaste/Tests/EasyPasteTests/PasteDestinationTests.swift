import XCTest
@testable import EasyPaste

final class PasteDestinationTests: XCTestCase {
    func testFocusedCodexWinsOverStaleChromeAtShortcutTime() {
        XCTAssertEqual(PasteDestinationPolicy.resolve(own: 1, focused: 2, frontmost: 3, lastExternal: 3), 2)
    }
    func testOpeningMenuKeepsLastExternalAppWhenEasyPasteAlreadyActive() {
        XCTAssertEqual(PasteDestinationPolicy.resolve(own: 1, focused: 1, frontmost: 1, lastExternal: 2), 2)
        XCTAssertNil(PasteDestinationPolicy.resolve(own: 1, focused: 1, frontmost: 1, lastExternal: nil))
    }
    func testNoAccessibilityUsesCurrentApplicationBeforeHistory() {
        XCTAssertEqual(PasteDestinationPolicy.resolve(own: 1, focused: nil, frontmost: 2, lastExternal: 3), 2)
    }
    func testManualAppSwitchWhileLoadingDoesNotStealFocusBack() {
        XCTAssertFalse(PasteDestinationPolicy.canActivate(own: 1, destination: 2, frontmost: 3))
        XCTAssertFalse(PasteDestinationPolicy.canActivate(own: 1, destination: 2, frontmost: nil))
        XCTAssertTrue(PasteDestinationPolicy.canActivate(own: 1, destination: 2, frontmost: 1))
        XCTAssertTrue(PasteDestinationPolicy.canActivate(own: 1, destination: 2, frontmost: 2))
        XCTAssertFalse(PasteDestinationPolicy.canActivate(own: 1, destination: 1, frontmost: 1))
    }
}
