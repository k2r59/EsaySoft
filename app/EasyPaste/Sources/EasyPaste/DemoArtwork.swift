import AppKit

/// An original, generated fixture for the isolated --demo workspace. Never added to user history.
enum DemoArtwork {
    static func png() -> Data {
        let image = NSImage(size: NSSize(width: 1000, height: 650)); image.lockFocus()
        NSGradient(colors: [NSColor(srgbRed: 0.68, green: 0.64, blue: 0.95, alpha: 1), NSColor(srgbRed: 0.95, green: 0.76, blue: 0.76, alpha: 1), NSColor(srgbRed: 1, green: 0.87, blue: 0.68, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: 1000, height: 650), angle: 95)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.72, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 605, y: 285, width: 180, height: 180)).fill()
        let back = NSBezierPath(); back.move(to: NSPoint(x: -50,y: 70)); back.curve(to: NSPoint(x: 1100,y: 180),controlPoint1: NSPoint(x: 320,y: 590),controlPoint2: NSPoint(x: 650,y: -30)); back.line(to: NSPoint(x: 1100,y: -20)); back.line(to: NSPoint(x: -50,y: -20)); back.close()
        NSColor(srgbRed: 0.42, green: 0.41, blue: 0.67, alpha: 1).setFill(); back.fill()
        let front = NSBezierPath(); front.move(to: NSPoint(x: -50,y: 15)); front.curve(to: NSPoint(x: 1100,y: 190),controlPoint1: NSPoint(x: 330,y: -120),controlPoint2: NSPoint(x: 800,y: 410)); front.line(to: NSPoint(x: 1100,y: -20)); front.line(to: NSPoint(x: -50,y: -20)); front.close()
        NSColor(srgbRed: 0.19, green: 0.29, blue: 0.38, alpha: 1).setFill(); front.fill()
        let title = "Prendre le large."
        title.draw(at: NSPoint(x: 58, y: 505), withAttributes: [.font: NSFont.systemFont(ofSize: 42, weight: .medium), .foregroundColor: NSColor.white])
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }
}
