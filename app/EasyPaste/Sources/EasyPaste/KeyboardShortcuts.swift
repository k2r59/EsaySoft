import AppKit
import Carbon
import Combine

struct KeyboardBinding: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt
    let keyLabel: String
    static let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    init(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ label: String) {
        keyCode = code; modifiers = flags.intersection(Self.mask).rawValue; keyLabel = label
    }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers }
    var flags: NSEvent.ModifierFlags { .init(rawValue: modifiers) }
    var display: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") +
        (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + keyLabel
    }
    var carbonModifiers: UInt32 {
        (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.control) ? UInt32(controlKey) : 0) |
        (flags.contains(.option) ? UInt32(optionKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
    }
    func matches(_ event: NSEvent) -> Bool { keyCode == event.keyCode && flags == event.modifierFlags.intersection(Self.mask) }
    var shifted: Self { Self(keyCode, flags.union(.shift), keyLabel) }
    static let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
    static func capture(_ event: NSEvent) -> Self? {
        let raw = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        guard !raw.isEmpty, raw.count <= 8, !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return Self(event.keyCode, event.modifierFlags, raw)
    }
}

enum ShortcutAction: String, Codable, CaseIterable, Identifiable {
    case shelf, stack, capture, ocr, stop, search, edit, preview, paste, plainPaste
    case card1, card2, card3, card4, card5, card6, card7, card8, card9
    var id: String { rawValue }
    static let global: [Self] = [.shelf, .stack, .capture, .ocr, .stop]
    static let cards: [Self] = [.card1, .card2, .card3, .card4, .card5, .card6, .card7, .card8, .card9]
    var globalID: UInt32? { Self.global.firstIndex(of: self).map(UInt32.init) }
    var title: String {
        switch self {
        case .shelf: return "Barre rapide"
        case .stack: return "Copier le suivant dans la pile"
        case .capture: return "Capturer une zone"
        case .ocr: return "Extraire du texte"
        case .stop: return "Arrêter la vidéo"
        case .search: return "Rechercher"
        case .edit: return "Modifier / annoter"
        case .preview: return "Aperçu"
        case .paste: return "Coller"
        case .plainPaste: return "Coller sans mise en forme"
        default: return "Coller la carte \(Self.cards.firstIndex(of: self)! + 1)"
        }
    }
    var initial: KeyboardBinding {
        let capture: NSEvent.ModifierFlags = [.command, .option, .control]
        switch self {
        case .shelf: return .init(9, [.shift, .command], "V")
        case .stack: return .init(9, capture, "V")
        case .capture: return .init(8, capture, "C")
        case .ocr: return .init(7, capture, "X")
        case .stop: return .init(1, capture, "S")
        case .search: return .init(3, .command, "F")
        case .edit: return .init(14, .command, "E")
        case .preview: return .init(16, .command, "Y")
        case .paste: return .init(36, [], "↩")
        case .plainPaste: return .init(36, .shift, "↩")
        default:
            let index = Self.cards.firstIndex(of: self)!
            return .init([18,19,20,21,23,22,26,28,25][index], .command, String(index + 1))
        }
    }
}

@MainActor final class KeyboardShortcuts: ObservableObject {
    static let storageKey = "keyboardShortcuts.v1"
    @Published private(set) var bindings: [ShortcutAction: KeyboardBinding]
    @Published var recording: ShortcutAction?
    @Published var error: String?
    private let defaults: UserDefaults
    private let systemReserved: (KeyboardBinding) -> Bool
    var apply: (([ShortcutAction: KeyboardBinding]) -> String?)?
    var recordingChanged: ((Bool) -> Void)?
    var changed: (() -> Void)?
    static var initial: [ShortcutAction: KeyboardBinding] { Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.initial) }) }
    init(defaults: UserDefaults = .standard, systemReserved: ((KeyboardBinding) -> Bool)? = nil) {
        self.defaults = defaults
        self.systemReserved = systemReserved ?? Self.isSystemReserved
        var loaded = Self.initial
        // Corrupt/obsolete settings must never leave the user without shortcuts.
        if let data = defaults.data(forKey: Self.storageKey), data.count <= 32_768,
           let saved = try? JSONDecoder().decode([String: KeyboardBinding].self, from: data) {
            for (key, value) in saved { if let action = ShortcutAction(rawValue: key) { loaded[action] = value } }
            if Self.validation(loaded) != nil { loaded = Self.initial }
        }
        bindings = loaded
    }
    subscript(_ action: ShortcutAction) -> KeyboardBinding { bindings[action] ?? action.initial }
    func begin(_ action: ShortcutAction) { error = nil; recording = action; recordingChanged?(true) }
    func end() { recording = nil; recordingChanged?(false) }
    @discardableResult func set(_ action: ShortcutAction, to binding: KeyboardBinding) -> Bool {
        var next = bindings; next[action] = binding
        return commit(next)
    }
    @discardableResult func reset(_ action: ShortcutAction? = nil) -> Bool {
        if let action { return set(action, to: action.initial) }
        return commit(Self.initial)
    }
    private func commit(_ next: [ShortcutAction: KeyboardBinding]) -> Bool {
        if let issue = Self.validation(next) { error = issue; return false }
        if let entry = next.first(where: { bindings[$0.key] != $0.value && systemReserved($0.value) }) {
            error = "\(entry.value.display) est réservé dans les réglages clavier de macOS."; return false
        }
        if let issue = apply?(next) { error = issue; return false }
        guard let data = try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: next.map { ($0.key.rawValue, $0.value) })) else { return false }
        bindings = next; defaults.set(data, forKey: Self.storageKey); error = nil; changed?(); return true
    }
    static func validation(_ values: [ShortcutAction: KeyboardBinding]) -> String? {
        var occupied: [(ShortcutAction, KeyboardBinding)] = []
        for action in ShortcutAction.allCases {
            guard let value = values[action], value.keyCode < 128, !(54...63).contains(value.keyCode),
                  value.modifiers == value.flags.intersection(KeyboardBinding.mask).rawValue,
                  !value.keyLabel.isEmpty, value.keyLabel.count <= 8,
                  !value.keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return "Combinaison non reconnue." }
            let isReturn = [ShortcutAction.paste, .plainPaste].contains(action) && value.keyCode == 36
            let function = KeyboardBinding.special[value.keyCode]?.hasPrefix("F") == true
            guard isReturn || function || !value.flags.intersection([.command, .control]).isEmpty else { return "Ajoute ⌘ ou ⌃ pour ne pas gêner la saisie." }
            let letter = value.keyLabel.uppercased()
            let nativeCommand = value.flags == .command && ([0,6,7,8,9,12,13,31,35,45,46,4,17,43].contains(value.keyCode) || ["A","C","V","X","Z","Q","W","H","M","N","O","T",","].contains(letter))
            let fixedLocal = action.globalID == nil && ([49,51,123,124,125,126].contains(value.keyCode) ||
                (value.flags.contains(.command) && ["N","O","T","C","Z"].contains(letter)))
            if [48, 53].contains(value.keyCode) || nativeCommand || fixedLocal {
                return "Cette combinaison est réservée aux commandes habituelles de macOS ou d’EasyPaste."
            }
            let chords = ShortcutAction.cards.contains(action) && !value.flags.contains(.shift) ? [value, value.shifted] : [value]
            for chord in chords {
                if let conflict = occupied.first(where: { $0.1 == chord }) { return "Déjà utilisé pour « \(conflict.0.title) »." }
                occupied.append((action, chord))
            }
        }
        return nil
    }
    static func isSystemReserved(_ binding: KeyboardBinding) -> Bool {
        var keys: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&keys) == noErr, let rows = keys?.takeRetainedValue() as? [[String: Any]] else { return false }
        return rows.contains {
            ($0[kHISymbolicHotKeyEnabled as String] as? Bool) == true &&
            ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint16Value == binding.keyCode &&
            ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == binding.carbonModifiers
        }
    }
}

/// Carbon registration is transactional: on conflict keep the previous bindings
/// and restore every previously working registration, including after a reset.
@MainActor final class GlobalShortcutRegistry {
    typealias Register = (ShortcutAction, KeyboardBinding) -> EventHotKeyRef?
    private let register: Register
    private let unregister: (EventHotKeyRef) -> Void
    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var active: [ShortcutAction: KeyboardBinding] = [:]
    private var configured: [ShortcutAction: KeyboardBinding] = [:]
    init(register: @escaping Register = { action, binding in
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(binding.keyCode), binding.carbonModifiers,
            EventHotKeyID(signature: 0x45504153, id: action.globalID!), GetApplicationEventTarget(), 0, &ref)
        return status == noErr ? ref : nil
    }, unregister: @escaping (EventHotKeyRef) -> Void = { UnregisterEventHotKey($0) }) {
        self.register = register; self.unregister = unregister
    }
    func suspend() { refs.values.forEach(unregister); refs = [:]; active = [:] }
    func start(_ values: [ShortcutAction: KeyboardBinding]) -> String? {
        suspend()
        configured = values.filter { $0.key.globalID != nil }
        var failed: [String] = []
        for action in ShortcutAction.global {
            if let binding = values[action], let ref = register(action, binding) { refs[action] = ref; active[action] = binding }
            else { failed.append(action.title) }
        }
        return failed.isEmpty ? nil : "Raccourci indisponible : \(failed.joined(separator: ", ")). Choisis une autre combinaison."
    }
    func replace(_ values: [ShortcutAction: KeyboardBinding]) -> String? {
        let globals = values.filter { $0.key.globalID != nil }
        let changed = ShortcutAction.global.filter { globals[$0] != configured[$0] }
        if changed.isEmpty { return nil }
        let previous = active
        func releaseChanged() {
            for action in changed {
                if let ref = refs.removeValue(forKey: action) { unregister(ref) }
                active.removeValue(forKey: action)
            }
        }
        releaseChanged()
        for action in changed {
            if let binding = globals[action], let ref = register(action, binding) { refs[action] = ref; active[action] = binding }
            else {
                releaseChanged()
                var lost: [String] = []
                for old in changed {
                    guard let binding = previous[old] else { continue }
                    if let ref = register(old, binding) { refs[old] = ref; active[old] = binding } else { lost.append(old.title) }
                }
                let recovery = lost.isEmpty ? "" : " À réactiver : \(lost.joined(separator: ", "))."
                return "« \(action.title) » : combinaison déjà utilisée ou indisponible.\(recovery)"
            }
        }
        configured = globals
        return nil
    }
}
