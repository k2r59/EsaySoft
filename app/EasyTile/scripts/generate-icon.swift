import AppKit
let dir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:dir,withIntermediateDirectories:true)
for (name,size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    let image = NSImage(size:NSSize(width:size,height:size)); image.lockFocus()
    let s = CGFloat(size); let r = NSRect(x:s*0.06,y:s*0.06,width:s*0.88,height:s*0.88)
    NSGradient(starting:NSColor(srgbRed:0.17,green:0.21,blue:0.26,alpha:1),ending:NSColor(srgbRed:0.055,green:0.065,blue:0.09,alpha:1))!.draw(in:NSBezierPath(roundedRect:r,xRadius:s*0.19,yRadius:s*0.19),angle:110)
    let tiles:[(NSRect,NSColor)] = [(.init(x:s*0.23,y:s*0.23,width:s*0.29,height:s*0.54),NSColor(srgbRed:0.55,green:0.92,blue:0.79,alpha:1)),(.init(x:s*0.56,y:s*0.52,width:s*0.21,height:s*0.25),NSColor(srgbRed:0.65,green:0.70,blue:1,alpha:1)),(.init(x:s*0.56,y:s*0.23,width:s*0.21,height:s*0.25),NSColor(srgbRed:0.96,green:0.77,blue:0.57,alpha:1))]
    for (rect,color) in tiles { color.setFill(); NSBezierPath(roundedRect:rect,xRadius:s*0.035,yRadius:s*0.035).fill() }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
    try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:dir+"/"+name+".png"))
}
