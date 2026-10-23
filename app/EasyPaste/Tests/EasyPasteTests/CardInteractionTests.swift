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
    func testDoubleClickPastesOnceAndFirstClickOnlySelects() {
        let clip = history.visible[2]
        var pasted: [[UUID]] = []
        history.paste = { clips, plain in pasted.append(clips.map(\.id)); XCTAssertFalse(plain) }
        let action = CardInteraction(history: history, clip: clip)
        action.select(clickCount: 1, modifiers: [])
        XCTAssertTrue(pasted.isEmpty)
        XCTAssertEqual(history.selected, clip.id)
        action.select(clickCount: 2, modifiers: [])
        action.activate(modifiers: [])
        XCTAssertEqual(pasted, [[clip.id]])
    }

    func testShelfModifiedClicksKeepMultiSelectionWithoutPasting() {
        history.paste = { _, _ in XCTFail("A selection modifier must not paste") }
        history.select(history.visible[0])
        let action = CardInteraction(history: history, clip: history.visible[2])
        action.select(clickCount: 1, modifiers: .shift)
        XCTAssertEqual(history.selectedIDs.count, 3)
        action.select(clickCount: 1, modifiers: .command)
        XCTAssertEqual(history.selectedIDs.count, 2)
        action.select(clickCount: 1, modifiers: .control)
        for modifiers: NSEvent.ModifierFlags in [.command, .shift, .control, .option] {
            action.activate(modifiers: modifiers)
        }
    }

    func testCancelledTrashKeepsItemAndConfirmationEvenWithCheckbox() {
        let clip = history.visible[0]
        XCTAssertTrue(history.confirmTrash)
        history.requestTrash([clip]) { count in
            XCTAssertEqual(count, 1)
            return TrashDecision(approved: false, skipFuture: true)
        }
        XCTAssertNil(history.clips.first { $0.id == clip.id }?.trashedAt)
        XCTAssertTrue(history.confirmTrash)
        XCTAssertTrue(history.recentlyTrashed.isEmpty)
    }

    func testTrashSuppressionPersistsAndCanBeEnabledAgain() {
        let clips = history.visible
        var prompts = 0
        history.requestTrash([clips[0]]) { _ in
            prompts += 1
            return TrashDecision(approved: true, skipFuture: true)
        }
        XCTAssertFalse(history.confirmTrash)
        XCTAssertEqual(defaults.object(forKey: "confirmTrash") as? Bool, false)
        history.requestTrash([clips[1]]) { _ in XCTFail("Suppressed confirmation"); return TrashDecision(approved: false) }
        XCTAssertNotNil(history.clips.first { $0.id == clips[1].id }?.trashedAt)
        history.confirmTrash = true
        history.requestTrash([clips[2]]) { _ in prompts += 1; return TrashDecision(approved: false) }
        XCTAssertEqual(prompts, 2)
        XCTAssertNil(history.clips.first { $0.id == clips[2].id }?.trashedAt)
    }

    func testBatchTrashDeduplicatesAndIgnoresStaleItemsThenUndoRestores() {
        let clips = history.visible
        history.trash(clips[0])
        history.requestTrash([clips[0], clips[1], clips[1], makeClip("Absent")]) { count in
            XCTAssertEqual(count, 1)
            return TrashDecision(approved: true)
        }
        XCTAssertNotNil(history.clips.first { $0.id == clips[1].id }?.trashedAt)
        XCTAssertNil(history.clips.first { $0.id == clips[2].id }?.trashedAt)
        history.undoTrash()
        XCTAssertNil(history.clips.first { $0.id == clips[1].id }?.trashedAt)
        XCTAssertNotNil(history.clips.first { $0.id == clips[0].id }?.trashedAt)
        history.requestTrash([clips[0]]) { _ in XCTFail("Nothing left to trash"); return TrashDecision(approved: true) }
    }

    func testDoubleClickRestoresCurrentTrashedStateInsteadOfPastingStaleCard() {
        let clip = history.visible[0]
        history.paste = { _, _ in XCTFail("A trashed item must not paste") }
        history.trash(clip)
        CardInteraction(history: history, clip: clip).activate(modifiers: [])
        XCTAssertNil(history.clips.first { $0.id == clip.id }?.trashedAt)
    }

    func testFooterFavoriteDoesNotChangeSelectionOrPaste() {
        let first = history.visible[0], other = history.visible[1]
        history.select(first)
        history.paste = { _, _ in XCTFail("Favorite must not paste") }
        history.togglePin(other)
        XCTAssertTrue(history.clips.first { $0.id == other.id }!.pinned)
        XCTAssertEqual(history.selected, first.id)
        history.togglePin(other)
        XCTAssertFalse(history.clips.first { $0.id == other.id }!.pinned)
    }

    func testPreviewEligibilityDoesNotDependOnLoadedPayload() {
        var clip = makeClip("")
        for kind in ClipKind.allCases {
            clip.kind = kind
            XCTAssertEqual(clip.metadata().hasPreview, kind == .image || kind == .video)
            clip.text = "Un aperçu"
            XCTAssertTrue(clip.metadata().hasPreview)
            clip.text = ""
        }
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
