import AppKit
import ApplicationServices
import IOKit.pwr_mgt
import ServiceManagement

final class AwakeSession {
    private var assertions: [IOPMAssertionID] = []
    private(set) var deadline: Date?
    var active: Bool { !assertions.isEmpty }

    func start(minutes: Int) throws {
        stop()
        for kind in [kIOPMAssertionTypeNoDisplaySleep, kIOPMAssertionTypeNoIdleSleep] {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kind as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "EasyWake — session activée par l’utilisateur" as CFString, &id)
            guard result == kIOReturnSuccess else {
                stop()
                throw NSError(domain: "Eveil", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "macOS n’a pas pu activer le maintien en éveil (\(result))."])
            }
            assertions.append(id)
        }
        deadline = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil
    }

    func stop() {
        assertions.forEach { _ = IOPMAssertionRelease($0) }
        assertions.removeAll()
        deadline = nil
    }

    deinit { stop() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let session = AwakeSession()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var nextMovement = Date.distantFuture
    var sessionVisible = true
    let heading = NSTextField(labelWithString: "Votre Mac peut se reposer.")
    let detail = NSTextField(wrappingLabelWithString: "Activez EasyWake lorsque vous souhaitez garder votre écran allumé.")
    let stateLabel = NSTextField(labelWithString: "EN PAUSE")
    let remaining = NSTextField(labelWithString: "À votre rythme.")
    let permissions = NSTextField(wrappingLabelWithString: "")
    let toggleButton = NSButton(title: "Activer EasyWake", target: nil, action: nil)
    let duration = NSPopUpButton()
    let interval = NSPopUpButton()
    let mouse = NSButton(checkboxWithTitle: "Simuler un léger mouvement de souris", target: nil, action: nil)
    let startup = NSButton(checkboxWithTitle: "Lancer au démarrage", target: nil, action: nil)
    var menuToggle: NSMenuItem!
    var menuState: NSMenuItem!
    var menuRemaining: NSMenuItem!
    var menuMouse: NSMenuItem!
    var durationMenu: NSMenu!
    var intervalMenu: NSMenu!
    var startupItems: [NSMenuItem] = []
    var startupApprovalItems: [NSMenuItem] = []
    let durations = [0, 30, 60, 120, 240]
    let intervals = [15, 30, 60, 120]
    let durationTitles = ["Jusqu’à mon arrêt", "30 minutes", "1 heure", "2 heures", "4 heures"]
    let intervalTitles = ["15 secondes", "30 secondes", "60 secondes", "120 secondes"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        buildMenu()
        buildWindow()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionHidden), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionShown), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        refresh()
        refreshStartupStatus()
        showWindow()
    }

    func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "À propos d’EasyWake", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.delegate = self
        addStartupItems(to: appMenu)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quitter EasyWake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        main.addItem(item)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menuState = menu.addItem(withTitle: "EasyWake — en pause", action: nil, keyEquivalent: "")
        menuState.isEnabled = false
        menuRemaining = menu.addItem(withTitle: "", action: nil, keyEquivalent: "")
        menuRemaining.isEnabled = false
        menu.addItem(.separator())
        menuToggle = menu.addItem(withTitle: "Activer EasyWake", action: #selector(toggle), keyEquivalent: "")
        menuToggle.target = self
        durationMenu = NSMenu(title: "Durée de la session")
        durationMenu.autoenablesItems = false
        for (index, title) in durationTitles.enumerated() {
            let choice = durationMenu.addItem(withTitle: title, action: #selector(selectDuration(_:)), keyEquivalent: "")
            choice.tag = index
            choice.target = self
        }
        menu.addItem(withTitle: "Durée de la session", action: nil, keyEquivalent: "").submenu = durationMenu
        menu.addItem(.separator())
        menuMouse = menu.addItem(withTitle: "Simuler le mouvement de souris", action: #selector(toggleMouse), keyEquivalent: "")
        menuMouse.target = self
        intervalMenu = NSMenu(title: "Intervalle du mouvement")
        intervalMenu.autoenablesItems = false
        for (index, title) in intervalTitles.enumerated() {
            let choice = intervalMenu.addItem(withTitle: title, action: #selector(selectInterval(_:)), keyEquivalent: "")
            choice.tag = index
            choice.target = self
        }
        menu.addItem(withTitle: "Intervalle du mouvement", action: nil, keyEquivalent: "").submenu = intervalMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ouvrir la fenêtre…", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Réglages Accessibilité…", action: #selector(openAccessibility), keyEquivalent: "").target = self
        menu.addItem(.separator())
        addStartupItems(to: menu)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter EasyWake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 620), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "EasyWake"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let root = window.contentView!
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28)
        ])

        let brand = NSTextField(labelWithString: "☀  EASYWAKE")
        brand.font = .systemFont(ofSize: 16, weight: .bold)
        brand.textColor = .systemOrange
        stack.addArrangedSubview(brand)
        stateLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        stack.addArrangedSubview(stateLabel)
        heading.font = .systemFont(ofSize: 26, weight: .bold)
        heading.maximumNumberOfLines = 2
        heading.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(heading)
        detail.font = .systemFont(ofSize: 14)
        detail.textColor = .secondaryLabelColor
        detail.widthAnchor.constraint(equalToConstant: 416).isActive = true
        stack.addArrangedSubview(detail)

        duration.addItems(withTitles: durationTitles)
        duration.target = self
        duration.action = #selector(settingsChanged)
        interval.addItems(withTitles: intervalTitles)
        interval.target = self
        interval.action = #selector(settingsChanged)
        interval.selectItem(at: 1)
        stack.addArrangedSubview(row("Maintenir éveillé", control: duration))
        stack.addArrangedSubview(row("Bouger toutes les", control: interval))
        mouse.state = .on
        mouse.target = self
        mouse.action = #selector(mouseChanged)
        stack.addArrangedSubview(mouse)
        permissions.font = .systemFont(ofSize: 12)
        permissions.textColor = .secondaryLabelColor
        permissions.widthAnchor.constraint(equalToConstant: 416).isActive = true
        stack.addArrangedSubview(permissions)
        let access = NSButton(title: "Réglages Accessibilité…", target: self, action: #selector(openAccessibility))
        access.bezelStyle = .rounded
        stack.addArrangedSubview(access)
        startup.target = self
        startup.action = #selector(toggleStartup)
        startup.allowsMixedState = true
        stack.addArrangedSubview(startup)
        toggleButton.target = self
        toggleButton.action = #selector(toggle)
        toggleButton.bezelStyle = .rounded
        toggleButton.controlSize = .large
        toggleButton.keyEquivalent = "\r"
        toggleButton.contentTintColor = .systemOrange
        toggleButton.widthAnchor.constraint(equalToConstant: 416).isActive = true
        toggleButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        stack.addArrangedSubview(toggleButton)
        remaining.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        remaining.textColor = .secondaryLabelColor
        stack.addArrangedSubview(remaining)
        let footer = NSTextField(wrappingLabelWithString: "Fermer cette fenêtre masque l’icône du Dock. EasyWake reste accessible dans la barre de menus.")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor
        footer.widthAnchor.constraint(equalToConstant: 416).isActive = true
        stack.addArrangedSubview(footer)
    }

    func row(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let row = NSStackView(views: [label, NSView(), control])
        row.orientation = .horizontal
        row.widthAnchor.constraint(equalToConstant: 416).isActive = true
        control.widthAnchor.constraint(equalToConstant: 195).isActive = true
        return row
    }

    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    @objc func toggle() {
        if session.active {
            session.stop()
        } else {
            do {
                try session.start(minutes: durations[duration.indexOfSelectedItem])
                nextMovement = Date().addingTimeInterval(Double(intervals[interval.indexOfSelectedItem]))
                if mouse.state == .on && !AXIsProcessTrusted() {
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(options)
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        refresh()
    }

    func addStartupItems(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Lancer au démarrage", action: #selector(toggleStartup), keyEquivalent: "")
        item.target = self
        item.toolTip = "Ouvrir automatiquement l’application à la connexion à votre Mac."
        startupItems.append(item)
        let approval = menu.addItem(withTitle: "Autoriser dans les réglages de connexion…", action: #selector(openLoginSettings), keyEquivalent: "")
        approval.target = self
        approval.isHidden = true
        startupApprovalItems.append(approval)
    }

    func refreshStartupStatus() {
        let status = SMAppService.mainApp.status
        let state: NSControl.StateValue
        let description: String
        switch status {
        case .enabled:
            state = .on
            description = "activé"
        case .requiresApproval:
            state = .mixed
            description = "autorisation requise"
        case .notRegistered:
            state = .off
            description = "désactivé"
        case .notFound:
            state = .off
            description = "indisponible"
        @unknown default:
            state = .off
            description = "état inconnu"
        }
        for item in startupItems {
            item.state = state
            item.title = "Lancer au démarrage — \(description)"
        }
        startup.state = state
        startup.title = "Lancer au démarrage — \(description)"
        startupApprovalItems.forEach { $0.isHidden = status != .requiresApproval }
    }

    @objc func toggleStartup() {
        do {
            let service = SMAppService.mainApp
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notRegistered, .notFound:
                try service.register()
                if service.status == .requiresApproval { openLoginSettings() }
            @unknown default:
                throw NSError(domain: "Eveil", code: 1, userInfo: [NSLocalizedDescriptionKey: "L’état du lancement au démarrage n’est pas reconnu par cette version."])
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement au démarrage"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshStartupStatus()
    }

    @objc func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }

    func applicationDidBecomeActive(_ notification: Notification) { refreshStartupStatus() }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        refreshStartupStatus()
    }

    @objc func selectDuration(_ sender: NSMenuItem) {
        guard !session.active else { return }
        duration.selectItem(at: sender.tag)
        refresh()
    }

    @objc func selectInterval(_ sender: NSMenuItem) {
        interval.selectItem(at: sender.tag)
        settingsChanged()
    }

    @objc func settingsChanged() {
        nextMovement = Date().addingTimeInterval(Double(intervals[interval.indexOfSelectedItem]))
        refresh()
    }

    @objc func toggleMouse() {
        mouse.state = mouse.state == .on ? .off : .on
        mouseChanged()
    }

    @objc func mouseChanged() {
        if session.active && mouse.state == .on && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        settingsChanged()
    }
    @objc func sessionHidden() { sessionVisible = false }
    @objc func sessionShown() { sessionVisible = true }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func tick() {
        if session.active, let deadline = session.deadline, Date() >= deadline { session.stop() }
        if session.active && Date() >= nextMovement {
            nextMovement = Date().addingTimeInterval(Double(intervals[interval.indexOfSelectedItem]))
            if mouse.state == .on && sessionVisible && AXIsProcessTrusted() { moveMouse() }
        }
        refresh()
    }

    func moveMouse() {
        // Leave the pointer alone while the user is typing, moving it, or dragging.
        guard CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!) >= 5,
              !CGEventSource.buttonState(.combinedSessionState, button: .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .right),
              !CGEventSource.buttonState(.combinedSessionState, button: .center),
              let point = CGEvent(source: nil)?.location else { return }
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 else { return }
        let bounds = CGDisplayBounds(display)
        let shifted = CGPoint(x: point.x + (point.x + 1 < bounds.maxX ? 1 : -1), y: point.y)
        let source = CGEventSource(stateID: .hidSystemState)
        // An immediate one-pixel round trip avoids leaving the cursor displaced.
        for location in [shifted, point] {
            CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }

    func refresh() {
        let active = session.active
        stateLabel.stringValue = active ? "● MAINTIEN EN ÉVEIL ACTIF" : "○ EN PAUSE"
        stateLabel.textColor = active ? .systemGreen : .secondaryLabelColor
        heading.stringValue = active ? "Votre Mac reste éveillé." : "Votre Mac peut se reposer."
        detail.stringValue = active ? "L’écran reste allumé et la veille automatique est suspendue pendant votre session." : "Activez EasyWake lorsque vous souhaitez garder votre écran allumé."
        toggleButton.title = active ? "Arrêter EasyWake" : "Activer EasyWake"
        menuToggle.title = toggleButton.title
        duration.isEnabled = !active
        interval.isEnabled = mouse.state == .on
        if mouse.state == .off {
            permissions.stringValue = "Mouvement désactivé. Le maintien en éveil fonctionne sans autorisation supplémentaire."
        } else if AXIsProcessTrusted() {
            permissions.stringValue = "Souris : aller-retour de 1 pixel, uniquement après 5 secondes sans activité. Aucun clic simulé."
        } else {
            permissions.stringValue = "Autorisez EasyWake dans Accessibilité pour bouger la souris. Le maintien en éveil fonctionne déjà sans cette permission."
        }
        if active, let deadline = session.deadline {
            let seconds = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            remaining.stringValue = String(format: "Arrêt automatique dans %02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
        } else {
            remaining.stringValue = active ? "Actif jusqu’à votre arrêt." : "À votre rythme."
        }
        menuState.title = active ? "EasyWake — actif" : "EasyWake — en pause"
        menuRemaining.title = remaining.stringValue
        menuRemaining.isHidden = !active
        menuMouse.state = mouse.state
        for item in durationMenu.items {
            item.state = item.tag == duration.indexOfSelectedItem ? .on : .off
            item.isEnabled = !active
        }
        for item in intervalMenu.items {
            item.state = item.tag == interval.indexOfSelectedItem ? .on : .off
            item.isEnabled = mouse.state == .on
        }
        let icon = NSImage(systemSymbolName: active ? "sun.max.fill" : "sun.max", accessibilityDescription: active ? "EasyWake actif" : "EasyWake en pause")
        icon?.size = NSSize(width: 18, height: 18)
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.toolTip = active ? "EasyWake — actif" : "EasyWake — en pause"
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        session.stop()
    }
}

// Short integration check: acquire real assertions, verify state, then release.
if CommandLine.arguments.contains("--self-test") {
    let session = AwakeSession()
    do {
        try session.start(minutes: 1)
        precondition(session.active && session.deadline != nil)
        session.stop()
        precondition(!session.active && session.deadline == nil)
        try session.start(minutes: 0)
        precondition(session.active && session.deadline == nil)
        session.stop()
        print("PASS: timed and unlimited sessions acquire and release macOS sleep assertions.")
    } catch {
        fputs("FAIL: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.setActivationPolicy(.regular)
    app.delegate = delegate
    app.run()
}
