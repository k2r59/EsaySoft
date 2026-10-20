import AppKit
import Vision
import Carbon
import SwiftUI
import ScreenCaptureKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var openedFilesAtLaunch=false
    var status: NSStatusItem!
    var home: HomeController?
    var windows: [NSWindow] = []
    var editors: [EditorController] = []
    var permissionNoticeOpen = false
    var busy = false
    private var ocrInProgress=0
    var lastRect: CGRect?
    var selectors: [NSWindow] = []
    let recorder = Recorder()
    let updates = AppUpdates()
    let sounds = SoundFeedback()
    var updateBusy: Bool {
        busy || ocrInProgress>0 || !selectors.isEmpty || recorder.isBusy ||
        scrolling?.session.isActive == true || !editors.isEmpty ||
        videoEditors.contains { $0.model.exporting || $0.model.hasUnexportedChanges }
    }
    nonisolated let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("EasyShoot/Captures")
    var hotkey: EventHotKeyRef?
    var ocrHotkey: EventHotKeyRef?
    var toastPanel: NSPanel?
    var quickCapture: QuickCaptureController?
    var scrolling: ScrollingController?
    var videoEditors:[VideoEditorController]=[]
    func windowWillClose(_ notification:Notification) {
        guard let window=notification.object as? NSWindow else{return}
        window.contentView=nil
        windows.removeAll { $0 === window }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        try? FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--mcp") { return }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "EasyShoot")
        sounds.muted = { [weak self] in self?.recorder.isBusy == true }
        if !CommandLine.arguments.contains("--demo") {
            updates.busy = { [weak self] in self?.updateBusy == true }
            updates.start()
        }
        setupMenu()
        installHotkey()
        if let index=CommandLine.arguments.firstIndex(of:"--preview"),index+1 < CommandLine.arguments.count { showQuickCapture(URL(fileURLWithPath:CommandLine.arguments[index+1])) }
        else if CommandLine.arguments.contains("--demo"), let image = demoImage() { showEditor(image) }
        else if !openedFilesAtLaunch { showHome() }
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {
        showHome()
        return true
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        if busy || ocrInProgress>0 || !selectors.isEmpty {
            message("Capture en cours","Termine la capture avant de quitter EasyShoot.");return .terminateCancel
        }
        if recorder.isBusy || videoEditors.contains(where:{$0.model.exporting}) {
            message("Opération en cours","Termine l’enregistrement ou l’export avant de quitter EasyShoot.");return .terminateCancel
        }
        if scrolling?.session.isActive == true || editors.contains(where:{!$0.canvas.marks.isEmpty}) {
            message("Modifications en cours","Termine la capture défilante ou ferme l’éditeur d’annotations avant de quitter EasyShoot.");return .terminateCancel
        }
        if videoEditors.contains(where:{$0.model.hasUnexportedChanges}) {
            let alert=NSAlert();alert.messageText="Quitter sans exporter le montage ?";alert.informativeText="Les vidéos originales sont conservées. Les modifications non exportées seront perdues.";alert.addButton(withTitle:"Continuer le montage");alert.addButton(withTitle:"Quitter")
            if alert.runModal() != .alertSecondButtonReturn {return .terminateCancel}
        }
        scrolling?.session.cancel()
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
    func applicationSupportsSecureRestorableState(_ app:NSApplication)->Bool { true }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        openedFilesAtLaunch=true
        for path in filenames { let url=URL(fileURLWithPath:path);if ["mp4","mov","m4v"].contains(url.pathExtension.lowercased()) {showVideoEditor(url)} else if let image=NSImage(contentsOfFile:path) { showEditor(image) } }
        sender.reply(toOpenOrPrint:.success)
    }
    func item(_ title: String, _ action: Selector, _ symbol: String, _ key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self; i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil); return i
    }
    func setupMenu() {
        let m = NSMenu()
        let heading = NSMenuItem(title: "EasyShoot", action: nil, keyEquivalent: ""); m.addItem(heading)
        m.addItem(item("Ouvrir EasyShoot", #selector(showHome), "square.grid.2x2"))
        m.addItem(.separator())
        m.addItem(item("Capturer une zone", #selector(area), "viewfinder", "2"))
        m.addItem(item("Reprendre la dernière zone", #selector(previous), "arrow.counterclockwise"))
        m.addItem(item("Capturer l’écran", #selector(fullscreen), "display", "3"))
        m.addItem(item("Capturer une fenêtre", #selector(window), "macwindow", "4"))
        m.addItem(item("Capture défilante…", #selector(scrollingCapture), "rectangle.expand.vertical"))
        m.addItem(item("Retardateur · 5 secondes", #selector(timer), "timer"))
        m.addItem(item("Extraire le texte (OCR)", #selector(ocr), "text.viewfinder", "5"))
        m.addItem(.separator())
        m.addItem(item(recorder.isRecording ? "Arrêter l’enregistrement" : "Enregistrer l’écran…", #selector(record), recorder.isRecording ? "stop.circle.fill" : "record.circle"))
        m.addItem(.separator())
        m.addItem(item("Ouvrir une image…", #selector(openImage), "folder", "o"))
        m.addItem(item("Monter une vidéo…", #selector(openVideo), "film.stack"))
        m.addItem(item("Image du presse-papiers", #selector(pasteImage), "clipboard", "v"))
        m.addItem(item("Historique des captures", #selector(history), "clock.arrow.circlepath", "h"))
        m.addItem(.separator())
        m.addItem(item("Réglages et autorisations…", #selector(settings), "gearshape", ","))
        m.addItem(item("Rechercher des mises à jour…", #selector(checkUpdates), "arrow.triangle.2.circlepath"))
        m.addItem(item("À propos d’EasyShoot", #selector(about), "info.circle"))
        m.addItem(item("Relancer EasyShoot", #selector(relaunch), "arrow.clockwise"))
        m.addItem(item("Quitter", #selector(quit), "power", "q"))
        status.menu = m
    }
    func fail(_ error: Error) { message("EasyShoot", error.localizedDescription) }
    func message(_ title: String, _ text: String) { NSApp.activate(ignoringOtherApps: true); let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal() }
    @objc func area() { guard !busy, ensureCaptureAccess() else { return }; selectArea { [weak self] rect in self?.lastRect = rect; self?.capture(["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"]) } }
    @objc func previous() { guard let r = lastRect else { area(); return }; capture(["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"]) }
    @objc func fullscreen() { capture(["-m"]) }
    @objc func window() {
        guard !busy,ensureCaptureAccess() else {return}
        busy=true
        Task { @MainActor in
            defer {busy=false}
            do {
                let content=try await NativeScreenCapture.content()
                let choices=content.windows.filter{$0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width>50 && $0.frame.height>50}
                guard !choices.isEmpty else {message("Aucune fenêtre disponible","Ouvre une fenêtre puis réessaie.");return}
                let picker=NSPopUpButton(frame:NSRect(x:0,y:0,width:460,height:28))
                for w in choices {picker.addItem(withTitle:"\(w.owningApplication?.applicationName ?? "Application") · \(w.title ?? "Sans titre")")}
                let alert=NSAlert();alert.messageText="Capturer une fenêtre";alert.informativeText="Choisis la fenêtre à capturer.";alert.accessoryView=picker;alert.addButton(withTitle:"Capturer");alert.addButton(withTitle:"Annuler")
                NSApp.activate(ignoringOtherApps:true)
                guard alert.runModal() == .alertFirstButtonReturn,choices.indices.contains(picker.indexOfSelectedItem) else{return}
                let image=try await NativeScreenCapture.window(choices[picker.indexOfSelectedItem])
                let url=store.appendingPathComponent("Capture-\(UUID().uuidString).png")
                try await NativeScreenCapture.savePNG(image,to:url);sounds.play(.capture);showQuickCapture(url)
            } catch {fail(error)}
        }
    }
    @objc func timer() { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.area() } }
    @objc func ocr() { guard !busy, ensureCaptureAccess() else { return }; selectArea(instruction:"Sélectionne le texte à copier · Échap pour annuler") { [weak self] r in self?.capture(["-R", "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"], recognize: true) } }
    func ensureCaptureAccess() -> Bool {
        guard !CGPreflightScreenCaptureAccess() else {return true}
        guard !permissionNoticeOpen else {return false}
        permissionNoticeOpen=true
        defer {permissionNoticeOpen=false}
        let alert=NSAlert();alert.messageText="Autoriser la capture d’écran"
        alert.informativeText="Active EasyShoot dans Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Utilise la copie du dossier Applications. Après activation, si macOS te demande de quitter l’app, rouvre EasyShoot depuis Applications."
        alert.addButton(withTitle:"Ouvrir les réglages");alert.addButton(withTitle:"Annuler")
        NSApp.activate(ignoringOtherApps:true)
        if alert.runModal() == .alertFirstButtonReturn {openScreenPermissions()}
        return false
    }
    @objc func openScreenPermissions() {
        // Request once, only on an explicit user action. Never from refresh or capture polling.
        if !CGPreflightScreenCaptureAccess(),!UserDefaults.standard.bool(forKey:"screenPermissionRequested") {
            UserDefaults.standard.set(true,forKey:"screenPermissionRequested")
            _ = CGRequestScreenCaptureAccess()
        }
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    func capture(_ arguments: [String], recognize: Bool = false) {
        guard !busy,ensureCaptureAccess() else { return };busy=true
        Task { @MainActor in
            defer {busy=false}
            do {
                var rect:CGRect?
                if let i=arguments.firstIndex(of:"-R"),i+1<arguments.count {
                    let n=arguments[i+1].split(separator:",").compactMap{Double($0)}
                    guard n.count==4 else{return};rect=CGRect(x:n[0],y:n[1],width:n[2],height:n[3])
                }
                try await Task.sleep(for:.milliseconds(250))
                let image=try await NativeScreenCapture.region(rect)
                let url=store.appendingPathComponent("Capture-\(UUID().uuidString).png")
                try await NativeScreenCapture.savePNG(image,to:url)
                if recognize {self.recognize(image,quietly:true)} else {sounds.play(.capture);showQuickCapture(url)}
            } catch {fail(error)}
        }
    }
    func selectArea(instruction:String = "Glisse pour sélectionner · Échap pour annuler", _ completion: @escaping (CGRect) -> Void) {
        guard selectors.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = SelectionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            w.level = .screenSaver; w.backgroundColor = .clear; w.isOpaque = false; w.hasShadow = false
            let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.instruction=instruction
            v.done = { [weak self] rect in
                guard let self else { return }
                self.selectors.forEach { $0.orderOut(nil) }; self.selectors.removeAll()
                guard let rect else { return }
                let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
                completion(CGRect(x: screen.frame.minX + rect.minX, y: primaryTop - (screen.frame.minY + rect.maxY), width: rect.width, height: rect.height))
            }
            w.contentView = v; selectors.append(w); w.makeKeyAndOrderFront(nil); w.makeFirstResponder(v)
        }
    }
    @objc func scrollingCapture() {
        guard ensureCaptureAccess() else{return}
        if let existing=scrolling,!existing.session.finishing,existing.window?.isVisible == true { existing.window?.orderFrontRegardless();return }
        guard !busy,!recorder.isRecording else {message("Capture en cours","Termine la capture ou l’enregistrement avant de démarrer une capture défilante.");return}
        home?.window?.orderOut(nil);quickCapture?.window?.orderOut(nil)
        selectArea(instruction:"Sélectionne le contenu à faire défiler · évite les en-têtes fixes") { [weak self] rect in
            guard let self else{return}
            guard rect.width>=100,rect.height>=120 else{message("Zone trop petite","Sélectionne une zone d’au moins 100 × 120 points.");return}
            Task { @MainActor in
                let controller=ScrollingController(rect:rect,owner:self);self.scrolling=controller;controller.showWindow(nil);controller.session.begin()
            }
        }
    }
    func showVideoEditor(_ url:URL) {
        if let existing=videoEditors.first(where:{$0.model.url.standardizedFileURL == url.standardizedFileURL && $0.window?.isVisible == true}) {existing.showWindow(nil);NSApp.activate(ignoringOtherApps:true);return}
        let controller=VideoEditorController(url:url,owner:self);videoEditors.append(controller);controller.showWindow(nil);NSApp.activate(ignoringOtherApps:true)
    }
    @objc func openVideo() {
        NSApp.activate(ignoringOtherApps:true);let panel=NSOpenPanel();panel.allowedContentTypes=[.movie,.mpeg4Movie];panel.message="Choisis une vidéo à monter. L’original restera intact."
        if panel.runModal() == .OK,let url=panel.url {showVideoEditor(url)}
    }
    func recognize(_ image: NSImage, quietly:Bool = false) {
        guard let pixels = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { return }
        recognize(pixels,quietly:quietly)
    }
    func recognize(_ image: CGImage, quietly:Bool = false) {
        ocrInProgress+=1
        DispatchQueue.global(qos: .userInitiated).async {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["fr-FR", "en-US"]; request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage:image).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                DispatchQueue.main.async {
                    self.ocrInProgress-=1
                    if text.isEmpty { self.showToast("Aucun texte détecté",detail:"Sélectionne une zone contenant du texte lisible.",success:false) }
                    else { NSPasteboard.general.clearContents(); if NSPasteboard.general.setString(text, forType: .string) { self.sounds.play(quietly ? .capture : .copy) }; if quietly { self.showToast("Texte copié",detail:"\(text.count) caractères · Prêt à coller avec ⌘V") } else { self.message("Texte copié", text) } }
                }
            } catch { DispatchQueue.main.async { self.ocrInProgress-=1;self.fail(error) } }
        }
    }
    func showQuickCapture(_ url:URL) {
        quickCapture?.dispose()
        let controller=QuickCaptureController(url:url,owner:self)
        quickCapture=controller;controller.window?.orderFrontRegardless()
        NotificationCenter.default.post(name:Notification.Name("EasyShootCapturesChanged"),object:nil)
    }
    func showEditor(_ image: NSImage) {
        let controller = EditorController(image: image, owner: self)
        editors.append(controller)
        controller.window?.isReleasedWhenClosed = false
        controller.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func openImage() { NSApp.activate(ignoringOtherApps: true); let p = NSOpenPanel(); p.allowedContentTypes = [.image]; if p.runModal() == .OK, let u = p.url, let im = NSImage(contentsOf: u) { showEditor(im) } }
    @objc func pasteImage() { guard let im = NSImage(pasteboard: .general) else { message("Presse-papiers vide", "Copie une image pour l’ouvrir ici."); return }; showEditor(im) }
    @objc func history() {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel(); p.directoryURL = store; p.allowedContentTypes = [.image, .movie]; p.message = "Historique local · choisis une capture à ouvrir"
        if p.runModal() == .OK, let u = p.url { if let im = NSImage(contentsOf: u) { showEditor(im) } else { showVideoEditor(u) } }
    }
    @objc func record() {
        if recorder.isRecording { Task { do { try await recorder.stop(); setupMenu() } catch { fail(error) } }; return }
        guard !recorder.isBusy else {message("Enregistrement en cours","Attends la fin de la préparation ou de l’enregistrement.");return}
        if scrolling?.window?.isVisible == true {message("Capture défilante en cours","Termine la capture défilante avant de démarrer un enregistrement.");return}
        guard ensureCaptureAccess() else{return}
        let a = NSAlert(); a.messageText = "Enregistrer l’écran principal"; a.informativeText = "Vidéo MP4 à 30 images/s avec le son système. Utilise le menu EasyShoot pour arrêter."; a.addButton(withTitle: "Enregistrer"); a.addButton(withTitle: "Annuler")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let url = store.appendingPathComponent("Enregistrement-\(UUID().uuidString).mp4")
        Task { [self] in do { try await recorder.start(url: url,completed: { [weak self] file in self?.showQuickCapture(file) }) { [weak self] in self?.setupMenu() }; setupMenu() } catch { fail(error) } }
    }
    @objc func checkUpdates() { updates.check() }
    @objc func settings() {
        showHome()
        home?.navigation.page=2
    }
    @objc func showHome() { if home == nil { home=HomeController(owner:self) };home?.showWindow(nil);NSApp.activate(ignoringOtherApps:true) }
    func showWelcome() { UserDefaults.standard.set(true, forKey: "welcomed"); message("Bienvenue dans EasyShoot", "Retrouve EasyShoot dans la barre de menus, avec l’icône de viseur.\n\nCapture une zone avec ⌃⌥⌘2. Annote, copie, exporte ou épingle l’image. OCR et historique fonctionnent localement.\n\nmacOS demandera l’autorisation d’enregistrer l’écran lors de la première capture.") }
    @objc func about() { message("EasyShoot · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", "Application macOS locale de capture et d’annotation.\n\nPrototype : captures, OCR, annotations, épinglage, historique et vidéo MP4.\n\nCapture défilante verticale et montage vidéo : coupes, segments, vitesse, cadrage et audio. Les GIF et la caméra ne sont pas encore intégrés.") }
    @objc func relaunch() {
        if recorder.isRecording { message("Enregistrement en cours","Arrête l’enregistrement avant de relancer EasyShoot.");return }
        if videoEditors.contains(where:{$0.model.exporting}) {message("Export en cours","Attends la fin de l’export vidéo avant de relancer.");return}
        if videoEditors.contains(where:{$0.model.hasUnexportedChanges}) {message("Montage non exporté","Exporte ton montage ou ferme son éditeur avant de relancer EasyShoot.");return}
        if editors.contains(where:{!$0.canvas.marks.isEmpty}) {
            let alert=NSAlert();alert.messageText="Relancer EasyShoot ?";alert.informativeText="Les annotations non exportées seront perdues. Exporte tes images avant de relancer.";alert.addButton(withTitle:"Annuler");alert.addButton(withTitle:"Relancer")
            guard alert.runModal() == .alertSecondButtonReturn else{return}
        }
        let task=Process();task.executableURL=URL(fileURLWithPath:"/bin/sh")
        task.arguments=["-c","sleep 1; /usr/bin/open -a \"$1\" --args --reopened","easyshoot-relaunch",Bundle.main.bundleURL.path]
        do { try task.run();NSApp.terminate(nil) } catch { fail(error) }
    }
    @objc func quit() { if scrolling?.session.finishing == true {message("Assemblage en cours","Attends la fin de l’enregistrement du PNG avant de quitter.");return}; if videoEditors.contains(where:{$0.model.exporting}) {message("Export en cours","Annule l’export ou attends sa fin avant de quitter.");return};scrolling?.session.cancel(); if recorder.isRecording { message("Enregistrement en cours", "Arrête l’enregistrement avant de quitter."); return }; NSApp.terminate(nil) }
    func installHotkey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ptr in
            guard let ptr,let event else { return noErr }
            var id=EventHotKeyID()
            GetEventParameter(event,EventParamName(kEventParamDirectObject),EventParamType(typeEventHotKeyID),nil,MemoryLayout<EventHotKeyID>.size,nil,&id)
            let owner=Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            let isOCR=id.id == 2
            DispatchQueue.main.async { if isOCR { owner.ocr() } else { owner.area() } }
            return noErr
        },1,&spec,Unmanaged.passUnretained(self).toOpaque(),nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_2),UInt32(controlKey | optionKey | cmdKey),EventHotKeyID(signature:0x45534854,id:1),GetApplicationEventTarget(),0,&hotkey)
        RegisterEventHotKey(UInt32(kVK_ANSI_T),UInt32(controlKey | optionKey | cmdKey),EventHotKeyID(signature:0x45534854,id:2),GetApplicationEventTarget(),0,&ocrHotkey)
    }
    func copyMCPConfiguration() {
        let executable=Bundle.main.executableURL?.path ?? "/Applications/EasyShoot.app/Contents/MacOS/EasyShoot"
        let config:[String:Any]=["mcpServers":["easyshoot":["command":executable,"args":["--mcp"]]]]
        guard let data=try? JSONSerialization.data(withJSONObject:config,options:[.prettyPrinted,.sortedKeys]),let text=String(data:data,encoding:.utf8) else{return}
        NSPasteboard.general.clearContents();if NSPasteboard.general.setString(text,forType:.string) {sounds.play(.copy)}
        showToast("Configuration MCP copiée",detail:"Connexion locale · aucun serveur à héberger")
    }
    func showToast(_ title:String,detail:String,success:Bool=true) {
        toastPanel?.orderOut(nil)
        guard let screen=NSScreen.main else{return}
        let rect=NSRect(x:screen.visibleFrame.maxX-390,y:screen.visibleFrame.maxY-116,width:365,height:88)
        let panel=NSPanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.level = .floating;panel.hasShadow=true;panel.isReleasedWhenClosed=false
        panel.contentView=NSHostingView(rootView:CaptureToast(title:title,detail:detail,success:success).preferredColorScheme(.dark))
        toastPanel=panel;panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self,weak panel] in panel?.orderOut(nil);if self?.toastPanel === panel { self?.toastPanel=nil } }
    }
    func demoImage() -> NSImage? {
        let image = NSImage(size: NSSize(width: 1000, height: 640)); image.lockFocus()
        NSColor(calibratedRed: 0.06, green: 0.09, blue: 0.15, alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 1000,height: 640).fill()
        let texts: [(String, CGFloat, CGFloat)] = [("EasyShoot", 64, 470), ("Capture. Annote. Partage.", 36, 390), ("Ton écran, tes idées. Tout reste sur ton Mac.", 22, 320), ("01   Capture une zone", 24, 220), ("02   Ajoute une flèche ou du texte", 24, 165), ("03   Copie ou exporte ton image", 24, 110)]
        for (s,size,y) in texts { (s as NSString).draw(at: NSPoint(x: 70,y:y), withAttributes: [.font:NSFont.systemFont(ofSize:size,weight:.semibold),.foregroundColor: NSColor.white]) }
        image.unlockFocus(); return image
    }
}
