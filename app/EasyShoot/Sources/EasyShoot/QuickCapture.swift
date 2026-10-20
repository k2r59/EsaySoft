import AppKit
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

final class QuickCaptureController:NSWindowController {
    let url:URL
    unowned let coordinator:AppDelegate
    var isVideo:Bool { url.pathExtension.lowercased() == "mp4" }
    init(url:URL,owner:AppDelegate) {
        self.url=url;coordinator=owner
        let frame=(NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let panel=NSPanel(contentRect:NSRect(x:frame.maxX-380,y:frame.minY+22,width:350,height:310),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        super.init(window:panel)
        panel.title="EasyShoot · Aperçu"
        panel.isOpaque=false;panel.backgroundColor = .clear;panel.hasShadow=true;panel.level = .floating;panel.hidesOnDeactivate=false;panel.isReleasedWhenClosed=false;panel.isMovableByWindowBackground=true
        panel.contentView=NSHostingView(rootView:QuickCaptureView(controller:self).preferredColorScheme(.dark))
    }
    required init?(coder:NSCoder) { fatalError() }
    func dispose() { window?.orderOut(nil); window?.contentView=nil }
    func dismiss() {
        dispose()
        if coordinator.quickCapture === self { coordinator.quickCapture=nil }
    }
    func copy() {
        NSPasteboard.general.clearContents()
        let copied:Bool
        if isVideo { copied=NSPasteboard.general.writeObjects([url as NSURL]) }
        else if let image=NSImage(contentsOf:url) { copied=NSPasteboard.general.writeObjects([image]) }
        else {copied=false}
        guard copied else {coordinator.message("Copie impossible","Le fichier n’est plus disponible.");return}
        coordinator.sounds.play(.copy)
        coordinator.showToast(isVideo ? "Vidéo copiée":"Image copiée",detail:"Prête à coller avec ⌘V")
        dismiss()
    }
    func save() {
        NSApp.activate(ignoringOtherApps:true)
        let p=NSSavePanel();p.allowedContentTypes=[isVideo ? .mpeg4Movie:.png];p.nameFieldStringValue="EasyShoot-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))\(isVideo ? ".mp4":".png")"
        guard p.runModal() == .OK,let destination=p.url else{return}
        if destination.standardizedFileURL == url.standardizedFileURL { dismiss();return }
        let temporary=destination.deletingLastPathComponent().appendingPathComponent(".EasyShoot-\(UUID().uuidString).\(destination.pathExtension)")
        do {
            try FileManager.default.copyItem(at:url,to:temporary)
            if FileManager.default.fileExists(atPath:destination.path) { _ = try FileManager.default.replaceItemAt(destination,withItemAt:temporary) }
            else { try FileManager.default.moveItem(at:temporary,to:destination) }
            coordinator.showToast("Fichier enregistré",detail:destination.lastPathComponent)
            dismiss()
        } catch { try? FileManager.default.removeItem(at:temporary);coordinator.fail(error) }
    }
    func editOrOpen() { if isVideo { coordinator.showVideoEditor(url) } else if let image=NSImage(contentsOf:url) { coordinator.showEditor(image) };dismiss() }
    func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]);dismiss() }
}
struct QuickCaptureView:View {
    let controller:QuickCaptureController
    @State private var thumbnail:NSImage?
    @State private var details=""
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Image(systemName:controller.isVideo ? "video.fill":"checkmark.circle.fill").font(.system(size:12)).foregroundStyle(Color.esAccent)
                Text(controller.isVideo ? "Enregistrement prêt":"Capture prête").font(.system(size:12,weight:.semibold))
                Spacer()
                Button { controller.dismiss() } label: { Image(systemName:"xmark").font(.system(size:10,weight:.semibold)).foregroundStyle(Color.esMuted).frame(width:24,height:24).background(.white.opacity(0.05),in:Circle()) }.buttonStyle(HoverButtonStyle()).help("Fermer l’aperçu · l’original reste dans la bibliothèque")
            }.padding(.horizontal,16).padding(.top,14).padding(.bottom,12)
            ZStack {
                RoundedRectangle(cornerRadius:10).fill(.black.opacity(0.2))
                if let thumbnail { Image(nsImage:thumbnail).resizable().scaledToFit().padding(8) }
                else { Image(systemName:controller.isVideo ? "video":"photo").font(.system(size:26,weight:.light)).foregroundStyle(Color.esMuted) }
                if controller.isVideo { Image(systemName:"play.circle.fill").font(.system(size:38)).foregroundStyle(.white).shadow(radius:8) }
            }.frame(height:144).padding(.horizontal,14).onDrag { NSItemProvider(contentsOf:controller.url) ?? NSItemProvider() }.help("Glisser le fichier vers une application")
            HStack { Text(details).font(.system(size:10)).foregroundStyle(Color.esMuted);Spacer();Image(systemName:"hand.draw").font(.system(size:10)).foregroundStyle(Color.esMuted);Text("Glisser pour partager").font(.system(size:9)).foregroundStyle(Color.esMuted) }.padding(.horizontal,16).padding(.top,9)
            HStack(spacing:7) {
                quickButton("Copier","square.on.square",primary:true) { controller.copy() }
                quickButton("Enregistrer","arrow.down.to.line") { controller.save() }
                iconButton(controller.isVideo ? "scissors":"pencil",controller.isVideo ? "Monter la vidéo":"Annoter l’image") { controller.editOrOpen() }
                iconButton("folder","Afficher dans le Finder") { controller.reveal() }
            }.padding(14)
        }.background(Color.esSurface,in:RoundedRectangle(cornerRadius:17)).overlay(RoundedRectangle(cornerRadius:17).stroke(.white.opacity(0.12))).padding(3)
        .task {
            let url=controller.url
            if controller.isVideo {
                let bytes=(try? url.resourceValues(forKeys:[.fileSizeKey]).fileSize) ?? 0
                let size=ByteCountFormatter.string(fromByteCount:Int64(bytes),countStyle:.file)
                details="MP4 · \(size)"
                let generator=AVAssetImageGenerator(asset:AVURLAsset(url:url));generator.appliesPreferredTrackTransform=true;generator.maximumSize=CGSize(width:640,height:400)
                if let result=try? await generator.image(at:.zero),!Task.isCancelled { thumbnail=NSImage(cgImage:result.image,size:.zero) }
            } else {
                guard let preview=await CaptureAssets.shared.preview(for:url),!Task.isCancelled else{return}
                thumbnail=NSImage(cgImage:preview.image,size:.zero)
                let size=ByteCountFormatter.string(fromByteCount:Int64(preview.fileSize),countStyle:.file)
                details="PNG · \(preview.originalWidth) × \(preview.originalHeight) · \(size)"
            }
        }
    }
    func quickButton(_ title:String,_ symbol:String,primary:Bool=false,_ action:@escaping()->Void)->some View { Button(action:action) { Label(title,systemImage:symbol).font(.system(size:10,weight:.semibold)).foregroundStyle(primary ? Color.black.opacity(0.85):Color.white).padding(.horizontal,11).frame(height:32).background(primary ? Color.esAccent:Color.white.opacity(0.07),in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(HoverButtonStyle()).help(title == "Enregistrer" ? "Enregistrer sous…":title) }
    func iconButton(_ symbol:String,_ hint:String,_ action:@escaping()->Void)->some View { Button(action:action) { Image(systemName:symbol).font(.system(size:12)).foregroundStyle(Color.esMuted).frame(width:32,height:32).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(HoverButtonStyle()).help(hint).accessibilityLabel(hint) }
}
