import AppKit
import ApplicationServices

struct ManagedWindow: Identifiable {
    let id: String
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    var name: String { app.localizedName ?? "Application" }
}
@MainActor
final class WindowEngine: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var windows: [ManagedWindow] = []
    @Published var selectedID: String?
    @Published var screens = NSScreen.screens
    @Published var screenIndex = 0
    @Published var message = "Choisis une zone pour y placer ta fenêtre."
    @Published var isError = false
    @Published var undoCount = 0
    @Published var isPlacing = false
    private var undoStack: [(ManagedWindow, CGRect)] = []
    private var previousApp: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    var selected: ManagedWindow? { windows.first { $0.id == selectedID } }
    var screen: NSScreen? { screens.indices.contains(screenIndex) ? screens[screenIndex] : screens.first }
    var primaryTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    init() {
        previousApp = NSWorkspace.shared.frontmostApplication
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier, app.activationPolicy == .regular else { return }
            Task { @MainActor in self?.previousApp = app; self?.refresh(preferFrontmost: true) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screens = NSScreen.screens; self?.screenIndex = 0 }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let current = AXIsProcessTrusted()
                if current != self.trusted { self.trusted = current; self.refresh(preferFrontmost: true) }
            }
        }
        refresh(preferFrontmost: true)
    }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }
    func refresh(preferFrontmost: Bool = false) {
        trusted = AXIsProcessTrusted()
        guard trusted else { windows = []; selectedID = nil; return }
        let old = selectedID
        var result: [ManagedWindow] = []
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success, let items = value as? [AXUIElement] else { continue }
            for win in items {
                guard string(win, kAXSubroleAttribute) == kAXStandardWindowSubrole, !bool(win, kAXMinimizedAttribute), frame(win) != nil else { continue }
                var sizeSettable = DarwinBoolean(false)
                AXUIElementIsAttributeSettable(win, kAXSizeAttribute as CFString, &sizeSettable)
                guard sizeSettable.boolValue else { continue }
                let title = string(win, kAXTitleAttribute) ?? "Sans titre"
                result.append(.init(id: "\(app.processIdentifier)-\(CFHash(win))", element: win, app: app, title: title.isEmpty ? "Sans titre" : title))
            }
        }
        windows = result.sorted { ($0.name, $0.title) < ($1.name, $1.title) }
        if preferFrontmost, let app = previousApp {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var focused: CFTypeRef?
            AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
            selectedID = windows.first { $0.app == app && focused != nil && CFEqual($0.element, focused!) }?.id ?? windows.first { $0.app == app }?.id ?? windows.first?.id
            followSelectedScreen()
        } else { selectedID = windows.contains { $0.id == old } ? old : windows.first?.id }
    }
    func window(at point: CGPoint) -> ManagedWindow? {
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&element) == .success else { return nil }
        for _ in 0..<12 {
            guard let current = element else { break }
            if let win = windows.first(where: { CFEqual($0.element,current) }) { return win }
            if string(current,kAXSubroleAttribute) == kAXStandardWindowSubrole, frame(current) != nil {
                var pid: pid_t = 0
                var settable = DarwinBoolean(false)
                AXUIElementGetPid(current,&pid)
                AXUIElementIsAttributeSettable(current,kAXSizeAttribute as CFString,&settable)
                if pid != ProcessInfo.processInfo.processIdentifier, settable.boolValue,
                   let app = NSRunningApplication(processIdentifier:pid), app.activationPolicy == .regular {
                    let win = ManagedWindow(id: "\(pid)-\(CFHash(current))",element:current,app:app,title:string(current,kAXTitleAttribute) ?? "Sans titre")
                    windows.append(win)
                    return win
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current,kAXParentAttribute as CFString,&parent) == .success, let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = (parent as! AXUIElement)
        }
        return nil
    }
    func followSelectedScreen() {
        guard let selected, let f = frame(selected.element) else { return }
        let center = CGPoint(x: f.midX, y: f.midY)
        if let index = screens.firstIndex(where: { TileGeometry.accessibilityRect($0.frame, primaryTop: primaryTop).contains(center) }) { screenIndex = index }
    }
    func report(_ text: String, error: Bool = false) { message = text; isError = error }
    func apply(_ zone: TileZone, gap: Double) {
        guard zone.isValid, let screen else { return }
        guard AXIsProcessTrusted() else { trusted = false; report("Autorise EasyTile dans Accessibilité pour déplacer les fenêtres.", error: true); return }
        guard let selected else { report("Aucune fenêtre redimensionnable. Ouvre une application, puis actualise la liste.", error: true); return }
        let visible = TileGeometry.accessibilityRect(screen.visibleFrame, primaryTop: primaryTop)
        move(selected, to: TileGeometry.frame(zone: zone, visible: visible, gap: gap), remember: true)
    }
    func move(_ win: ManagedWindow, to target: CGRect, remember: Bool) {
        guard !isPlacing else { return }
        guard !win.app.isTerminated, let original = frame(win.element) else { report("Cette fenêtre a été fermée. Actualise la liste.", error: true); refresh(); return }
        if bool(win.element, "AXFullScreen") { report("Quitte d’abord le plein écran macOS de cette fenêtre.", error: true); return }
        var position = target.origin; var size = target.size
        guard let posValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        let s1 = AXUIElementSetAttributeValue(win.element, kAXSizeAttribute as CFString, sizeValue)
        let p = AXUIElementSetAttributeValue(win.element, kAXPositionAttribute as CFString, posValue)
        let s2 = AXUIElementSetAttributeValue(win.element, kAXSizeAttribute as CFString, sizeValue)
        isPlacing = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            defer { isPlacing = false }
            guard let actual = frame(win.element) else { report("Impossible de lire la position de cette fenêtre.", error: true); return }
            let changed = abs(actual.minX-original.minX) > 1 || abs(actual.minY-original.minY) > 1 || abs(actual.width-original.width) > 1 || abs(actual.height-original.height) > 1
            if changed && remember { undoStack.append((win, original)); if undoStack.count > 30 { undoStack.removeFirst() }; undoCount = undoStack.count }
            if p != .success || (s1 != .success && s2 != .success) { report("\(win.name) n’a pas accepté tout le placement. Tu peux annuler.", error: true); return }
            let exact = abs(actual.minX-target.minX) < 4 && abs(actual.minY-target.minY) < 4 && abs(actual.width-target.width) < 4 && abs(actual.height-target.height) < 4
            report(exact ? "\(win.name) · fenêtre placée." : "\(win.name) impose une taille minimale ; placement adapté.")
        }
    }

    func undo() {
        guard !isPlacing else { return }
        guard AXIsProcessTrusted() else { requestAccess(); return }
        guard let (win, rect) = undoStack.popLast() else { return }
        undoCount = undoStack.count
        let available = screens.map { TileGeometry.accessibilityRect($0.visibleFrame, primaryTop: primaryTop) }
        var target = rect
        if !available.contains(where: { $0.intersects(rect) }), let f = available.first {
            target.size.width = min(target.width, f.width); target.size.height = min(target.height, f.height); target.origin = f.origin
        }
        move(win, to: target, remember: false)
    }
    func nextScreen() {
        guard !isPlacing else { return }
        guard screens.count > 1, let win = selected, let original = frame(win.element), let current = screen else { return }
        let old = TileGeometry.accessibilityRect(current.visibleFrame, primaryTop: primaryTop)
        screenIndex = (screenIndex+1) % screens.count
        guard let screen else { return }
        let next = TileGeometry.accessibilityRect(screen.visibleFrame, primaryTop: primaryTop)
        let w = min(original.width, next.width); let h = min(original.height, next.height)
        let x = next.minX + min(max((original.minX-old.minX)/max(old.width-original.width,1),0),1)*(next.width-w)
        let y = next.minY + min(max((original.minY-old.minY)/max(old.height-original.height,1),0),1)*(next.height-h)
        move(win, to: CGRect(x: x,y: y,width: w,height: h), remember: true)
    }
    private func string(_ el: AXUIElement, _ attr: String) -> String? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(el, attr as CFString, &v); return v as? String }
    private func bool(_ el: AXUIElement, _ attr: String) -> Bool { var v: CFTypeRef?; AXUIElementCopyAttributeValue(el, attr as CFString, &v); return (v as? Bool) ?? false }
    func frame(_ el: AXUIElement) -> CGRect? {
        var p: CFTypeRef?; var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success, AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success, let p, let s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
}
