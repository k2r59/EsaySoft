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
    func testShelfClickPastesExactlyOnceWithoutWaitingForAnotherClick() {
        let clip = history.visible[2]
        var pasted: [[UUID]] = []
        history.paste = { clips, plain in pasted.append(clips.map(\.id)); XCTAssertFalse(plain) }
        let action = CardInteraction(history: history, clip: clip, pasteOnClick: true)
        action.select(clickCount: 1, modifiers: [])
        XCTAssertEqual(pasted, [[clip.id]])
        XCTAssertEqual(history.selected, clip.id)
        action.select(clickCount: 2, modifiers: [])
        XCTAssertEqual(pasted.count, 1)
    }

    func testShelfModifiedClicksKeepMultiSelectionWithoutPasting() {
        history.paste = { _, _ in XCTFail("A selection modifier must not paste") }
        history.select(history.visible[0])
        let action = CardInteraction(history: history, clip: history.visible[2], pasteOnClick: true)
        action.select(clickCount: 1, modifiers: .shift)
        XCTAssertEqual(history.selectedIDs.count, 3)
        action.select(clickCount: 1, modifiers: .command)
        XCTAssertEqual(history.selectedIDs.count, 2)
        action.select(clickCount: 1, modifiers: .control)
    }

    func testReopeningShelfKeepsSelectionAndArrowNavigationPosition() async throws {
        let clips = history.visible
        history.select(clips[1])
        for _ in 0..<3 {
            history.prepareShelf()
            try await settle()
            XCTAssertEqual(history.selected, clips[1].id)
            XCTAssertEqual(history.selection.map(\.id), [clips[1].id])
        }
        history.moveSelection(1)
        XCTAssertEqual(history.selected, clips[2].id)
    }

    func testNewCopySelectsNewestItemAndClearsPreviousMultiSelection() async throws {
        history.select(history.visible[1])
        history.select(history.visible[2], modifiers: .command)
        let fresh = makeClip("Nouvelle copie")
        history.add(fresh)
        XCTAssertEqual(history.selected, fresh.id)
        try await settle()
        history.prepareShelf(); try await settle()
        XCTAssertEqual(history.visible.first?.id, fresh.id)
        XCTAssertEqual(history.selection.map(\.id), [fresh.id])
    }

    func testRecopyingOldContentSelectsItsExistingCardAtTheFront() async throws {
        let old = history.visible.last!
        history.select(history.visible[0])
        history.add(makeClip(old.text))
        try await settle()
        XCTAssertEqual(history.visible.count, 3)
        XCTAssertEqual(history.visible.first?.id, old.id)
        XCTAssertEqual(history.selected, old.id)
    }

    func testCopyHiddenBySearchBecomesSelectedWhenShelfReopens() async throws {
        history.query = "Un"; try await settle()
        let fresh = makeClip("Copie hors recherche")
        history.add(fresh); try await settle()
        XCTAssertFalse(history.visible.contains { $0.id == fresh.id })
        history.prepareShelf(); try await settle()
        XCTAssertEqual(history.selected, fresh.id)
        XCTAssertEqual(history.selection.map(\.id), [fresh.id])
    }

    func testExplicitNavigationWinsOverPendingCopyAndMetadataRefresh() async throws {
        history.query = "Un"; try await settle()
        history.add(makeClip("Copie hors recherche")); try await settle()
        let chosen = history.visible[0]
        history.select(chosen)
        history.mutate(chosen.id) { $0.pinned = true }
        history.prepareShelf(); try await settle()
        XCTAssertEqual(history.selected, chosen.id)
    }

    func testCopyingHistoryItemDoesNotResetSelection() async throws {
        let chosen = history.visible[2]
        history.select(chosen)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let copied = await history.copy([chosen], to: board, sound: nil)
        XCTAssertTrue(copied)
        history.prepareShelf(); try await settle()
        XCTAssertEqual(history.selected, chosen.id)
        XCTAssertEqual(board.string(forType: .string), chosen.text)
    }

    private func settle() async throws {
        await history.flush()
        try await Task.sleep(for: .milliseconds(220))
    }

}
