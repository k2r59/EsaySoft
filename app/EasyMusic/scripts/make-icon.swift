import AppKit
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
NSColor(calibratedRed: 0.12, green: 0.85, blue: 0.39, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 172, y: 172, width: 680, height: 680)).fill()
NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
for (i, height) in [100.0, 220, 340, 180, 290, 140, 70].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 297 + Double(i) * 64, y: (1024-height)/2, width: 42, height: height), xRadius: 21, yRadius: 21).fill()
}
image.unlockFocus()
let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
