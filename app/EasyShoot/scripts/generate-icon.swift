import AppKit
let folder=URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let n=base*scale
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:n,pixelsHigh:n,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        let t=AffineTransform(scale:CGFloat(n)/1024);(t as NSAffineTransform).concat()
        let bg=NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:205,yRadius:205)
        NSGradient(starting:NSColor(calibratedRed:0.19,green:0.21,blue:0.26,alpha:1),ending:NSColor(calibratedRed:0.055,green:0.065,blue:0.085,alpha:1))!.draw(in:bg,angle: -90)
        NSColor(calibratedRed:1,green:0.47,blue:0.28,alpha:1).setStroke()
        let p=NSBezierPath();p.lineWidth=65;p.lineCapStyle = .round;p.lineJoinStyle = .round
        for (x,y,sx,sy) in [(290.0,290.0,1.0,1.0),(734,290,-1,1),(290,734,1,-1),(734,734,-1,-1)] {
            p.move(to:NSPoint(x:x,y:y+110*sy));p.line(to:NSPoint(x:x,y:y+30*sy));p.curve(to:NSPoint(x:x+30*sx,y:y),controlPoint1:NSPoint(x:x,y:y),controlPoint2:NSPoint(x:x,y:y));p.line(to:NSPoint(x:x+110*sx,y:y))
        };p.stroke()
        NSColor.white.withAlphaComponent(0.95).setFill();NSBezierPath(ovalIn:NSRect(x:476,y:476,width:72,height:72)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name="icon_\(base)x\(base)\(scale == 2 ? "@2x":"").png"
        try rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(name))
    }
}
