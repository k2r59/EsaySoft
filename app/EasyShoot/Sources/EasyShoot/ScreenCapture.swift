import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

/// Captures run inside the signed application, never in a new helper process.
enum NativeScreenCapture {
    static func savePNG(_ image:CGImage,to url:URL) async throws {
        try await Task.detached(priority:.userInitiated) {
            try png(image,to:url)
        }.value
    }
    static func permissionError() -> NSError { NSError(domain:"EasyShoot.ScreenCapture",code:1,userInfo:[NSLocalizedDescriptionKey:"L’autorisation d’enregistrer l’écran n’est pas active pour cette copie d’EasyShoot. Active EasyShoot dans Réglages Système → Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Si macOS demande de quitter l’app, rouvre EasyShoot depuis Applications."]) }
    static func png(_ image:CGImage,to url:URL) throws {
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw NSError(domain:"EasyShoot",code:2,userInfo:[NSLocalizedDescriptionKey:"Impossible de créer le fichier PNG."]) }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"EasyShoot",code:3,userInfo:[NSLocalizedDescriptionKey:"Impossible d’enregistrer la capture."])}
    }
    @MainActor static func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {throw permissionError()}
        return try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
    }
    @MainActor static func region(_ rect:CGRect? = nil) async throws -> CGImage {
        let content=try await content()
        guard let main=content.displays.first(where:{$0.displayID == CGMainDisplayID()}) else {throw permissionError()}
        let area=rect ?? main.frame
        let displays=content.displays.filter{$0.frame.intersects(area)}
        guard !displays.isEmpty,area.width>0,area.height>0,area.width.isFinite,area.height.isFinite else {throw NSError(domain:"EasyShoot",code:4,userInfo:[NSLocalizedDescriptionKey:"La zone est en dehors des écrans disponibles."])}
        let scale=displays.map{Double($0.width)/$0.frame.width}.max() ?? 1
        let pixelWidth=ceil(area.width*scale),pixelHeight=ceil(area.height*scale)
        guard pixelWidth>=1,pixelHeight>=1,pixelWidth*pixelHeight<=100_000_000 else {throw NSError(domain:"EasyShoot",code:5,userInfo:[NSLocalizedDescriptionKey:"La capture dépasse la limite de 100 mégapixels."])}
        let width=Int(pixelWidth),height=Int(pixelHeight)
        // A region contained by one display needs no second full-size bitmap or copy.
        if displays.count == 1,let display=displays.first,display.frame.contains(area) {
            let config=SCStreamConfiguration()
            config.sourceRect=CGRect(x:area.minX-display.frame.minX,y:area.minY-display.frame.minY,width:area.width,height:area.height)
            config.width=width;config.height=height;config.showsCursor=false
            return try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(display:display,excludingWindows:[]),configuration:config)
        }
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw permissionError()}
        for display in displays {
            let intersection=display.frame.intersection(area)
            let config=SCStreamConfiguration()
            config.sourceRect=CGRect(x:intersection.minX-display.frame.minX,y:intersection.minY-display.frame.minY,width:intersection.width,height:intersection.height)
            config.width=Int(ceil(intersection.width*scale));config.height=Int(ceil(intersection.height*scale));config.showsCursor=false
            let filter=SCContentFilter(display:display,excludingWindows:[])
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let destination=CGRect(x:(intersection.minX-area.minX)*scale,y:(area.maxY-intersection.maxY)*scale,width:intersection.width*scale,height:intersection.height*scale)
            context.draw(image,in:destination)
        }
        guard let image=context.makeImage() else {throw permissionError()}
        return image
    }
    @MainActor static func window(_ window:SCWindow) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {throw permissionError()}
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=SCStreamConfiguration()
        config.width=Int(ceil(filter.contentRect.width*Double(filter.pointPixelScale)))
        config.height=Int(ceil(filter.contentRect.height*Double(filter.pointPixelScale)))
        config.showsCursor=false;config.ignoreShadowsSingleWindow=true
        return try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
    }
}
