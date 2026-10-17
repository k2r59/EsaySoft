import AppKit
import ImageIO

struct ScrollMatch {
    enum Kind { case duplicate, shifted, unmatched }
    let kind:Kind
    var offset:Int=0
    var error:Double=0
}

/// Pixel-based vertical registration. No Accessibility or input-event permissions required.
enum ScrollStitcher {
    struct Raster {
        let width:Int
        let height:Int
        let pixels:[UInt8]
        init(_ image:CGImage,width:Int?=nil,height:Int?=nil) throws {
            let w=width ?? image.width,h=height ?? image.height
            self.width=w;self.height=h
            var bytes=[UInt8](repeating:0,count:w*h*4)
            let success=bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
                context.interpolationQuality = .high
                context.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return true
            }
            guard success else{throw failure("Impossible de décoder la capture.")};pixels=bytes
        }
        func luma(_ x:Int,_ y:Int)->Double { let i=(y*width+x)*4;return Double(Int(pixels[i])*3+Int(pixels[i+1])*6+Int(pixels[i+2]))/10 }
    }
    static func failure(_ message:String)->NSError { NSError(domain:"EasyShoot.Scroll",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    static func difference(_ a:Raster,_ b:Raster,offset:Int,dense:Bool=false)->Double {
        let overlap=a.height-offset
        guard overlap>10 else{return .infinity}
        let margin=max(3,overlap/12),stepY=dense ? 1:max(1,(overlap-margin*2)/65),stepX=max(1,a.width/45)
        var error=0.0;var samples=0
        for y in stride(from:margin,to:overlap-margin,by:stepY) {
            for x in stride(from:a.width/12,to:a.width-a.width/12,by:stepX) {
                let aa=a.luma(x,y+offset),bb=b.luma(x,y)
                error += abs(aa-bb)
                // Edges disambiguate white backgrounds and closely spaced lines of text.
                if y+offset+1<a.height && y+1<b.height { error += abs((a.luma(x,y+offset+1)-aa)-(b.luma(x,y+1)-bb))*0.6 }
                samples+=1
            }
        }
        return samples>0 ? error/Double(samples):.infinity
    }
    static func match(_ first:CGImage,_ next:CGImage)throws->ScrollMatch {
        guard first.width == next.width,first.height == next.height else { throw failure("La taille de la zone a changé. Recommence la capture.") }
        let h=min(560,first.height),w=min(112,first.width)
        let a=try Raster(first,width:w,height:h),b=try Raster(next,width:w,height:h)
        let unchanged=difference(a,b,offset:0)
        if unchanged<0.7 {return ScrollMatch(kind:.duplicate,error:unchanged)}
        let minOverlap=max(50,h/5)
        var candidates=[(Int,Double)]()
        for offset in 2..<(h-minOverlap) { candidates.append((offset,difference(a,b,offset:offset))) }
        candidates.sort{$0.1<$1.1}
        guard !candidates.isEmpty else{return ScrollMatch(kind:.unmatched)}
        // Downsampling can shift text edges by a fraction of a pixel on Retina.
        // Refine several distinct coarse candidates before making a confidence decision.
        var shortlist=[(Int,Double)]()
        for c in candidates {
            if shortlist.allSatisfy({abs($0.0-c.0)>max(4,h/100)}) {shortlist.append(c)}
            if shortlist.count == 8 {break}
        }
        let scale=Double(first.height)/Double(h),radius=max(2,Int(ceil(scale*2)))
        let fullA=try Raster(first),fullB=try Raster(next)
        var refinements=[(Int,Double)]()
        for candidate in shortlist {
            let guess=Int((Double(candidate.0)*scale).rounded())
            var refined=(guess,Double.infinity)
            for d in max(1,guess-radius)...min(first.height-20,guess+radius) {
                let score=difference(fullA,fullB,offset:d,dense:true)
                if score<refined.1 {refined=(d,score)}
            }
            refinements.append(refined)
        }
        refinements.sort{$0.1<$1.1}
        guard let best=refinements.first,best.1<9,best.1<difference(fullA,fullB,offset:0)*0.62 else{return ScrollMatch(kind:.unmatched,error:refinements.first?.1 ?? .infinity)}
        if let second=refinements.first(where:{abs($0.0-best.0)>max(7,first.height/60)}),second.1<=best.1*1.12+0.12 {return ScrollMatch(kind:.unmatched,error:best.1)}
        return ScrollMatch(kind:.shifted,offset:best.0,error:best.1)
    }
    static func copy(_ image:CGImage)throws->CGImage {
        guard let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw failure("Mémoire insuffisante pour cette capture.")}
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        guard let result=context.makeImage() else{throw failure("Impossible de préparer la capture.")};return result
    }
    static func assemble(_ strips:[CGImage])throws->CGImage {
        guard let first=strips.first,strips.allSatisfy({$0.width == first.width}) else{throw failure("Aucune capture à assembler.")}
        let height=strips.reduce(0){$0+$1.height}
        guard height<=50000,first.width*height<=40_000_000 else{throw failure("Limite de 40 mégapixels atteinte. Termine cette capture et poursuis dans une seconde image.")}
        guard let context=CGContext(data:nil,width:first.width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{throw failure("Mémoire insuffisante pour assembler la capture.")}
        var top=height
        for strip in strips {top-=strip.height;context.draw(strip,in:CGRect(x:0,y:top,width:strip.width,height:strip.height))}
        guard let image=context.makeImage() else{throw failure("Impossible d’assembler les images.")};return image
    }
    static func writePNG(_ image:CGImage,to url:URL)throws {
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else{throw failure("Impossible d’écrire le fichier PNG.")}
        CGImageDestinationAddImage(destination,image,nil)
        guard CGImageDestinationFinalize(destination) else{throw failure("L’enregistrement du PNG a échoué.")}
    }
}

struct ScrollAccumulator {
    private(set) var strips:[CGImage]=[]
    private(set) var last:CGImage?
    var height:Int { strips.reduce(0){$0+$1.height} }
    var width:Int { last?.width ?? 0 }
    mutating func append(_ image:CGImage)throws->ScrollMatch {
        guard let previous=last else {strips=[try ScrollStitcher.copy(image)];last=image;return ScrollMatch(kind:.shifted,offset:image.height)}
        let match=try ScrollStitcher.match(previous,image)
        if match.kind == .shifted {
            guard (height+match.offset)*width<=40_000_000,height+match.offset<=50000 else{throw ScrollStitcher.failure("Limite de taille atteinte. Termine cette capture avant de continuer.")}
            guard let bottom=image.cropping(to:CGRect(x:0,y:image.height-match.offset,width:image.width,height:match.offset)) else{throw ScrollStitcher.failure("Impossible d’assembler la nouvelle portion.")}
            strips.append(try ScrollStitcher.copy(bottom));last=image
        }
        return match
    }
}
