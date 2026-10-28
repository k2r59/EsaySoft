import AppKit
import SwiftUI

/// Focus the actual AppKit editor, even when SwiftUI's previous focus value
/// outlives a hidden/reopened shelf. Requests are scoped to one window.
final class SearchTextField: NSTextField {
    static let focusNotification = Notification.Name("EasyPaste.focusSearch")
    private(set) var pendingFocus = false
    private var focusObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var keyObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false; drawsBackground = false; focusRingType = .none
        isEditable = true; isSelectable = true
        cell?.usesSingleLineMode = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setAccessibilityLabel("Rechercher dans l’historique")
        focusObserver = NotificationCenter.default.addObserver(forName: Self.focusNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let target = note.object as? NSWindow, self.window === target else { return }
                self.requestFocus()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusIfReady() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        for token in [focusObserver, activationObserver, keyObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(token) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver); self.keyObserver = nil }
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusIfReady() }
        }
        // Attach/layout can finish after the notification requesting focus.
        DispatchQueue.main.async { [weak self] in self?.focusIfReady() }
    }

    override func layout() { super.layout(); focusIfReady() }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { pendingFocus = false }
        return accepted
    }

    func requestFocus() {
        pendingFocus = true
        focusIfReady()
    }

    private func focusIfReady() {
        guard pendingFocus, let window, window.isVisible, window.isKeyWindow,
              !isHiddenOrHasHiddenAncestor, bounds.width > 0, bounds.height > 0 else { return }
        if let editor = currentEditor(), window.firstResponder === editor { pendingFocus = false; return }
        if window.makeFirstResponder(self) { pendingFocus = false }
    }
}

struct SearchInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let prompt: String
    let color: Color
    let fontSize: CGFloat
    var focusOnAppear = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> SearchTextField {
        let view = SearchTextField(frame: .zero)
        view.delegate = context.coordinator
        updateNSView(view, context: context)
        if focusOnAppear { view.requestFocus() }
        return view
    }
    func updateNSView(_ view: SearchTextField, context: Context) {
        context.coordinator.parent = self
        if view.stringValue != text { view.stringValue = text }
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = NSColor(Theme.ink)
        view.placeholderAttributedString = NSAttributedString(string: prompt, attributes: [.foregroundColor: NSColor(color), .font: NSFont.systemFont(ofSize: fontSize)])
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchInput
        init(_ parent: SearchInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in self?.parent.focused = true }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            DispatchQueue.main.async { [weak self] in self?.parent.focused = false }
        }
    }
}
