import XCTest
import SwiftUI
import CryptoKit
@testable import EasyPaste

@MainActor final class InterfaceLayoutTests: XCTestCase {
    func testAnnotationFitsMinimumWindow() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.95, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let image = try XCTUnwrap(context.makeImage()), data = try CaptureImage.png(image)
        let model = AnnotationModel(data: data, image: image, size: CGSize(width: 800, height: 500))
        model.commit(AnnotationMark(tool: .arrow, start: CGPoint(x: 100, y: 180), end: CGPoint(x: 500, y: 70), color: .coral, width: 7))
        let view = AnnotationView(model: model, cancel: {}, save: { _, _ in })
        try check(view, size: CGSize(width: 1000, height: 620), name: "annotation-minimum")
    }
    func testLibraryFitsMinimumWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "EasyPaste.layout." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        try check(MainView(history: history), size: CGSize(width: 1050, height: 740), name: "library-minimum")
    }
    func testEverySettingsCategoryFitsMinimumWindow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "EasyPaste.settings.layout." + UUID().uuidString, defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let history = History(vault: try ClipVault(directory: directory, key: SymmetricKey(size: .bits256)), monitor: false, defaults: defaults)
        for category in SettingsCategory.allCases {
            try check(SettingsView(history: history, initialCategory: category),
                      size: CGSize(width: 837, height: 740), name: "settings-\(category)")
        }
    }
    private func check<V: View>(_ root: V, size: CGSize, name: String) throws {
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            try check(root, size: size, name: name, appearance: appearance)
        }
    }
    private func check<V: View>(_ root: V, size: CGSize, name: String, appearance: NSAppearance.Name) throws {
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = host
        defer { window.close() }
        host.frame = CGRect(origin: .zero, size: size); host.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(host.fittingSize.width, size.width, "The interface must fit the supported minimum width.")
        if let folder = ProcessInfo.processInfo.environment["EASYPASTE_LAYOUT_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: folder); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url.appendingPathComponent(name+"-"+appearance.rawValue+".png"))
        }
    }
}
