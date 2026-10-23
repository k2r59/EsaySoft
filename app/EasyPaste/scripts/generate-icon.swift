import AppKit
let directory = CommandLine.arguments[1]
let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/EasyPaste/Resources/easypaste-ribbon.png")
guard let artwork = NSImage(contentsOf: source) else { fatalError("Missing approved EasyPaste ribbon artwork") }
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
    let tile = NSRect(x: s*0.06, y: s*0.06, width: s*0.88, height: s*0.88)
    // Apply the standard app-icon mask while exporting each ICNS resolution.
    // The approved ribbon artwork itself remains unchanged.
    NSBezierPath(roundedRect: tile, xRadius: s*0.2024, yRadius: s*0.2024).addClip()
    NSGraphicsContext.current!.imageInterpolation = .high
    artwork.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory + "/" + name + ".png"))
}
