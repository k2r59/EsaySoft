import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers

/// Captures run inside the signed application, never in a new helper process.
enum CaptureImage {
    static func savePNG(_ image:CGImage,to url:URL) async throws {
        try await Task.detached(priority:.userInitiated) {
            try png(image,to:url)
        }.value
    }
    static func permissionError() -> NSError { NSError(domain:"EasyPaste.ScreenCapture",code:1,userInfo:[NSLocalizedDescriptionKey:"L’autorisation d’enregistrer l’écran n’est pas active pour cette copie d’EasyPaste. Active EasyPaste dans Réglages Système → Confidentialité et sécurité → Enregistrement de l’écran et de l’audio système. Si macOS demande de quitter l’app, rouvre EasyPaste depuis Applications."]) }
    static func png(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw CaptureFailure.message("Impossible de créer l’image.") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureFailure.message("Impossible d’encoder l’image.") }
        return data as Data
    }
    static func png(_ image:CGImage,to url:URL) throws {
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { throw NSError(domain:"EasyPaste",code:2,userInfo:[NSLocalizedDescriptionKey:"Impossible de créer le fichier PNG."]) }
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"EasyPaste",code:3,userInfo:[NSLocalizedDescriptionKey:"Impossible d’enregistrer la capture."])}
    }
    @MainActor static func nativeScale(_ id: CGDirectDisplayID) -> CGFloat {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }?.backingScaleFactor ?? 1
    }
    static func pixelSize(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: ceil(size.width * scale), height: ceil(size.height * scale))
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
        guard !displays.isEmpty,area.width>0,area.height>0,area.width.isFinite,area.height.isFinite else {throw NSError(domain:"EasyPaste",code:4,userInfo:[NSLocalizedDescriptionKey:"La zone est en dehors des écrans disponibles."])}
        let scale = displays.map { nativeScale($0.displayID) }.max() ?? 1
        let dimensions = pixelSize(area.size, scale: scale)
        let pixelWidth = dimensions.width, pixelHeight = dimensions.height
        guard pixelWidth>=1,pixelHeight>=1,pixelWidth*pixelHeight<=50_000_000 else {throw NSError(domain:"EasyPaste",code:5,userInfo:[NSLocalizedDescriptionKey:"La capture dépasse la limite de 50 mégapixels."])}
        let width=Int(pixelWidth),height=Int(pixelHeight)
        // A region contained by one display needs no second full-size bitmap or copy.
        if displays.count == 1,let display=displays.first,display.frame.contains(area) {
            let config=SCStreamConfiguration()
            config.sourceRect=CGRect(x:area.minX-display.frame.minX,y:area.minY-display.frame.minY,width:area.width,height:area.height)
            config.width=width;config.height=height;config.showsCursor=false;config.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }, exceptingWindows: []),configuration:config)
        }
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw permissionError()}
        for display in displays {
            let intersection=display.frame.intersection(area)
            let config=SCStreamConfiguration()
            config.sourceRect=CGRect(x:intersection.minX-display.frame.minX,y:intersection.minY-display.frame.minY,width:intersection.width,height:intersection.height)
            config.width=Int(ceil(intersection.width*scale));config.height=Int(ceil(intersection.height*scale));config.showsCursor=false
            let filter=SCContentFilter(display: display, excludingApplications: content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }, exceptingWindows: [])
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
