import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import CryptoKit

@main struct EasyPasteMain {
    static func main() {
        if CommandLine.arguments.contains("--mcp") { MCPServer.run(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let history: History
    private var window: NSWindow!
    private var shelf: ShelfPanel?
    private var status: NSStatusItem!
    private var target: NSRunningApplication?
    private var hotkeys: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var keys: Any?
    private var resignObserver: NSObjectProtocol?
    private var demoDirectory: URL?
    private var isPasting = false
    private lazy var captures = CaptureController(history: history)
    private lazy var annotations = AnnotationController(history: history)
    private var recordingStatus: NSStatusItem?
    override init() {
        if CommandLine.arguments.contains("--demo") || Bundle.main.object(forInfoDictionaryKey: "EasyPasteDemo") as? Bool == true {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-demo-" + UUID().uuidString)
            demoDirectory = folder
            let preferences = UserDefaults(suiteName: "EasyPaste.demo")!
            preferences.set(false, forKey: "monitoring"); preferences.set(false, forKey: "mcpEnabled")
            history = History(vault: try! ClipVault(directory: folder, key: SymmetricKey(size: .bits256)), monitor: false, defaults: preferences)
        } else { history = History() }
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        target = NSWorkspace.shared.frontmostApplication
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1190, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "EasyPaste"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.delegate = self
        window.backgroundColor = NSColor(Theme.bg); window.minSize = NSSize(width: 1050, height: 740)
        window.contentView = NSHostingView(rootView: MainView(history: history)); window.isReleasedWhenClosed = false
        window.center(); window.setFrameAutosaveName("EasyPasteLibrary")
        buildMenu(); registerHotkeys()
        history.capture = { [weak self] action in self?.rememberTarget(); self?.captures.run(action) }
        history.annotate = { [weak self] clip in self?.annotations.open(clip) }
        history.stopRecording = { [weak self] in self?.captures.stop() }
        captures.hideApp = { [weak self] in self?.window.orderOut(nil); self?.closeShelf(restore: false) }
        captures.showResult = { [weak self] in self?.revealShelf() }
        captures.statusChanged = { [weak self] text in self?.recordingStatus(text) }
        annotations.onSaved = { [weak self] in self?.revealShelf() }
        history.openShelf = { [weak self] in self?.toggleShelf() }
        history.closeShelf = { [weak self] in self?.closeShelf() }
        history.showLibrary = { [weak self] in self?.showMain() }
        history.resizeShelf = { [weak self] in self?.resizeShelf() }
        history.paste = { [weak self] clips, plain in self?.paste(clips, plain: plain) }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self else { return event }; return self.key(event) }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.closeShelf(restore: false) } }
        if demoDirectory != nil { fillDemo() }
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { showMain() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool { showMain(); return true }
    func windowDidBecomeKey(_ notification: Notification) {
        // A click back into the library can bypass showMain(), for example after
        // a save panel closes. Present editors and previews in the visible host.
        if let active = notification.object as? NSWindow {
            if active === window { history.surface = "library" }
            else if active === shelf { history.surface = "shelf" }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if history.recording || history.captureBusy {
            let alert = NSAlert(); alert.messageText = history.recording ? "Un enregistrement est en cours." : "Une capture est en cours."
            alert.informativeText = "Termine la capture avant de quitter pour conserver ton contenu."
            alert.addButton(withTitle: history.recording ? "Arrêter et enregistrer" : "Revenir à la capture"); alert.addButton(withTitle: "Continuer")
            if alert.runModal() == .alertFirstButtonReturn, history.recording { captures.stop() }
            return .terminateCancel
        }
        if history.annotating { annotations.requestClose(); if history.annotating { return .terminateCancel } }
        history.stopMonitoring()
        // Flush queued atomic writes before exiting, without blocking the interface.
        Task { await history.flush(); if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }; NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func buildMenu() {
        let main = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu(); root.submenu = appMenu; main.addItem(root)
        appMenu.addItem(withTitle: "À propos d’EasyPaste", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "Réglages…", action: #selector(settings), keyEquivalent: ",")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quitter EasyPaste", action: #selector(quit), keyEquivalent: "q")
        for item in appMenu.items { item.target = self }
        let editRoot = NSMenuItem(title: "Édition", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Édition")
        for (title, action, key) in [("Annuler", Selector(("undo:")), "z"), ("Couper", #selector(NSText.cut(_:)), "x"), ("Copier", #selector(NSText.copy(_:)), "c"), ("Coller", #selector(NSText.paste(_:)), "v"), ("Tout sélectionner", #selector(NSText.selectAll(_:)), "a")] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        editRoot.submenu = editMenu; main.addItem(editRoot); NSApp.mainMenu = main
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "EasyPaste")
        let menu = NSMenu()
        menu.addItem(withTitle: "Barre rapide   ⇧⌘V", action: #selector(toggleShelf), keyEquivalent: "")
        menu.addItem(withTitle: "Ouvrir la bibliothèque…", action: #selector(showMain), keyEquivalent: "")
        let quickCapture = NSMenuItem(title: "Capturer une zone   ⌃⌥⌘C", action: #selector(captureFromMenu(_:)), keyEquivalent: "")
        quickCapture.tag = CaptureAction.area.rawValue; quickCapture.target = self
        quickCapture.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capturer une zone")
        menu.addItem(quickCapture)
        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        let captureMenu = NSMenu(title: "Capture")
        for action in CaptureAction.allCases {
            if action == .text || action == .video { captureMenu.addItem(.separator()) }
            let item = NSMenuItem(title: action.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            item.tag = action.rawValue; item.target = self; item.image = NSImage(systemSymbolName: action.icon, accessibilityDescription: action.title); captureMenu.addItem(item)
        }
        captureItem.submenu = captureMenu; menu.addItem(captureItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause / reprise de la collecte", action: #selector(toggleMonitoring), keyEquivalent: "")
        menu.addItem(withTitle: "Copier le prochain élément de la pile", action: #selector(copyNext), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Réglages…", action: #selector(settings), keyEquivalent: "")
        menu.addItem(withTitle: "Quitter EasyPaste", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }; status.menu = menu
    }
    private func rememberTarget() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { target = app }
    }
    @objc func showMain() { rememberTarget(); closeShelf(restore: false); history.surface = "library"; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func settings() { history.page = "settings"; showMain() }
    @objc func about() { let alert = NSAlert(); alert.messageText = "EasyPaste"; alert.informativeText = "Version 0.2.2\nTon historique, sur ton Mac.\nLogiciel libre sous licence MIT.\nmacOS 15 ou ultérieur."; alert.addButton(withTitle: "Fermer"); alert.runModal() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func toggleMonitoring() { guard !history.fault else { showMain(); return }; history.enabled.toggle() }
    @objc func copyNext() {
        Task { guard let id = history.stack.first, let clip = history.clips.first(where: { $0.id == id }) else { history.report("La pile est vide."); return }; if await history.copy([clip]) { history.consumeStack([clip]) } }
    }
    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let action = CaptureAction(rawValue: sender.tag) else { return }
        rememberTarget(); captures.run(action)
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(captureFromMenu(_:)) { return !history.captureBusy && !history.recording && !history.annotating && !history.loading && !history.fault }
        return true
    }
    private func revealShelf() {
        if shelf?.isVisible != true { toggleShelf() }
        else { history.surface = "shelf"; shelf?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    }
    private func recordingStatus(_ text: String?) {
        guard let text else {
            if let recordingStatus { NSStatusBar.system.removeStatusItem(recordingStatus) }
            recordingStatus = nil; return
        }
        if recordingStatus == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self; item.button?.action = #selector(stopVideo)
            item.button?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Arrêter l’enregistrement EasyPaste")
            item.button?.contentTintColor = .systemRed; item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            recordingStatus = item
        }
        recordingStatus?.button?.title = " " + text
        recordingStatus?.button?.toolTip = "Arrêter et conserver la vidéo dans EasyPaste"
    }
    @objc private func stopVideo() { captures.stop() }
    @objc func toggleShelf() {
        if shelf?.isVisible == true { closeShelf(); return }
        rememberTarget(); history.surface = "shelf"; history.collection = "all"; history.query = ""; history.filter = nil; history.sourceFilter = ""; history.todayOnly = false
        if shelf == nil {
            let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
            panel.isReleasedWhenClosed = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self
            panel.contentView = NSHostingView(rootView: ShelfView(history: history)); shelf = panel
        }
        resizeShelf(); shelf?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .init("EasyPaste.focusSearch"), object: nil)
    }
    private func resizeShelf() {
        guard let panel = shelf, let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame; let height: CGFloat = history.compact ? 290 : 375
        let width = min(frame.width - 28, 1680)
        panel.setFrame(NSRect(x: frame.midX - width/2, y: frame.minY + 12, width: width, height: height), display: true)
    }
    func closeShelf(restore: Bool = true) {
        guard shelf?.isVisible == true, shelf?.attachedSheet == nil else { return }
        shelf?.orderOut(nil)
        history.surface = "library"
        if restore { target?.activate(options: []) }
    }
    private func paste(_ clips: [Clip], plain: Bool) {
        guard !isPasting else { return }; isPasting = true
        let destination = target
        Task {
            defer { isPasting = false }
            guard await history.copy(clips, plain: plain) else { return }
            if history.collection == "stack" { history.consumeStack(clips) }
            closeShelf(restore: false)
            guard let destination, !destination.isTerminated, destination.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            guard destination.activate(options: []) else { return }
            guard AXIsProcessTrusted() else { history.report("Copié. Autorise le collage direct dans les réglages, ou utilise ⌘V."); return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
                  let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.postToPid(destination.processIdentifier); up.postToPid(destination.processIdentifier)
            history.report("Collé dans \(destination.localizedName ?? "l’application").")
        }
    }
    private func key(_ event: NSEvent) -> NSEvent? {
        guard window.isKeyWindow || shelf?.isKeyWindow == true else { return event }
        guard NSApp.keyWindow?.attachedSheet == nil, history.editing == nil, history.previewing == nil, !history.newSnippet, !history.showNewBoard else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        if event.keyCode == 53, shelf?.isVisible == true { closeShelf(); return nil }
        if cmd, event.charactersIgnoringModifiers == "f" { NotificationCenter.default.post(name: .init("EasyPaste.focusSearch"), object: nil); return nil }
        if cmd, event.charactersIgnoringModifiers == "n" { if flags.contains(.shift) { history.showNewBoard = true } else { history.newSnippet = true }; return nil }
        if cmd, event.charactersIgnoringModifiers == "e", let clip = history.selectedClip, clip.trashedAt == nil {
            if clip.kind == .image { annotations.open(clip); return nil }
            if clip.editable { history.editing = clip; return nil }
        }
        if cmd, event.charactersIgnoringModifiers == "y", let clip = history.selectedClip { history.previewing = clip; return nil }
        if cmd, event.charactersIgnoringModifiers == "o", let clip = history.selectedClip { openClip(clip); return nil }
        if cmd, event.charactersIgnoringModifiers == "t" { toggleMonitoring(); return nil }
        if !(NSApp.keyWindow?.firstResponder is NSTextView) {
            if event.keyCode == 51, history.collection != "trash", !history.selection.isEmpty { history.trashItems(history.selection); return nil }
            if cmd, event.charactersIgnoringModifiers == "z", !history.recentlyTrashed.isEmpty { history.undoTrash(); return nil }
        }
        guard shelf?.isKeyWindow == true else { return event }
        let physical: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        if cmd, let index = physical[event.keyCode], index < history.visible.count { paste([history.visible[index]], plain: flags.contains(.shift)); return nil }
        if event.keyCode == 123 || event.keyCode == 124 { history.moveSelection(event.keyCode == 123 ? -1 : 1); return nil }
        if event.keyCode == 36 { paste(history.selection, plain: flags.contains(.shift)); return nil }
        if event.keyCode == 49, !(NSApp.keyWindow?.firstResponder is NSTextView), let c = history.selectedClip { history.previewing = c; return nil }
        return event
    }
    private func registerHotkeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { switch id.id { case 0: delegate.toggleShelf(); case 1: delegate.copyNext(); case 2: delegate.rememberTarget(); delegate.captures.run(.area); case 3: delegate.rememberTarget(); delegate.captures.run(.text); default: break } }; return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let captureModifiers = UInt32(cmdKey | optionKey | controlKey)
        let bindings: [(Int, UInt32)] = [(kVK_ANSI_V, UInt32(cmdKey | shiftKey)), (kVK_ANSI_V, captureModifiers), (kVK_ANSI_C, captureModifiers), (kVK_ANSI_X, captureModifiers)]
        for (id, binding) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(binding.0), binding.1, EventHotKeyID(signature: 0x45504153, id: UInt32(id)), GetApplicationEventTarget(), 0, &ref) == noErr, let ref { hotkeys.append(ref) }
            else { history.report("Un raccourci est déjà utilisé. La barre rapide reste accessible depuis le menu EasyPaste.") }
        }
    }
    private func fillDemo() {
        let samples: [(String, String, String)] = [
            ("Pour les bonnes idées.", "Une pensée, un lien, trois mots qui tombent juste.\nGarde ce qui compte, retrouve-le quand tu en as besoin.", "Notes"),
            ("Un vert qui respire", "#8CEBC9", "Figma"),
            ("La suite commence ici", "https://developer.apple.com/design/", "Safari"),
            ("Réponse à garder", "Bonjour,\nMerci pour ton retour ! Je regarde les derniers détails et je reviens vers toi dans la journée.\nÀ très vite.", "Mail"),
            ("Moins chercher. Plus créer.", "Raccourcis utiles\n⇧⌘V  Ouvrir mes copies\nEntrée  Coller\n⌘E  Ajuster mon texte", "EasyPaste"),
            ("L’idée du vendredi", "Et si on gardait seulement l’essentiel ?\nUne interface calme. Les bons gestes. Un peu d’espace pour penser.", "Notes")]
        for (index, sample) in samples.enumerated() {
            let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(sample.1.utf8))]])
            var clip = Clip(title: sample.0, text: sample.1, source: sample.2, sourceID: "demo", kind: Clip.kind(for: sample.1), fingerprint: Clip.fingerprint(payload), payload: payload, pinned: index == 0)
            clip.date = Date().addingTimeInterval(-Double(index) * 720); history.add(clip)
        }
        let imagePayload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: DemoArtwork.png())]])
        var imageClip = Clip(title: "Prendre le large", text: "", source: "Aperçu", sourceID: "demo", kind: .image, fingerprint: Clip.fingerprint(imagePayload), payload: imagePayload)
        imageClip.date = Date().addingTimeInterval(-100); imageClip.prepareThumbnail(); history.add(imageClip)
        history.addBoard("Inspirations"); history.addBoard("Réponses utiles"); history.addBoard("Mon projet"); history.collection = "all"
        history.report("Aperçu de démonstration · données fictives, collecte désactivée.")
    }
}
final class ShelfPanel: NSPanel { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { false } }
