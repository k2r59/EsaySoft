import AppKit
import SwiftUI

@MainActor final class EditorController:NSWindowController,NSWindowDelegate {
    let model:AnnotationModel
    let actions:AnnotationActions
    unowned let coordinator:AppDelegate
    private var finishing=false
    init(image:NSImage,owner:AppDelegate) throws {
        coordinator=owner
        guard let data=image.tiffRepresentation else {throw AnnotationRaster.Failure.message("Impossible de lire cette image.")}
        let prepared=try AnnotationModel.prepare(data)
        model=AnnotationModel(data:data,image:prepared.0,size:prepared.1);actions=AnnotationActions(model:model)
        let w=NSWindow(contentRect:CGRect(x:0,y:0,width:1120,height:760),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        super.init(window:w)
        w.title="EasyShoot · Éditeur";w.titleVisibility = .hidden;w.titlebarAppearsTransparent=true;w.center();w.minSize=CGSize(width:1080,height:700);w.delegate=self
        w.isOpaque=false;w.backgroundColor = .clear;w.titlebarAppearsTransparent=true
        w.contentView=NSHostingView(rootView:AnnotationView(model:model,cancel:{[weak self] in self?.window?.performClose(nil)},save:{[weak self] _,copy in self?.finish(copy:copy)},open:{[weak self] in self?.coordinator.openImage()},copy:{[weak self] in self?.actions.copy()},export:{[weak self] in self?.actions.export()},pin:{[weak self] in self?.actions.pin()},dragProvider:{[weak self] in self?.actions.provider() ?? NSItemProvider()},appName:"EasyShoot",allowReplacement:false).ignoresSafeArea(.container,edges:.top))
    }
    required init?(coder:NSCoder) {fatalError()}
    private func finish(copy:Bool) {
        let completion:()->Void = {[weak self] in self?.finishing=true;self?.window?.close()}
        if copy {actions.copy(completion:completion)} else {actions.export(completion:completion)}
    }
    func windowShouldClose(_ sender:NSWindow)->Bool {
        guard !model.saving else{return false}
        guard model.dirty && !finishing else{return true}
        let alert=NSAlert();alert.messageText="Fermer sans enregistrer ?";alert.informativeText="L’image originale reste intacte.";alert.addButton(withTitle:"Continuer à modifier");alert.addButton(withTitle:"Fermer")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification:Notification) {window?.contentView=nil;coordinator.editors.removeAll {$0 === self}}
}
