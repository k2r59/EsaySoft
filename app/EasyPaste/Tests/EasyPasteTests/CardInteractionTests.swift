import AppKit
import CryptoKit
import XCTest
@testable import EasyPaste

@MainActor final class CardInteractionTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var history: History!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suite = "EasyPaste.click-tests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        let vault = try ClipVault(directory: directory, key: SymmetricKey(size: .bits256))
        history = History(vault: vault, monitor: false, defaults: defaults)
        for text in ["Un", "Deux", "Trois"] { history.add(makeClip(text)) }
        await history.flush()
        for _ in 0..<100 where history.visible.count != 3 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(history.visible.count, 3)
    }

    override func tearDown() async throws {
        await history.flush()
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
        history = nil
    }

    func testSingleClickSelectsSynchronouslyWithoutCopyingOrReloadingHistory() {
        let clip = history.visible[1], snapshot = history.visible.map(\.id)
        history.paste = { _, _ in XCTFail("Selecting must not paste") }
        let action = CardInteraction(history: history, clip: clip)
        action.select(clickCount: 1, modifiers: [])
        XCTAssertEqual(history.selected, clip.id)
        XCTAssertEqual(history.selectedIDs, [clip.id])
        XCTAssertEqual(history.visible.map(\.id), snapshot)
    }

    func testSecondClickNeverTogglesCommandSelectionBackOff() {
        let first = history.visible[0], second = history.visible[1]
        history.select(first)
        let action = CardInteraction(history: history, clip: second)
        action.select(clickCount: 1, modifiers: .command)
        XCTAssertEqual(history.selectedIDs, [first.id, second.id])
        action.select(clickCount: 2, modifiers: .command)
        XCTAssertEqual(history.selectedIDs, [first.id, second.id])
        action.select(clickCount: 1, modifiers: .command)
        XCTAssertEqual(history.selectedIDs, [first.id])
    }

    func testShiftRangeAndKeyboardNavigationRemainImmediate() {
        let clips = history.visible
        history.select(clips[0])
        CardInteraction(history: history, clip: clips[2]).select(clickCount: 1, modifiers: .shift)
        XCTAssertEqual(history.selectedIDs, Set(clips.map(\.id)))
        history.moveSelection(-1)
        XCTAssertEqual(history.selected, clips[1].id)
        XCTAssertEqual(history.selectedIDs, [clips[1].id])
    }

    func testRepeatedSelectionsDoNotQueueDelayedActions() async throws {
        let clips = history.visible
        let actions = clips.map { CardInteraction(history: history, clip: $0) }
        let start = ContinuousClock.now
        for index in 0..<300 {
            actions[index % 3].select(clickCount: 1, modifiers: [])
            XCTAssertEqual(history.selected, clips[index % 3].id)
        }
        XCTAssertLessThan(start.duration(to: .now), .milliseconds(100))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(history.selected, clips[2].id)
    }
}
