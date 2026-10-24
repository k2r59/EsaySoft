import AppKit
import UniformTypeIdentifiers

@MainActor final class AnnotationActions {
    let model:AnnotationModel
    private var pinned:[NSPanel] = []
    private var noticeTask:Task<Void,Never>?
    init(model:AnnotationModel) {self.model=model}
    func render(_ action:@escaping(Data)->Void) {
        guard !model.saving else{return}
        if model.textPoint != nil {model.addText()}
        model.saving=true;model.error=""
        let data=model.data,snapshot=model.snapshot,background=model.customBackground
        Task {
            do {
                let output=try await Task.detached(priority:.userInitiated) {try AnnotationRenderer.export(data:data,snapshot:snapshot,customBackground:background)}.value
                model.saving=false;action(output)
            } catch {model.saving=false;model.error=error.localizedDescription}
        }
    }
    func copy(completion:(()->Void)? = nil) {
        render { [self] data in
            let pasteboard=NSPasteboard.general
            pasteboard.clearContents()
            if pasteboard.setData(data,forType:.png) {notify("Image copiée");completion?()}
            else {model.error="Impossible de copier l’image."}
        }
    }
    func export(completion:(()->Void)? = nil) {
        let panel=NSSavePanel();panel.allowedContentTypes=[.png];panel.nameFieldStringValue="Capture.png";panel.canCreateDirectories=true
        guard panel.runModal() == .OK,let url=panel.url else{return}
        render { [self] data in
            model.saving=true
            Task {
                do {try await Task.detached(priority:.userInitiated) {try data.write(to:url,options:.atomic)}.value;model.saving=false;notify("PNG enregistré");completion?()}
                catch {model.saving=false;model.error=error.localizedDescription}
            }
        }
    }
    func pin() {
        render { [self] data in
            guard let image=NSImage(data:data) else{return}
            let width:CGFloat=420,height=max(80,min(650,width*image.size.height/image.size.width))
            let panel=NSPanel(contentRect:CGRect(x:100,y:100,width:width,height:height),styleMask:[.titled,.closable,.resizable,.utilityWindow],backing:.buffered,defer:false)
            panel.title="Capture épinglée";panel.level = .floating;panel.isFloatingPanel=true;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false
            let view=NSImageView();view.image=image;view.imageScaling = .scaleProportionallyUpOrDown;panel.contentView=view
            pinned.removeAll { !$0.isVisible };pinned.append(panel);panel.makeKeyAndOrderFront(nil)
        }
    }
    func provider()->NSItemProvider {
        if model.textPoint != nil {model.addText()}
        let data=model.data,snapshot=model.snapshot,background=model.customBackground
        let provider=NSItemProvider();provider.suggestedName="Capture.png"
        provider.registerDataRepresentation(forTypeIdentifier:UTType.png.identifier,visibility:.all) {completion in
            let progress=Progress(totalUnitCount:1)
            let worker=Task.detached(priority:.userInitiated) {
                do {try Task.checkCancellation();let png=try AnnotationRenderer.export(data:data,snapshot:snapshot,customBackground:background);try Task.checkCancellation();progress.completedUnitCount=1;completion(png,nil)}
                catch {completion(nil,error)}
            }
            progress.cancellationHandler={worker.cancel()};return progress
        }
        return provider
    }
    func notify(_ text:String) {
        noticeTask?.cancel();model.notice=text
        noticeTask=Task {try? await Task.sleep(for:.seconds(2));guard !Task.isCancelled else{return};model.notice=""}
    }
}
