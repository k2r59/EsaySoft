import AppKit
import SwiftUI
import Carbon

@main
struct EasyTileMain {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--verify-placement") {
            Task { @MainActor in await PlacementCheck.run(); app.terminate(nil) }
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let store = TileStore()
    let engine = WindowEngine()
    let updates = AppUpdates()
    let login = LoginLaunch()
    private var window: NSWindow!
    private var status: NSStatusItem!
    private var palette: PalettePanel?
    private var hotkeys: [EventHotKeyRef] = []
    private var keyboardHandler: EventHandlerRef?
    private var localKeyMonitor: Any?
    private var mouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var preview: NSPanel?
    private var dragCandidate: (TileZone, Int)?
    private var dragTracking: DragTracking?
    private var dragHover = DragHover()
    private var dragWindow: ManagedWindow?
    private var dragMenu: NSPanel?
    private let dragState = DragPaletteState()
    private var dragScreenIndex: Int?
    private var dragTimer: Timer?
    private var dragCancelled = false
    private var dragKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearance.stored().apply()
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1170,height:920),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "EasyTile"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Theme.bg); window.minSize = NSSize(width:1000,height:740)
        window.contentView = NSHostingView(rootView:MainView(store:store,engine:engine,updates:updates,login:login)); window.isReleasedWhenClosed = false
        window.center(); window.setFrameAutosaveName("EasyTileWorkspace")
        buildMenu()
        store.showPalette = { [weak self] in self?.togglePalette() }
        registerHotkeys(); setupMouse()
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, self.palette?.isVisible == true else { return event }
            if event.keyCode == 53 { self.closePalette(); return nil }
            let physicalNumbers: [UInt16:Int] = [18:1,19:2,20:3,21:4,23:5,22:6,26:7,28:8,25:9]
            let number = event.charactersIgnoringModifiers.flatMap(Int.init) ?? physicalNumbers[event.keyCode]
            if let n = number, n > 0, n <= self.store.layout.zones.count {
                self.engine.apply(self.store.layout.zones[n-1],gap:self.store.gap); self.closePalette(); return nil
            }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.closePalette(restoreFocus: false) } }
        updates.busy = { [weak self] in
            guard let self else { return false }
            return AppUpdates.isBusy(editor: self.store.showEditor, dragging: self.dragTracking != nil,
                                     placement: self.engine.isPlacing, palette: self.palette?.isVisible == true)
        }
        updates.start()
        if !LoginLaunch.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent) { showMain() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool) -> Bool { showMain(); return true }
    private func buildMenu() {
        let appMenu = NSMenu(); let main = NSMenu(); let root = NSMenuItem(); root.submenu = appMenu; main.addItem(root)
        appMenu.addItem(withTitle:"À propos d’EasyTile",action:#selector(showMain),keyEquivalent:"")
        appMenu.addItem(withTitle:"Préférences…",action:#selector(showPreferences),keyEquivalent:",")
        appMenu.addItem(withTitle:"Rechercher une mise à jour…",action:#selector(checkUpdates),keyEquivalent:"")
        appMenu.addItem(.separator()); appMenu.addItem(withTitle:"Quitter EasyTile",action:#selector(quit),keyEquivalent:"q")
        let edit = NSMenuItem(title:"Édition",action:nil,keyEquivalent:""); let editMenu = NSMenu(title:"Édition")
        for (title,selector,key) in [("Couper",#selector(NSText.cut(_:)),"x"),("Copier",#selector(NSText.copy(_:)),"c"),("Coller",#selector(NSText.paste(_:)),"v"),("Tout sélectionner",#selector(NSText.selectAll(_:)),"a")] { editMenu.addItem(withTitle:title,action:selector,keyEquivalent:key) }
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName:"rectangle.split.2x2",accessibilityDescription:"EasyTile")
        let menu = NSMenu()
        menu.addItem(withTitle:"Organiser mes fenêtres…",action:#selector(showMain),keyEquivalent:"")
        menu.addItem(withTitle:"Palette rapide   ⌃⌥espace",action:#selector(togglePalette),keyEquivalent:"")
        menu.addItem(withTitle:"Annuler le dernier placement",action:#selector(undo),keyEquivalent:"")
        menu.addItem(.separator())
        menu.addItem(withTitle:"Préférences…",action:#selector(showPreferences),keyEquivalent:",")
        menu.addItem(withTitle:"Rechercher une mise à jour…",action:#selector(checkUpdates),keyEquivalent:"")
        menu.addItem(.separator()); menu.addItem(withTitle:"Quitter EasyTile",action:#selector(quit),keyEquivalent:"")
        for item in menu.items { item.target = self }; status.menu = menu
    }
    @objc func showMain() { engine.refresh(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func showPreferences() { store.page = "settings"; showMain() }
    @objc func checkUpdates() {
        if updates.waitingToInstall { updates.installWhenReady() } else { updates.check() }
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkUpdates) {
            menuItem.title = updates.waitingToInstall ? "Installer la mise à jour et relancer…" : "Rechercher une mise à jour…"
            return (updates.canCheck || updates.waitingToInstall) && !updates.busy()
        }
        return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func undo() { engine.undo() }
    func closePalette(restoreFocus: Bool = true) {
        guard palette?.isVisible == true else { return }
        palette?.orderOut(nil)
        if restoreFocus, let target = engine.selected, !target.app.isTerminated {
            AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
            target.app.activate(options: [])
        }
    }
    @objc func togglePalette() {
        if palette?.isVisible == true { closePalette(); return }
        engine.refresh(preferFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier)
        if !engine.trusted { showMain(); engine.report("Autorise l’Accessibilité pour utiliser la palette.",error:true); return }
        let panel = PalettePanel(contentRect:NSRect(x:0,y:0,width:580,height:430),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .floating; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView:PaletteView(store:store,engine:engine,close:{ [weak self] in self?.closePalette() }))
        let s = engine.screen ?? NSScreen.main!
        panel.setFrameOrigin(CGPoint(x:s.visibleFrame.midX-290,y:s.visibleFrame.midY-215))
        palette = panel; panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    private func registerHotkeys() {
        let spec = EventTypeSpec(eventClass:OSType(kEventClassKeyboard),eventKind:UInt32(kEventHotKeyPressed))
        var eventSpec = spec
        InstallEventHandler(GetApplicationEventTarget(),{ _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID(); GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.handleHotkey(id.id) }
            return noErr
        },1,&eventSpec,Unmanaged.passUnretained(self).toOpaque(),&keyboardHandler)
        let codes:[UInt32] = [UInt32(kVK_Space),UInt32(kVK_LeftArrow),UInt32(kVK_RightArrow),UInt32(kVK_UpArrow),UInt32(kVK_DownArrow),UInt32(kVK_Delete)]
        var failed = false
        for (index,code) in codes.enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(code,UInt32(controlKey | optionKey),EventHotKeyID(signature:0x4554494C,id:UInt32(index)),GetApplicationEventTarget(),0,&ref)
            if result == noErr, let ref { hotkeys.append(ref) } else { failed = true }
        }
        if failed { engine.report("Un raccourci est déjà utilisé par une autre application. Libère ⌃⌥ espace ou les flèches.",error:true) }
    }
    private func handleHotkey(_ id: UInt32) {
        if id == 0 { togglePalette(); return }
        closePalette()
        if id == 5 { engine.undo(); return }
        engine.refresh(preferFrontmost:NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier)
        let z:TileZone
        switch id { case 1: z = .init(0,0,0.5,1,"Gauche"); case 2: z = .init(0.5,0,0.5,1,"Droite"); case 3: z = .init(0,0,1,1,"Agrandir"); default: z = .init(0.1,0.1,0.8,0.8,"Centrer") }
        engine.apply(z,gap:store.gap)
        if !engine.trusted { showMain() }
    }
    private func setupMouse() {
        screenObserver = NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.clearDrag(); self?.dragCancelled = true }
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] e in
            MainActor.assumeIsolated { self?.mouse(e) }
        }
        dragKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching:.keyDown) { [weak self] e in
            guard e.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.clearDrag(); self?.dragCancelled = true }
        }
    }
    private func clearDrag() {
        dragTimer?.invalidate(); dragTimer = nil
        preview?.orderOut(nil); dragMenu?.orderOut(nil)
        dragCandidate = nil; dragTracking = nil; dragHover = DragHover()
        dragWindow = nil; dragScreenIndex = nil; dragState.choice = nil
        engine.trackingDrag = false
    }
    private func mouse(_ e:NSEvent) {
        // WindowEngine already monitors authorization. Do not query TCC for
        // every pointer event while another app is running its tracking loop.
        guard store.dragEnabled, engine.trusted else { clearDrag(); return }
        if e.type == .leftMouseDown {
            clearDrag(); dragCancelled = false
            let p = NSEvent.mouseLocation
            let ax = CGPoint(x:p.x,y:engine.primaryTop-p.y)
            guard let w = engine.window(at:ax), let f = engine.frame(w.element) else { return }
            dragTracking = DragTracking(initialPointer:p, initialFrame:f); dragWindow = w
            engine.trackingDrag = true
            return
        }
        if e.type == .leftMouseUp {
            finishDrag(); return
        }
        guard !dragCancelled, dragTracking != nil, e.type == .leftMouseDragged else { return }
        if dragTimer == nil {
            // Events drive feedback immediately. This fallback handles a quiet
            // pointer and a release that the global monitor did not receive.
            let timer = Timer(timeInterval:0.04,repeats:true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard NSEvent.pressedMouseButtons & 1 != 0 else { self?.finishDrag(); return }
                    self?.updateDrag()
                }
            }
            RunLoop.main.add(timer,forMode:.common); dragTimer = timer
        }
        updateDrag()
    }
    private func finishDrag() {
        if dragTracking?.phase == .moving, !dragCancelled, let w = dragWindow {
            updateDrag()
            if let (zone,index) = dragCandidate, engine.windows.contains(where: { $0.id == w.id }) {
                engine.selectedID = w.id; engine.screenIndex = index; engine.apply(zone,gap:store.gap)
            }
        }
        // Both the mouse-up event and fallback timer can finish a drag. Clearing
        // it here ensures the second notification cannot place the window again.
        clearDrag()
    }
    private func updateDrag() {
        guard store.dragEnabled, !dragCancelled, engine.trusted, var tracking = dragTracking,
              let w = dragWindow, !w.app.isTerminated else { clearDrag(); return }
        let p = NSEvent.mouseLocation
        let phase = tracking.update(pointer:p) { engine.frame(w.element) }
        dragTracking = tracking
        switch phase {
        case .pending: return
        case .cancelled: clearDrag(); dragCancelled = true; return
        case .moving: break
        }
        guard dragHover.sample(p) else { return }
        guard let i = engine.screens.firstIndex(where: { $0.frame.contains(p) }) else {
            dragMenu?.orderOut(nil); preview?.orderOut(nil); dragCandidate = nil
            dragHover = DragHover(); dragState.choice = nil; return
        }
        if dragScreenIndex != i || dragMenu?.isVisible != true { showDragMenu(on:i) }
        guard let menu = dragMenu else { return }
        let local = CGPoint(x:p.x-menu.frame.minX,y:menu.frame.maxY-p.y)
        let choice = dragState.geometry.hit(local,layouts:dragState.layouts)
        guard dragHover.select(choice) else { return }
        dragState.choice = choice
        guard let choice else { dragCandidate = nil; preview?.orderOut(nil); return }
        let z = dragState.layouts[choice.layoutIndex].zones[choice.zoneIndex]
        dragCandidate = (z,i)
        showPreview(z,on:i)
    }
    private func showDragMenu(on index:Int) {
        let screen = engine.screens[index]
        dragState.layouts = store.layouts
        let columns = max(1,min(8,Int((screen.visibleFrame.width-64)/100)))
        let maxRows = max(1,Int((screen.visibleFrame.height-110)/95))
        let visibleCount = min(dragState.layouts.count,columns*maxRows)
        if let selected = dragState.layouts.firstIndex(where: { $0.id == store.selectedLayoutID }), selected >= visibleCount {
            let active = dragState.layouts.remove(at:selected)
            dragState.layouts.insert(active,at:0)
        }
        dragState.geometry = DragPaletteGeometry(columns:columns,count:visibleCount)
        dragState.choice = nil; dragHover = DragHover(); dragCandidate = nil; preview?.orderOut(nil)
        let size = dragState.geometry.size
        let panel = dragMenu ?? NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+2)
        panel.ignoresMouseEvents = true; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        if dragMenu == nil { panel.contentView = NSHostingView(rootView:DragPaletteView(state:dragState)) }
        panel.setFrame(CGRect(x:screen.visibleFrame.midX-size.width/2,y:screen.visibleFrame.maxY-size.height-14,width:size.width,height:size.height),display:true)
        dragMenu = panel; dragScreenIndex = index; panel.orderFrontRegardless()
    }
    private func showPreview(_ z:TileZone,on index:Int) {
        let s = engine.screens[index]
        let axFrame = TileGeometry.frame(zone:z,visible:TileGeometry.accessibilityRect(s.visibleFrame,primaryTop:engine.primaryTop),gap:store.gap)
        let cocoaFrame = CGRect(x:axFrame.minX,y:engine.primaryTop-axFrame.maxY,width:axFrame.width,height:axFrame.height)
        if preview == nil {
            let panel = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .floating; panel.ignoresMouseEvents = true; panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView:RoundedRectangle(cornerRadius:14).fill(Theme.mint.opacity(0.13)).overlay(RoundedRectangle(cornerRadius:14).strokeBorder(Theme.mint.opacity(0.85),lineWidth:3)).padding(2)); preview = panel
        }
        if preview?.frame != cocoaFrame { preview?.setFrame(cocoaFrame,display:true,animate:false) }
        if preview?.isVisible != true { preview?.orderFrontRegardless() }
    }

}
final class PalettePanel:NSPanel { override var canBecomeKey:Bool { true }; override var canBecomeMain:Bool { false } }
struct PaletteView:View {
    @ObservedObject var store:TileStore
    @ObservedObject var engine:WindowEngine
    let close:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:19) {
            HStack { Image(systemName:"rectangle.split.2x2.fill").foregroundStyle(Theme.mint); Text("Une place pour \(engine.selected?.name ?? "ta fenêtre")").font(.system(size:16,weight:.semibold)).lineLimit(1); Spacer(); Button(action:close) { KeyCap(text:"esc") }.buttonStyle(TilePlainButtonStyle()) }
            HStack { Text(store.layout.name).foregroundStyle(Theme.muted); Spacer(); Picker("Disposition",selection:$store.selectedLayoutID) { ForEach(store.layouts) { Text($0.name).tag($0.id) } }.labelsHidden().fixedSize() }.font(.system(size:12))
            MonitorView(layout:store.layout,enabled:engine.selected != nil,compact:true) { z in engine.apply(z,gap:store.gap); close() }.frame(maxWidth: .infinity)
            Text(engine.selected == nil ? "Aucune fenêtre disponible. Ouvre une fenêtre puis réessaie." : "Clique sur une zone, ou appuie sur son numéro.").font(.system(size:11)).foregroundStyle(Theme.muted)
        }.padding(26).frame(width:580,height:430).background(Theme.panel,in:RoundedRectangle(cornerRadius:23)).overlay(RoundedRectangle(cornerRadius:23).strokeBorder(Theme.ink.opacity(0.14))).foregroundStyle(Theme.ink)
    }
}
