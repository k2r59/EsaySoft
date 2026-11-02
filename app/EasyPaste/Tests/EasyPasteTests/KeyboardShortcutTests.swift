import AppKit
import Carbon
import XCTest
@testable import EasyPaste

@MainActor final class KeyboardShortcutTests: XCTestCase {
    private func withModel(_ run: (KeyboardShortcuts, UserDefaults) throws -> Void) rethrows {
        let name = "EasyPaste.shortcut-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try run(KeyboardShortcuts(defaults: defaults, systemReserved: { _ in false }), defaults)
    }
    func testDefaultsExactlyPreserveExistingGlobalAndLocalShortcuts() {
        withModel { model, _ in
            XCTAssertNil(KeyboardShortcuts.validation(model.bindings))
            XCTAssertEqual(model[.shelf].display, "⇧⌘V")
            XCTAssertEqual(model[.capture].carbonModifiers, UInt32(cmdKey | optionKey | controlKey))
            XCTAssertEqual(model[.paste], .init(36, [], "↩")); XCTAssertEqual(model[.plainPaste], .init(36, .shift, "↩"))
            XCTAssertEqual(ShortcutAction.global.map { model[$0].keyCode }, [9,9,8,7,1])
            XCTAssertEqual(ShortcutAction.cards.map { model[$0].display }, (1...9).map { "⌘\($0)" })
        }
    }
    func testChangePersistsAcrossRestartAndResetRestoresOnlyRequestedBinding() {
        withModel { model, defaults in
            let binding = KeyboardBinding(40, [.control,.option], "K")
            XCTAssertTrue(model.set(.shelf, to: binding))
            XCTAssertEqual(KeyboardShortcuts(defaults: defaults)[.shelf], binding)
            XCTAssertTrue(model.set(.edit, to: .init(37, [.control,.command], "L")))
            XCTAssertTrue(model.reset(.shelf)); XCTAssertEqual(model[.shelf], ShortcutAction.shelf.initial)
            XCTAssertNotEqual(model[.edit], ShortcutAction.edit.initial)
            XCTAssertTrue(model.reset()); XCTAssertEqual(model.bindings, KeyboardShortcuts.initial)
        }
    }
    func testDuplicatesAndImplicitPlainCardShortcutsAreRejectedWithoutSaving() {
        withModel { model, defaults in
            XCTAssertFalse(model.set(.shelf, to: model[.capture]))
            XCTAssertFalse(model.set(.preview, to: model[.card1].shifted))
            XCTAssertNil(defaults.data(forKey: KeyboardShortcuts.storageKey))
            XCTAssertEqual(model.bindings, KeyboardShortcuts.initial)
        }
    }
    func testTypingKeysAndNativeCommandsRemainAvailable() {
        withModel { model, _ in
            for binding in [KeyboardBinding(0, [], "A"), .init(36, [], "↩"), .init(53, .command, "⎋"), .init(9, .command, "V"), .init(12, .command, "Q")] {
                XCTAssertFalse(model.set(.capture, to: binding))
            }
            XCTAssertTrue(model.set(.paste, to: .init(40, [.control,.command], "K")))
            XCTAssertTrue(model.reset(.paste))
        }
    }
    func testSystemConflictAndRuntimeConflictDoNotOverwritePreviousPreference() {
        withModel { model, defaults in
            model.apply = { _ in "Déjà utilisé" }
            XCTAssertFalse(model.set(.shelf, to: .init(40, [.control,.command], "K")))
            XCTAssertEqual(model.error, "Déjà utilisé")
            XCTAssertNil(defaults.data(forKey: KeyboardShortcuts.storageKey))
            let reserved = KeyboardShortcuts(defaults: defaults, systemReserved: { _ in true })
            XCTAssertFalse(reserved.set(.shelf, to: .init(49, .command, "Espace")))
            XCTAssertEqual(reserved[.shelf], ShortcutAction.shelf.initial)
        }
    }
    func testCorruptPreferencesRecoverDefaults() {
        withModel { _, defaults in
            defaults.set(Data("invalid".utf8), forKey: KeyboardShortcuts.storageKey)
            XCTAssertEqual(KeyboardShortcuts(defaults: defaults).bindings, KeyboardShortcuts.initial)
            let data = try! JSONEncoder().encode(["shelf": KeyboardBinding(9, .command, "V")])
            defaults.set(data, forKey: KeyboardShortcuts.storageKey)
            XCTAssertEqual(KeyboardShortcuts(defaults: defaults).bindings, KeyboardShortcuts.initial)
        }
    }
    func testRecorderSuspendsAndRestoresWithoutChangingBindingsOnCancel() {
        withModel { model, _ in
            var transitions: [Bool] = []
            model.recordingChanged = { transitions.append($0) }
            model.begin(.shelf); XCTAssertEqual(model.recording, .shelf)
            model.end(); XCTAssertNil(model.recording)
            XCTAssertEqual(transitions, [true, false]); XCTAssertEqual(model.bindings, KeyboardShortcuts.initial)
        }
    }
    func testRegistryRollsBackFailedUpdateAndReleasesTemporaryRegistrations() {
        var allocated = 0
        var live: [EventHotKeyRef: KeyboardBinding] = [:]
        var reject = false
        let registry = GlobalShortcutRegistry(register: { _, binding in
            if reject && binding.keyCode == 40 { return nil }
            allocated += 1
            let token = EventHotKeyRef(bitPattern: allocated)!
            live[token] = binding; return token
        }, unregister: { live.removeValue(forKey: $0) })
        XCTAssertNil(registry.start(KeyboardShortcuts.initial)); XCTAssertEqual(live.count, 5)
        var changed = KeyboardShortcuts.initial; changed[.capture] = .init(40, [.control,.command], "K")
        reject = true
        XCTAssertNotNil(registry.replace(changed)); XCTAssertEqual(live.count, 5)
        XCTAssertEqual(Set(live.values.map(\.display)), Set(ShortcutAction.global.map { $0.initial.display }))
        registry.suspend(); XCTAssertTrue(live.isEmpty)
    }
    func testResetHandlesSwappedGlobalsWithoutSelfConflict() {
        var allocated = 0
        var live: [EventHotKeyRef: KeyboardBinding] = [:]
        let registry = GlobalShortcutRegistry(register: { _, binding in
            guard !live.values.contains(binding) else { return nil }
            allocated += 1; let token = EventHotKeyRef(bitPattern: allocated)!; live[token] = binding; return token
        }, unregister: { live.removeValue(forKey: $0) })
        var swapped = KeyboardShortcuts.initial
        swapped[.shelf] = ShortcutAction.capture.initial; swapped[.capture] = ShortcutAction.shelf.initial
        XCTAssertNil(registry.start(swapped)); XCTAssertNil(registry.replace(KeyboardShortcuts.initial))
        XCTAssertEqual(live.count, 5); registry.suspend()
    }
    func testAnExistingUnavailableShortcutDoesNotBlockEditingAnother() {
        var allocated = 0
        var live: [EventHotKeyRef: KeyboardBinding] = [:]
        let registry = GlobalShortcutRegistry(register: { action, binding in
            if action == .capture { return nil }
            allocated += 1; let token = EventHotKeyRef(bitPattern: allocated)!; live[token] = binding; return token
        }, unregister: { live.removeValue(forKey: $0) })
        XCTAssertNotNil(registry.start(KeyboardShortcuts.initial))
        let unchanged = live.filter { $0.value != ShortcutAction.shelf.initial }
        var changed = KeyboardShortcuts.initial; changed[.shelf] = .init(40, [.control,.command], "K")
        XCTAssertNil(registry.replace(changed)); XCTAssertEqual(live.count, 4)
        for (ref, binding) in unchanged { XCTAssertEqual(live[ref], binding) }
        registry.suspend()
    }
    func testMatchingIgnoresCapsLockButNotExtraModifiers() throws {
        let binding = ShortcutAction.shelf.initial
        func event(_ flags: NSEvent.ModifierFlags) -> NSEvent { NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: "V", charactersIgnoringModifiers: "v", isARepeat: false, keyCode: 9)! }
        XCTAssertTrue(binding.matches(event([.command,.shift,.capsLock])))
        XCTAssertFalse(binding.matches(event([.command,.shift,.option])))
        XCTAssertEqual(KeyboardBinding.capture(event([.command,.shift]))?.display, "⇧⌘V")
    }
}

@MainActor final class ShortcutRecordingTests: XCTestCase {
    func testRecorderConsumesCommandInsteadOfDispatchingItAndEscapeCancels() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 150), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; defer { window.close() }
        let view = ShortcutCaptureView(); window.contentView = view; window.makeFirstResponder(view)
        var received: UInt16?, cancelled = false
        view.received = { received = $0.keyCode }; view.cancel = { cancelled = true }
        let command = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12)!
        XCTAssertTrue(view.performKeyEquivalent(with: command)); XCTAssertEqual(received, 12)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape); XCTAssertTrue(cancelled)
    }
    func testKeyboardLayoutsAndFixedNavigationCannotShadowLocalActions() {
        var bindings = KeyboardShortcuts.initial
        bindings[.preview] = .init(41, .command, "M")
        XCTAssertNotNil(KeyboardShortcuts.validation(bindings))
        bindings = KeyboardShortcuts.initial; bindings[.paste] = .init(49, .control, "Espace")
        XCTAssertNotNil(KeyboardShortcuts.validation(bindings))
        bindings = KeyboardShortcuts.initial; bindings[.preview] = .init(45, [.command,.control], "N")
        XCTAssertNotNil(KeyboardShortcuts.validation(bindings))
    }
}
