import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import CoreVideo

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
    /// Mouse locations can fall between pixels. Enclose the selection on the
    /// source pixel grid so ScreenCaptureKit never resamples half-pixel text.
    static func pixelAligned(_ rect: CGRect, scale: CGFloat) throws -> CGRect {
        guard scale.isFinite, scale > 0, [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite), rect.width > 0, rect.height > 0 else {
            throw CaptureFailure.message("La zone de capture n’est pas valide.")
        }
        let left = floor(rect.minX * scale), top = floor(rect.minY * scale)
        let right = ceil(rect.maxX * scale), bottom = ceil(rect.maxY * scale)
        guard (right-left) * (bottom-top) <= 50_000_000 else {
            throw CaptureFailure.message("La capture dépasse la limite de 50 mégapixels.")
        }
        return CGRect(x: left/scale, y: top/scale, width: (right-left)/scale, height: (bottom-top)/scale)
    }
    static func configuration(size: CGSize, scale: CGFloat) throws -> SCStreamConfiguration {
        let pixels = try pixelAligned(CGRect(origin: .zero, size: size), scale: scale).size
        let config = SCStreamConfiguration()
        config.width = Int((pixels.width * scale).rounded())
        config.height = Int((pixels.height * scale).rounded())
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.scalesToFit = false
        return config
    }
    @MainActor static func content() async throws -> SCShareableContent {
        guard CGPreflightScreenCaptureAccess() else {throw permissionError()}
        return try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
    }
    static func composite(_ pieces: [(CGImage, CGRect)], width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0, width <= ImageRaster.pixelLimit / height,
              let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureFailure.message("La capture dépasse les dimensions autorisées.") }
        // Mixed-density displays: duplicate 1x pixels instead of softening
        // them; retain every 2x pixel. Never shrink the Retina section.
        context.interpolationQuality = .none
        for (image,destination) in pieces { context.draw(image,in:destination) }
        guard let image=context.makeImage() else { throw permissionError() }
        return image
    }
    @MainActor static func region(_ rect:CGRect? = nil) async throws -> CGImage {
        let content=try await content()
        guard let main=content.displays.first(where:{$0.displayID == CGMainDisplayID()}) else {throw permissionError()}
        let requested=rect ?? main.frame
        _ = try pixelAligned(requested, scale: 1)
        let candidates=content.displays.filter{$0.frame.intersects(requested)}
        let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filters = Dictionary(uniqueKeysWithValues: candidates.map { ($0.displayID, SCContentFilter(display: $0, excludingApplications: excluded, exceptingWindows: [])) })
        let scale = filters.values.map { CGFloat($0.pointPixelScale) }.max() ?? 1
        let area = try pixelAligned(requested, scale: scale)
        let displays=content.displays.filter{$0.frame.intersects(area)}
        guard !displays.isEmpty,area.width>0,area.height>0,area.width.isFinite,area.height.isFinite else {throw NSError(domain:"EasyPaste",code:4,userInfo:[NSLocalizedDescriptionKey:"La zone est en dehors des écrans disponibles."])}
        let dimensions = pixelSize(area.size, scale: scale)
        let pixelWidth = dimensions.width, pixelHeight = dimensions.height
        guard pixelWidth>=1,pixelHeight>=1,pixelWidth*pixelHeight<=50_000_000 else {throw NSError(domain:"EasyPaste",code:5,userInfo:[NSLocalizedDescriptionKey:"La capture dépasse la limite de 50 mégapixels."])}
        let width=Int(pixelWidth),height=Int(pixelHeight)
        // A region contained by one display needs no second full-size bitmap or copy.
        if displays.count == 1,let display=displays.first,display.frame.contains(area) {
            let config=try configuration(size:area.size,scale:scale)
            config.sourceRect=CGRect(x:area.minX-display.frame.minX,y:area.minY-display.frame.minY,width:area.width,height:area.height)
            return try await SCScreenshotManager.captureImage(contentFilter:filters[display.displayID]!,configuration:config)
        }
        var pieces: [(CGImage, CGRect)] = []
        for display in displays {
            let intersection=display.frame.intersection(area)
            let filter=filters[display.displayID] ?? SCContentFilter(display:display,excludingApplications:excluded,exceptingWindows:[])
            let sourceScale = CGFloat(filter.pointPixelScale)
            let local = try pixelAligned(CGRect(x:intersection.minX-display.frame.minX,y:intersection.minY-display.frame.minY,width:intersection.width,height:intersection.height),scale:sourceScale)
            let config=try configuration(size:local.size,scale:sourceScale)
            config.sourceRect=local
            let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
            let destination=CGRect(x:(display.frame.minX+local.minX-area.minX)*scale,y:(area.maxY-display.frame.minY-local.maxY)*scale,width:local.width*scale,height:local.height*scale)
            pieces.append((image,destination))
        }
        let captured = pieces
        return try await Task.detached(priority:.userInitiated) {
            try composite(captured,width:width,height:height)
        }.value
    }
    @MainActor static func window(_ window:SCWindow) async throws -> CGImage {
        guard CGPreflightScreenCaptureAccess() else {throw permissionError()}
        let filter=SCContentFilter(desktopIndependentWindow:window)
        let config=try configuration(size:filter.contentRect.size,scale:CGFloat(filter.pointPixelScale))
        config.showsCursor=false;config.ignoreShadowsSingleWindow=true
        return try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
    }
}
