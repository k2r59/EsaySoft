import AppKit
import SwiftUI

/// Opt-in entry before production initialization: no vault, capture, hotkeys,
/// account, login item or updater is started by the local preview bundles.
@MainActor enum AnnotationPreviewLauncher {
    static var delegate:AnnotationPreviewDelegate?
    static func runIfNeeded()->Bool {
        guard Bundle.main.object(forInfoDictionaryKey:"AnnotationPreview") as? Bool == true else{return false}
        let app=NSApplication.shared, owner=AnnotationPreviewDelegate()
        delegate=owner;app.delegate=owner;app.setActivationPolicy(.regular);app.run();return true
    }
}
@MainActor final class AnnotationPreviewDelegate:NSObject,NSApplicationDelegate,NSWindowDelegate {
    private var window:NSWindow!
    private var model:AnnotationModel!
    private var actions:AnnotationActions!
    private var closing=false
    private let appName=Bundle.main.object(forInfoDictionaryKey:"AnnotationPreviewProduct") as? String ?? "EasyPaste"
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu=NSMenu(), appItem=NSMenuItem(), appMenu=NSMenu()
        appMenu.addItem(withTitle:"Quitter l’atelier",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");appItem.submenu=appMenu;menu.addItem(appItem)
        let editItem=NSMenuItem(title:"Édition",action:nil,keyEquivalent:""), editMenu=NSMenu(title:"Édition")
        for (name,key,selector) in [("Couper","x",#selector(NSText.cut(_:))),("Copier","c",#selector(NSText.copy(_:))),("Coller","v",#selector(NSText.paste(_:))),("Tout sélectionner","a",#selector(NSText.selectAll(_:)))] {editMenu.addItem(withTitle:name,action:selector,keyEquivalent:key)}
        editItem.submenu=editMenu;menu.addItem(editItem);NSApp.mainMenu=menu
        window=NSWindow(contentRect:CGRect(x:100,y:100,width:1180,height:840),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title=appName+" · Atelier d’annotation — TEST";window.titleVisibility = .hidden;window.titlebarAppearsTransparent=true;window.isReleasedWhenClosed=false;window.minSize=CGSize(width:1080,height:700);window.delegate=self
        window.appearance=NSAppearance(named:.darkAqua);window.center()
        do {try show(Self.sample(),styled:true)} catch {NSApp.presentError(error)}
        window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
    private func show(_ data:Data,styled:Bool=false,prepared supplied:(CGImage,CGSize)? = nil) throws {
        let prepared=try supplied ?? AnnotationModel.prepare(data)
        model=AnnotationModel(data:data,image:prepared.0,size:prepared.1)
        if styled {model.snapshot.backdrop.background="lagoon";model.snapshot.backdrop.padding=200;model.snapshot.backdrop.corners=28;model.snapshot.backdrop.shadow=45}
        actions=AnnotationActions(model:model)
        window.contentView=NSHostingView(rootView:AnnotationView(model:model,cancel:{[weak self] in self?.requestClose()},save:{[weak self] _,copy in self?.finish(copy:copy)},open:{[weak self] in self?.open()},copy:{[weak self] in self?.actions.copy()},export:{[weak self] in self?.actions.export()},pin:{[weak self] in self?.actions.pin()},dragProvider:{[weak self] in self?.actions.provider() ?? NSItemProvider()},appName:appName,allowReplacement:false).ignoresSafeArea(.container,edges:.top))
    }
    private func open() {
        guard !model.saving else{return}
        if !model.undoStates.isEmpty || model.textPoint != nil {
            let alert=NSAlert();alert.messageText="Ouvrir une autre image ?";alert.informativeText="Enregistre d’abord les modifications que tu souhaites conserver.";alert.addButton(withTitle:"Annuler");alert.addButton(withTitle:"Ouvrir")
            guard alert.runModal() == .alertSecondButtonReturn else{return}
        }
        let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.tiff,.heic];panel.canChooseDirectories=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        model.saving=true
        Task {
            do {let prepared=try await Task.detached(priority:.userInitiated) {let data=try Data(contentsOf:url);return (data,try AnnotationModel.prepare(data))}.value;model.saving=false;try show(prepared.0,prepared:prepared.1)}
            catch {model.saving=false;model.error=error.localizedDescription}
        }
    }
    private func finish(copy:Bool) {
        let close:()->Void = { [weak self] in self?.closing=true;self?.window.close() }
        if copy {actions.copy(completion:close)} else {actions.export(completion:close)}
    }
    private func requestClose() {if windowShouldClose(window) {closing=true;window.close()}}
    func windowShouldClose(_ sender:NSWindow)->Bool {
        guard let model else{return true}
        guard !model.saving else{return false}
        if closing || !model.dirty {return true}
        let alert=NSAlert();alert.messageText="Fermer sans enregistrer ?";alert.informativeText="L’image originale reste intacte.";alert.addButton(withTitle:"Continuer à modifier");alert.addButton(withTitle:"Fermer")
        let discard=alert.runModal() == .alertSecondButtonReturn
        if discard {closing=true}
        return discard
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {true}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {closing || windowShouldClose(window) ? .terminateNow:.terminateCancel}
    private static func sample() throws -> Data {
        let width=620,height=340
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else {throw AnnotationRaster.Failure.message("Impossible de préparer l’exemple.")}
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
        NSColor(srgbRed:0.045,green:0.055,blue:0.06,alpha:1).setFill();CGRect(x:0,y:0,width:width,height:height).fill()
        let text="Une idée claire mérite\nune capture nette."
        (text as NSString).draw(in:CGRect(x:42,y:160,width:540,height:130),withAttributes:[.font:NSFont.systemFont(ofSize:30,weight:.medium),.foregroundColor:NSColor.white])
        NSColor(srgbRed:0.18,green:0.6,blue:0.7,alpha:1).setFill();NSBezierPath(ovalIn:CGRect(x:42,y:53,width:48,height:48)).fill()
        ("E" as NSString).draw(at:CGPoint(x:57,y:62),withAttributes:[.font:NSFont.boldSystemFont(ofSize:25),.foregroundColor:NSColor.white])
        ("Ton prochain partage" as NSString).draw(at:CGPoint(x:108,y:77),withAttributes:[.font:NSFont.boldSystemFont(ofSize:16),.foregroundColor:NSColor.white])
        ("Exemple local · modifiable" as NSString).draw(at:CGPoint(x:108,y:53),withAttributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.lightGray])
        NSGraphicsContext.restoreGraphicsState()
        guard let data=bitmap.representation(using:.png,properties:[:]) else {throw AnnotationRaster.Failure.message("Impossible de créer l’exemple.")};return data
    }
}
