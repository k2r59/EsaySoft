import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct AnnotationBackdrop: Equatable, Codable {
    var background = "none"
    var padding: Double = 64
    var inset: Double = 0
    var shadow: Double = 36
    var corners: Double = 18
    var alignment = 4
    var ratio = "Auto"
    var autoBalance = false
    var enabled: Bool { background != "none" }
    static let ratios = ["Auto", "1:1", "4:3", "3:2", "16:9", "9:16", "4:5"]
    struct Layout: Equatable {
        let size: CGSize
        let image: CGRect
        let card: CGRect
    }
    func layout(for size: CGSize) -> Layout {
        guard enabled else { return Layout(size:size,image:CGRect(origin:.zero,size:size),card:CGRect(origin:.zero,size:size)) }
        let p = min(320,max(0,padding.isFinite ? padding : 64)), i = min(120,max(0,inset.isFinite ? inset : 0))
        var w = size.width+2*(p+i), h = size.height+2*(p+i)
        let parts = ratio.split(separator:":").compactMap { Double($0) }
        if Self.ratios.contains(ratio), parts.count == 2, parts[1] > 0, parts[0] > 0 {
            let aspect = parts[0]/parts[1]
            if w/h < aspect { w = h*aspect } else { h = w/aspect }
        }
        let column = min(8,max(0,alignment)) % 3, row = min(8,max(0,alignment)) / 3
        let x = p+i+(w-size.width-2*(p+i))*Double(column)/2
        let y = p+i+(h-size.height-2*(p+i))*Double(2-row)/2
        let rect = CGRect(x:x.rounded(),y:y.rounded(),width:size.width,height:size.height)
        return Layout(size:CGSize(width:ceil(w),height:ceil(h)),image:rect,card:rect.insetBy(dx:-i,dy:-i))
    }
}
struct BackdropPreset: Identifiable {
    let id: String, name: String
    let colors: [UInt32]
    static let gradients: [BackdropPreset] = [
        .init(id:"rose",name:"Aurore",colors:[0xDE6CA5,0xF4A478,0xAF85D2]),
        .init(id:"violet",name:"Iris",colors:[0x4B426D,0x9C72DB,0x697DC8]),
        .init(id:"ocean",name:"Océan",colors:[0x153F7A,0x128FA0,0x213F81]),
        .init(id:"lagoon",name:"Lagon",colors:[0x15848A,0x5DC6B7,0xC9E8AD]),
        .init(id:"sunset",name:"Coucher de soleil",colors:[0xF49260,0xE471A1,0xF5BE75]),
        .init(id:"blush",name:"Pivoine",colors:[0xD690AF,0xF7D6DF,0xDA9BBE]),
        .init(id:"silver",name:"Brume",colors:[0xDFE8EF,0xA8C8CF,0xEBE3EF]),
        .init(id:"sand",name:"Dune",colors:[0xE8D6B7,0xAFC5C3,0xF3D9CA]),
        .init(id:"aurora",name:"Boréale",colors:[0x7171EB,0x76CFDF,0xC897E8]),
        .init(id:"midnight",name:"Minuit",colors:[0x101A36,0x4458AD,0x171528])
    ]
    static let wallpapers: [BackdropPreset] = [
        .init(id:"wall-blue",name:"Vagues",colors:[0x153989,0x198BBC,0x0D315C]),
        .init(id:"wall-mint",name:"Lumière",colors:[0x0E797D,0x9CE4D4,0x66A0D3]),
        .init(id:"wall-violet",name:"Crépuscule",colors:[0x28235C,0xBA73A9,0x5156A7])
    ]
    static let blurred: [BackdropPreset] = [
        .init(id:"blur-blue",name:"Bleu diffus",colors:[0x0A4389,0x559FDB,0x112955]),
        .init(id:"blur-earth",name:"Terre diffuse",colors:[0x443B33,0xAE967B,0x2C302E]),
        .init(id:"blur-night",name:"Nuit diffuse",colors:[0x0B0E16,0x3B3F5B,0x06090F])
    ]
    static let solids: [UInt32] = [0x17181C,0x6A6C79,0xFFFFFF,0xFF6C6C,0xEBA457,0xE1BC54,0x59B3A2,0x3D92E4,0x8F7BDC,0xE3A6D9,0xA5D2C4,0xB7D6EB,0xF7D6A5,0xEBDCE7,0xADC0B4]
    static func find(_ id:String) -> Self? { (gradients+wallpapers+blurred).first { $0.id == id } }
    static func color(_ hex:UInt32) -> CGColor { CGColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1) }
}
enum AnnotationRaster {
    enum Failure: LocalizedError {
        case message(String)
        var errorDescription:String? { if case .message(let text) = self { text } else { nil } }
    }
    static func decode(_ data:Data,maxPixels:Int? = nil) throws -> (CGImage,CGSize) {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 32768, h <= 32768, Int64(w)*Int64(h) <= 80_000_000 else { throw Failure.message("Image trop grande ou non prise en charge.") }
        let orientation=properties[kCGImagePropertyOrientation] as? Int ?? 1
        let rotated=(5...8).contains(orientation)
        let image:CGImage?
        if orientation != 1 || (maxPixels.map { max(w,h)>$0 } ?? false) {
            image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:maxPixels ?? max(w,h),kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
        } else { image = CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) }
        guard let image else { throw Failure.message("Impossible de lire l’image.") }
        return (image,CGSize(width:rotated ? h:w,height:rotated ? w:h))
    }
    static func png(_ image:CGImage) throws -> Data {
        let data = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil) else { throw Failure.message("Impossible de créer le PNG.") }
        CGImageDestinationAddImage(target,image,nil)
        guard CGImageDestinationFinalize(target) else { throw Failure.message("L’export PNG a échoué.") }
        return data as Data
    }
    static func fittedSize(pixels:CGSize,available:CGSize,displayScale:CGFloat) -> CGSize {
        let factor = min(1/displayScale,min(available.width/pixels.width,available.height/pixels.height))
        return CGSize(width:pixels.width*factor,height:pixels.height*factor)
    }
}
enum BackdropRenderer {
    static func background(_ style:AnnotationBackdrop,in c:CGContext,layout:AnnotationBackdrop.Layout,custom:CGImage? = nil) {
        let rect = CGRect(origin:.zero,size:layout.size)
        c.saveGState(); defer { c.restoreGState() }; c.clip(to:rect)
        if style.background == "custom", let custom {
            let scale = max(rect.width/CGFloat(custom.width),rect.height/CGFloat(custom.height))
            let size = CGSize(width:CGFloat(custom.width)*scale,height:CGFloat(custom.height)*scale)
            c.interpolationQuality = .high
            c.draw(custom,in:CGRect(x:(rect.width-size.width)/2,y:(rect.height-size.height)/2,width:size.width,height:size.height)); return
        }
        if style.background.hasPrefix("solid-"), let hex = UInt32(style.background.dropFirst(6),radix:16) {
            c.setFillColor(BackdropPreset.color(hex)); c.fill(rect); return
        }
        let preset = BackdropPreset.find(style.background) ?? BackdropPreset.gradients[3]
        let colors = preset.colors.map(BackdropPreset.color)
        if let gradient = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors as CFArray,locations:nil) {
            c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:rect.width,y:rect.height),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
        }
        if style.background.hasPrefix("wall-") || style.background.hasPrefix("blur-") {
            let fade = [colors[1].copy(alpha:0.75)!,colors[1].copy(alpha:0)!]
            if let glow = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:fade as CFArray,locations:nil) {
                c.drawRadialGradient(glow,startCenter:CGPoint(x:rect.width*0.2,y:rect.height*0.65),startRadius:0,endCenter:CGPoint(x:rect.width*0.25,y:rect.height*0.6),endRadius:max(rect.width,rect.height)*0.65,options:[])
            }
        }
    }
    static func card(_ style:AnnotationBackdrop,in c:CGContext,layout:AnnotationBackdrop.Layout,draw:(CGRect)->Void) {
        guard style.enabled else { draw(layout.image); return }
        let radius = min(max(0,style.corners.isFinite ? style.corners : 0),min(layout.card.width,layout.card.height)/2)
        let shadow = min(100,max(0,style.shadow.isFinite ? style.shadow : 0))
        let outline = CGPath(roundedRect:layout.card,cornerWidth:radius,cornerHeight:radius,transform:nil)
        c.saveGState()
        if shadow > 0 {
            c.setShadow(offset:CGSize(width:0,height:-shadow*0.24),blur:shadow*0.7,color:CGColor(gray:0,alpha:min(0.55,shadow/120)))
        }
        c.addPath(outline); c.setFillColor(CGColor(gray:0.98,alpha:1)); c.fillPath(); c.restoreGState()
        c.saveGState(); c.addPath(outline); c.clip()
        let innerRadius = max(0,radius-(style.inset.isFinite ? max(0,style.inset) : 0))
        c.addPath(CGPath(roundedRect:layout.image,cornerWidth:innerRadius,cornerHeight:innerRadius,transform:nil)); c.clip()
        draw(layout.image); c.restoreGState()
    }
    static func compose(_ image:CGImage,style:AnnotationBackdrop,custom:CGImage? = nil) throws -> CGImage {
        guard style.enabled else { return image }
        let layout = style.layout(for:CGSize(width:image.width,height:image.height))
        guard layout.size.width*layout.size.height <= 80_000_000, layout.size.width <= 32768, layout.size.height <= 32768 else { throw AnnotationRaster.Failure.message("Le fond dépasse la taille maximale. Réduis les marges ou change les proportions.") }
        guard let context = CGContext(data:nil,width:Int(layout.size.width),height:Int(layout.size.height),bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AnnotationRaster.Failure.message("Mémoire insuffisante pour cet export.") }
        background(style,in:context,layout:layout,custom:custom)
        card(style,in:context,layout:layout) { rect in context.interpolationQuality = .none; context.draw(image,in:rect) }
        guard let result = context.makeImage() else { throw AnnotationRaster.Failure.message("Impossible de créer l’image.") }; return result
    }
    /// Conservative trimming of a uniform border; never changes source pixels.
    /// The rectangle is normalized in image coordinates (origin at top-left).
    static func contentBounds(_ image:CGImage) -> CGRect {
        let full = CGRect(x:0,y:0,width:1,height:1)
        let factor = min(1,256/CGFloat(max(image.width,image.height)))
        let w = max(1,Int(CGFloat(image.width)*factor)), h = max(1,Int(CGFloat(image.height)*factor))
        guard w > 8,h > 8,let c = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue),let bytes = c.data?.assumingMemoryBound(to:UInt8.self) else { return full }
        c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
        let corners = [0,(w-1)*4,(h-1)*w*4,(w*h-1)*4]
        guard corners.allSatisfy({ p in (0..<4).allSatisfy { abs(Int(bytes[p+$0])-Int(bytes[$0])) < 12 } }) else { return full }
        var left=w,right=0,top=h,bottom=0
        for y in 0..<h { for x in 0..<w {
            let p=(y*w+x)*4
            if (0..<4).contains(where:{ abs(Int(bytes[p+$0])-Int(bytes[$0])) > 20 }) { left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y) }
        } }
        guard right>left,bottom>top else { return full }
        let margin=3
        left=max(0,left-margin);top=max(0,top-margin);right=min(w,right+margin+1);bottom=min(h,bottom+margin+1)
        return CGRect(x:Double(left)/Double(w),y:Double(top)/Double(h),width:Double(right-left)/Double(w),height:Double(bottom-top)/Double(h))
    }
}
