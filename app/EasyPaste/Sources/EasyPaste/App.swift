import AppKit
import SwiftUI
import Carbon
import ApplicationServices
import CryptoKit

@main struct EasyPasteMain {
    static func main() {
        if BrowserBridgeHost.runIfNeeded() { return }
        if AnnotationPreviewLauncher.runIfNeeded() { return }
        if CommandLine.arguments.contains("--render-svg") { SVGRenderer.runHelper(); return }
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
    private let shelfSizer = ShelfWindowSizer()
    private var status: NSStatusItem!
    private var statusMenu: NSMenu?
    private var target: NSRunningApplication?
    private var pasteRenameContext: PasteCompatibility.RenameContext?
    private lazy var destinations = PasteDestinationTracker()
    private let shortcutRegistry = GlobalShortcutRegistry()
    private var handler: EventHandlerRef?
    private var keys: Any?
    private var resignObserver: NSObjectProtocol?
    private var demoDirectory: URL?
    private var isPasting = false
    private lazy var captures = CaptureController(history: history)
    private lazy var annotations = AnnotationController(history: history)
    private lazy var previews = PreviewController(history: history)
    private lazy var colorSampler = ColorSamplerController(history: history)
    private lazy var bitwardenWindow = BitwardenWindowController(model: history.bitwarden)
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
        AppAppearance.stored().apply()
        target = destinations.capture()
        pasteRenameContext = PasteCompatibility.captureRename(destination: target)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1190, height: 850), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "EasyPaste"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.delegate = self
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false; window.backgroundColor = .clear; window.minSize = NSSize(width: 1050, height: 740)
        window.contentView = NSHostingView(rootView: MainView(history: history)); window.isReleasedWhenClosed = false
        window.center(); window.setFrameAutosaveName("EasyPasteLibrary")
        buildMenu(); registerHotkeys()
        history.updates.busy = { [weak self] in self?.history.updateBusy ?? true }
        if demoDirectory == nil || Bundle.main.object(forInfoDictionaryKey: "EasyPasteUpdateQA") as? Bool == true {
            history.updates.start()
        }
        history.bitwarden.attach(history: history)
        _ = bitwardenWindow
        history.bitwarden.visibilityChanged = { [weak self] in self?.refreshBitwardenMenu() }
        refreshBitwardenMenu()
        history.capture = { [weak self] action in self?.rememberTarget(); self?.captures.run(action) }
        history.annotate = { [weak self] clip in self?.annotations.open(clip) }
        history.previewChanged = { [weak self] clip in self?.previews.present(clip) }
        history.stopRecording = { [weak self] in self?.captures.stop() }
        captures.hideApp = { [weak self] in self?.window.orderOut(nil); self?.closeShelf(restore: false) }
        captures.originApplication = { [weak self] in self?.target }
        captures.showResult = { [weak self] in self?.revealShelf() }
        captures.statusChanged = { [weak self] text in self?.recordingStatus(text) }
        annotations.onSaved = { [weak self] in
            guard let self else { return }
            if self.history.surface == "library" { self.showMain() } else { self.revealShelf() }
        }
        history.openShelf = { [weak self] in self?.toggleShelf() }
        history.closeShelf = { [weak self] in self?.closeShelf() }
        history.showLibrary = { [weak self] in self?.showMain() }
        history.resizeShelf = { [weak self] in self?.resizeShelf() }
        history.paste = { [weak self] clips, plain in self?.paste(clips, plain: plain) }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self else { return event }; return self.key(event) }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.closeShelf(restore: false) } }
        if demoDirectory != nil { fillDemo() }
        let loginLaunch = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !loginLaunch { revealShelf() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if (history.captureBusy || history.recording), captures.revealActiveControls() { return false }
        revealShelf()
        // We handled reopening ourselves; AppKit must not restore the library.
        return false
    }
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
            if alert.runModal() == .alertFirstButtonReturn {
                if history.recording { captures.stop() } else { captures.revealActiveControls() }
            }
            return .terminateCancel
        }
        if history.annotating { annotations.requestClose(); if history.annotating { return .terminateCancel } }
        guard previews.requestClose() else { return .terminateCancel }
        history.stopMonitoring()
        // Flush queued atomic writes before exiting, without blocking the interface.
        Task { await history.bitwarden.shutdown(); await history.flush(); if let demoDirectory { try? FileManager.default.removeItem(at: demoDirectory) }; NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    private func buildMenu() {
        let main = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu(); root.submenu = appMenu; main.addItem(root)
        appMenu.addItem(withTitle: "À propos d’EasyPaste", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(withTitle: "Réglages…", action: #selector(settings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Rechercher des mises à jour…", action: #selector(checkUpdates), keyEquivalent: "")
        appMenu.addItem(withTitle: "Arrêter la vidéo", action: #selector(stopVideo), keyEquivalent: "")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle: "Quitter EasyPaste", action: #selector(quit), keyEquivalent: "q")
        for item in appMenu.items { item.target = self }
        let editRoot = NSMenuItem(title: "Édition", action: nil, keyEquivalent: ""); let editMenu = NSMenu(title: "Édition")
        for (title, action, key) in [("Annuler", Selector(("undo:")), "z"), ("Couper", #selector(NSText.cut(_:)), "x"), ("Copier", #selector(NSText.copy(_:)), "c"), ("Coller", #selector(NSText.paste(_:)), "v"), ("Tout sélectionner", #selector(NSText.selectAll(_:)), "a")] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        editRoot.submenu = editMenu; main.addItem(editRoot); NSApp.mainMenu = main
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "EasyPaste")
        status.button?.target = self
        status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "EasyPaste · Clic gauche : menu · Clic droit : barre rapide"
        let menu = NSMenu()
        menu.addItem(withTitle: "Barre rapide   ⇧⌘V", action: #selector(toggleShelf), keyEquivalent: "")
        menu.addItem(withTitle: "Ouvrir la bibliothèque…", action: #selector(showMain), keyEquivalent: "")
        let quickCapture = NSMenuItem(title: "Capturer une zone   ⌃⌥⌘C", action: #selector(captureFromMenu(_:)), keyEquivalent: "")
        quickCapture.tag = CaptureAction.area.rawValue; quickCapture.target = self
        quickCapture.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Capturer une zone")
        menu.addItem(quickCapture)
        let quickText = NSMenuItem(title: CaptureAction.text.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
        quickText.tag = CaptureAction.text.rawValue
        quickText.image = NSImage(systemSymbolName: CaptureAction.text.icon, accessibilityDescription: CaptureAction.text.title)
        menu.addItem(quickText)
        let colorItem = NSMenuItem(title: "Prélever une couleur…", action: #selector(sampleColor), keyEquivalent: "")
        colorItem.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Prélever une couleur")
        menu.addItem(colorItem)
        let captureItem = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        let captureMenu = NSMenu(title: "Capture")
        for action in CaptureAction.allCases {
            if action == .text || action == .video { captureMenu.addItem(.separator()) }
            let item = NSMenuItem(title: action.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            item.tag = action.rawValue; item.target = self; item.image = NSImage(systemSymbolName: action.icon, accessibilityDescription: action.title); captureMenu.addItem(item)
        }
        captureItem.submenu = captureMenu; menu.addItem(captureItem)
        menu.addItem(withTitle: "Arrêter la vidéo   ⌃⌥⌘S", action: #selector(stopVideo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause / reprise de la collecte", action: #selector(toggleMonitoring), keyEquivalent: "")
        menu.addItem(withTitle: "Copier le suivant dans la pile", action: #selector(copyNext), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "Réglages…", action: #selector(settings), keyEquivalent: "")
        menu.addItem(withTitle: "Rechercher des mises à jour…", action: #selector(checkUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Quitter EasyPaste", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }; statusMenu = menu
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Use the keyboard shortcut's path, including destination tracking
            // and search focus. Do not activate the library or open the menu.
            toggleShelf()
            return
        }
        guard let menu = statusMenu else { return }
        // A permanently attached menu consumes both mouse buttons before our
        // action runs. Attach it only while AppKit tracks the primary click.
        status.menu = menu
        defer { status.menu = nil }
        sender.performClick(nil)
    }
    private func rememberTarget() {
        // Keep the same destination while opening an editor from our shelf.
        if NSApp.isActive, shelf?.isVisible == true || window?.isVisible == true { return }
        target = destinations.capture()
        pasteRenameContext = PasteCompatibility.captureRename(destination: target)
    }
    private func refreshBitwardenMenu() {
        let tag = 8240
        for menu in [statusMenu, NSApp.mainMenu].compactMap({ $0 }) {
            if let old = menu.item(withTag: tag) { menu.removeItem(old) }
            guard history.bitwarden.enabled else { continue }
            let root = NSMenuItem(title: "Bitwarden", action: nil, keyEquivalent: ""); root.tag = tag
            root.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Bitwarden")
            let submenu = NSMenu(title: "Bitwarden")
            for (title, action) in [
                (history.bitwarden.publicOnly ? "Copier un lien" : "Créer un lien…", #selector(shareBitwarden)),
                ("Partager avec options…", #selector(shareBitwardenOptions)),
                ("Mes partages…", #selector(bitwardenSends)),
                ("Mon compte…", #selector(bitwardenAccount)),
                ("Verrouiller", #selector(lockBitwarden))
            ] {
                if action == #selector(shareBitwardenOptions) && !history.bitwarden.publicOnly { continue }
                let item = submenu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
            }
            root.submenu = submenu
            menu.insertItem(root, at: min(2, menu.items.count))
        }
    }
    @objc private func shareBitwarden() { guard history.selection.count == 1, let clip = history.selection.first else { return }; history.bitwarden.share(clip) }
    @objc private func shareBitwardenOptions() { guard history.selection.count == 1, let clip = history.selection.first else { return }; history.bitwarden.share(clip, forceOptions: true) }
    @objc private func bitwardenSends() { history.bitwarden.showSends() }
    @objc private func bitwardenAccount() { history.bitwarden.showAccount() }
    @objc private func lockBitwarden() { history.bitwarden.lock() }
    @objc func showMain() {
        if (history.captureBusy || history.recording), captures.revealActiveControls() { return }
        rememberTarget(); closeShelf(restore: false); history.surface = "library"; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func settings() { history.page = "settings"; showMain() }
    @objc func checkUpdates() {
        if history.updates.waitingToInstall { history.updates.installWhenReady() }
        else { history.updates.check() }
    }
    @objc func about() { let alert = NSAlert(); alert.messageText = "EasyPaste"; alert.informativeText = "Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Développement")\nLicence MIT\nmacOS 15 ou ultérieur"; alert.addButton(withTitle: "Fermer"); alert.runModal() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func toggleMonitoring() { guard !history.fault else { showMain(); return }; history.enabled.toggle() }
    @objc func copyNext() {
        Task { guard let id = history.stack.first, let clip = history.clips.first(where: { $0.id == id }) else { history.report("La pile est vide."); return }; if await history.copy([clip]) { history.consumeStack([clip]) } }
    }
    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let action = CaptureAction(rawValue: sender.tag) else { return }
        rememberTarget(); captures.run(action)
    }
    @objc private func sampleColor() {
        rememberTarget()
        colorSampler.beforeSampling = { [weak self] in self?.closeShelf(restore: false) }
        colorSampler.sample()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkUpdates) {
            menuItem.title = history.updates.waitingToInstall ? "Installer la mise à jour et relancer…" : "Rechercher des mises à jour…"
            return !history.updateBusy && (history.updates.canCheck || history.updates.waitingToInstall)
        }
        if menuItem.action == #selector(shareBitwarden) || menuItem.action == #selector(shareBitwardenOptions) { return history.bitwarden.canShare && history.selection.count == 1 && history.selection.first?.trashedAt == nil }
        if menuItem.action == #selector(bitwardenSends) || menuItem.action == #selector(bitwardenAccount) { return history.bitwarden.canShare }
        if menuItem.action == #selector(lockBitwarden) { return history.bitwarden.unlocked }
        if menuItem.action == #selector(stopVideo) { return history.recording }
        if menuItem.action == #selector(captureFromMenu(_:)) || menuItem.action == #selector(sampleColor) { return !history.captureBusy && !history.samplingColor && !history.recording && !history.annotating && !history.loading && !history.fault }
        return true
    }
    private func revealShelf() {
        if shelf?.isVisible != true { toggleShelf() }
        else {
            window.orderOut(nil); history.surface = "shelf"; shelf?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: SearchTextField.focusNotification, object: shelf)
        }
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
        recordingStatus?.button?.title = history.recording ? " Arrêter · " + text : " " + text
        recordingStatus?.button?.isEnabled = history.recording && !history.captureBusy
        recordingStatus?.button?.toolTip = "Arrêter et conserver la vidéo dans EasyPaste"
    }
    @objc private func stopVideo() { captures.stop() }
    @objc func toggleShelf() {
        if shelf?.isVisible == true { closeShelf(); return }
        // An unfinished editor belongs to its host window; leave it accessible.
        guard window.attachedSheet == nil else {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        rememberTarget()
        // Activating the app raises its visible windows. Hide the library first
        // so the user's destination application stays visible behind the shelf.
        window.orderOut(nil)
        history.prepareShelf()
        if shelf == nil {
            let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating
            panel.isReleasedWhenClosed = false; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.delegate = self
            panel.contentView = ShelfHosting.make(history: history); shelf = panel
        }
        resizeShelf(); shelf?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: SearchTextField.focusNotification, object: shelf)
    }
    private func resizeShelf() {
        guard let panel = shelf, let screen = (panel.isVisible ? panel.screen : nil) ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        if history.shelfScreenHeight != frame.height { history.shelfScreenHeight = frame.height }
        let layout = ShelfLayout(screenHeight: frame.height, compact: history.compact, expanded: history.shelfPreview != nil, footer: history.shelfNeedsFooter)
        let height = layout.height
        let width = min(frame.width - 28, 1680)
        let target = NSRect(x: frame.midX - width/2, y: frame.minY + 12, width: width, height: height)
        shelfSizer.resize(panel, to: target, deferShrink: panel.isVisible && history.shelfPreview == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    func closeShelf(restore: Bool = true) {
        guard shelf?.isVisible == true, shelf?.attachedSheet == nil else { return }
        shelfSizer.cancel()
        shelf?.orderOut(nil)
        history.shelfPreview = nil
        history.surface = "library"
        if restore { target?.activate(options: []) }
    }
    private func paste(_ clips: [Clip], plain: Bool) {
        guard !isPasting else { return }; isPasting = true
        let destination = target
        let renameContext = pasteRenameContext
        let fromStack = history.collection == "stack"
        Task {
            defer { isPasting = false }
            guard await history.copy(clips, plain: plain) else { return }
            guard AXIsProcessTrusted() else {
                let alert = NSAlert()
                alert.messageText = "Activer le collage direct"
                alert.informativeText = "Le contenu est copié. Autorise EasyPaste dans Accessibilité pour le coller directement dans tes applications."
                alert.addButton(withTitle: "Ouvrir les réglages")
                alert.addButton(withTitle: "Plus tard")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                return
            }
            guard let destination, !destination.isTerminated,
                  PasteDestinationPolicy.canActivate(own: ProcessInfo.processInfo.processIdentifier,
                    destination: destination.processIdentifier, frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
                history.report("Contenu copié. La destination a changé : utilise ⌘V dans l’application souhaitée.")
                return
            }
            closeShelf(restore: false)
            guard destination.activate(options: []) else { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier else { return }
            let compatibility = await PasteCompatibility.prepare(destination: destination, plain: plain, rename: renameContext)
            if compatibility == .unavailable {
                history.report("Contenu copié. Utilise le menu Coller du champ pour terminer.")
                return
            }
            if compatibility != .inserted {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == destination.processIdentifier,
                      let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
                      let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
                let flags: CGEventFlags = compatibility == .sheetsValues ? [.maskCommand, .maskShift] : .maskCommand
                down.flags = flags; up.flags = flags
                down.postToPid(destination.processIdentifier); up.postToPid(destination.processIdentifier)
            }
            history.recordPaste(clips, plain: plain)
            if fromStack { history.consumeStack(clips) }
            history.report(compatibility == .sheetsValues ? "Valeurs collées dans Google Sheets." : "Collé dans \(destination.localizedName ?? "l’application").")
        }
    }
    private func key(_ event: NSEvent) -> NSEvent? {
        if history.shortcuts.recording != nil { return event }
        if annotations.isKeyWindow { return annotations.key(event) }
        guard window.isKeyWindow || shelf?.isKeyWindow == true else { return event }
        guard NSApp.keyWindow?.attachedSheet == nil, history.editing == nil, history.previewing == nil, !history.newSnippet, !history.showNewBoard else { return event }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let cmd = flags.contains(.command)
        if event.keyCode == 53, shelf?.isVisible == true {
            if history.shelfPreview != nil { history.shelfPreview = nil } else { closeShelf() }
            return nil
        }
        if history.shortcuts[.search].matches(event) { NotificationCenter.default.post(name: SearchTextField.focusNotification, object: NSApp.keyWindow); return nil }
        if cmd, event.charactersIgnoringModifiers == "n" { if flags.contains(.shift) { history.showNewBoard = true } else { history.newSnippet = true }; return nil }
        if history.shortcuts[.edit].matches(event), let clip = history.selectedClip, clip.trashedAt == nil {
            if clip.kind == .image { annotations.open(clip); return nil }
            if clip.editable { history.editing = clip; return nil }
        }
        if history.shortcuts[.preview].matches(event), let clip = history.selectedClip { history.openPreview(clip); return nil }
        if cmd, event.charactersIgnoringModifiers == "o", let clip = history.selectedClip { openClip(clip); return nil }
        if cmd, event.charactersIgnoringModifiers == "t" { toggleMonitoring(); return nil }
        if !(NSApp.keyWindow?.firstResponder is NSTextView) {
            if cmd, event.charactersIgnoringModifiers == "c", !history.selection.isEmpty { Task { _ = await history.copy(history.selection) }; return nil }
            if event.keyCode == 49, let clip = history.selectedClip { history.openPreview(clip); return nil }
            if event.keyCode == 51, history.collection != "trash", !history.selection.isEmpty { history.requestTrash(history.selection); return nil }
            if cmd, event.charactersIgnoringModifiers == "z", !history.recentlyTrashed.isEmpty { history.undoTrash(); return nil }
        }
        guard shelf?.isKeyWindow == true else { return event }
        for (index, action) in ShortcutAction.cards.enumerated() where index < history.visible.count {
            let binding = history.shortcuts[action]
            if binding.matches(event) { paste([history.visible[index]], plain: false); return nil }
            if !binding.flags.contains(.shift), binding.shifted.matches(event) { paste([history.visible[index]], plain: true); return nil }
        }
        if history.shortcuts[.paste].matches(event) { paste(history.selection, plain: false); return nil }
        if history.shortcuts[.plainPaste].matches(event) { paste(history.selection, plain: true); return nil }
        if event.keyCode == 123 || event.keyCode == 124 { history.moveSelection(event.keyCode == 123 ? -1 : 1); return nil }
        if event.keyCode == 49, !(NSApp.keyWindow?.firstResponder is NSTextView), let c = history.selectedClip { history.openPreview(c); return nil }
        return event
    }
    private func registerHotkeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { guard delegate.history.shortcuts.recording == nil else { return }; switch id.id { case 0: delegate.toggleShelf(); case 1: delegate.copyNext(); case 2: delegate.rememberTarget(); delegate.captures.run(.area); case 3: delegate.rememberTarget(); delegate.captures.run(.text); case 4: delegate.captures.stop(); default: break } }; return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        history.shortcuts.apply = { [weak self] values in self?.shortcutRegistry.replace(values) }
        history.shortcuts.recordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.shortcutRegistry.suspend() }
            else if let issue = self.shortcutRegistry.start(self.history.shortcuts.bindings) { self.history.shortcuts.error = issue }
        }
        history.shortcuts.changed = { [weak self] in self?.refreshShortcutLabels() }
        if let issue = shortcutRegistry.start(history.shortcuts.bindings) { history.shortcuts.error = issue; history.report(issue) }
        refreshShortcutLabels()
    }
    private func refreshShortcutLabels() {
        func update(_ menu: NSMenu) {
            for item in menu.items {
                var action: ShortcutAction?
                if item.action == #selector(toggleShelf) { action = .shelf }
                if item.action == #selector(copyNext) { action = .stack }
                if item.action == #selector(stopVideo) { action = .stop }
                if item.action == #selector(captureFromMenu(_:)) {
                    if item.tag == CaptureAction.area.rawValue { action = .capture }
                    if item.tag == CaptureAction.text.rawValue { action = .ocr }
                }
                if let action { item.title = action.title + "   " + history.shortcuts[action].display }
                if let submenu = item.submenu { update(submenu) }
            }
        }
        if let menu = statusMenu { update(menu) }
        if let menu = NSApp.mainMenu { update(menu) }
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
final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    weak var wheelRoutingView: ShelfWheelRoutingView?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .scrollWheel, attachedSheet == nil,
           let scroll = wheelRoutingView?.enclosingScrollView,
           ShelfWheelRoutingView.route(event, in: scroll, at: event.locationInWindow) {
            return
        }
        super.sendEvent(event)
    }
}
