import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for (name, size) in [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)] {
    // Explicit pixels: lockFocus() multiplies dimensions by the current display's
    // Retina scale, producing an invalid 2048px image for the 1024px ICNS slot.
    let s = CGFloat(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current!.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))
    let base = NSBezierPath(roundedRect: NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88), xRadius: s*0.20, yRadius: s*0.20)
    NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.23, blue: 0.28, alpha: 1), ending: NSColor(srgbRed: 0.055, green: 0.07, blue: 0.10, alpha: 1))!.draw(in: base, angle: 115)
    NSColor(srgbRed: 0.64, green: 0.69, blue: 1, alpha: 0.8).setFill()
    NSBezierPath(roundedRect: NSRect(x: s*0.23, y: s*0.32, width: s*0.41, height: s*0.45), xRadius: s*0.055, yRadius: s*0.055).fill()
    let front = NSBezierPath(roundedRect: NSRect(x: s*0.35, y: s*0.22, width: s*0.41, height: s*0.45), xRadius: s*0.055, yRadius: s*0.055)
    NSGradient(starting: NSColor(srgbRed: 0.65, green: 0.98, blue: 0.85, alpha: 1), ending: NSColor(srgbRed: 0.36, green: 0.77, blue: 0.65, alpha: 1))!.draw(in: front, angle: 90)
    NSColor(srgbRed: 0.08, green: 0.23, blue: 0.21, alpha: 0.75).setFill()
    for (y, width) in [(0.51,0.21),(0.42,0.21),(0.33,0.13)] { NSBezierPath(roundedRect: NSRect(x: s*0.445, y: s*y, width: s*width, height: s*0.025), xRadius: s*0.012, yRadius: s*0.012).fill() }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
}
