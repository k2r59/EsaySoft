import AppKit
import XCTest
@testable import EasyPaste

final class BrowserBridgeTests: XCTestCase {
    private var hello: [String: Any] { ["protocol": 1, "type": "hello", "nonce": "1234567890abcdef1234567890abcdef", "extensionVersion": "0.2.0"] }
    func testHandshakeOnlyReturnsVersionAndMatchingNonce() throws {
        let data = try JSONSerialization.data(withJSONObject: hello)
        let reply = try BrowserBridgeProtocol.response(data, origin: BrowserBridgeProtocol.origin, enabled: true, version: "0.3.6")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: reply) as? [String: Any])
        XCTAssertEqual(object["nonce"] as? String, hello["nonce"] as? String)
        XCTAssertEqual(object["status"] as? String, "ready")
        XCTAssertEqual(object["appVersion"] as? String, "0.3.6")
        XCTAssertEqual(Set(object.keys), ["protocol", "type", "nonce", "appVersion", "bridgeVersion", "status"])
        let disabled = try BrowserBridgeProtocol.response(data, origin: BrowserBridgeProtocol.origin, enabled: false, version: "0.3.6")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: disabled) as? [String: Any])?["status"] as? String, "disabled")
    }
    func testUnknownOriginsProtocolCommandsAndPayloadsAreRejected() throws {
        let valid = try JSONSerialization.data(withJSONObject: hello)
        for origin in ["", "https://example.com", BrowserBridgeProtocol.origin + "path", "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/", BrowserBridgeProtocol.origin + "?host=1"] {
            XCTAssertThrowsError(try BrowserBridgeProtocol.response(valid, origin: origin, enabled: true, version: "0.3.6"))
        }
        for mutation: [String: Any] in [["protocol": 2], ["protocol": true], ["type": "read_history"], ["nonce": "short"], ["nonce": String(repeating: "x", count: 129)], ["nonce": "1234567890abcdef\n"], ["extensionVersion": "0.2\n"], ["contents": "secret"]] {
            var message = hello; message.merge(mutation) { _, next in next }
            XCTAssertThrowsError(try BrowserBridgeProtocol.response(JSONSerialization.data(withJSONObject: message), origin: BrowserBridgeProtocol.origin, enabled: true, version: "0.3.6"))
        }
        XCTAssertThrowsError(try BrowserBridgeProtocol.response(Data(repeating: 32, count: 4097), origin: BrowserBridgeProtocol.origin, enabled: true, version: "0.3.6"))
    }
    func testFramingRejectsOversizedAndTruncatedInputBeforeAllocation() throws {
        let message = try JSONSerialization.data(withJSONObject: hello)
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: BrowserBridgeProtocol.framed(message))
        try pipe.fileHandleForWriting.close()
        XCTAssertEqual(try BrowserBridgeProtocol.read(pipe.fileHandleForReading), message)
        for corrupt in [Data(), Data([5, 0]), Data([10, 0, 0, 0, 123]), Data([0, 0, 0, 0]), Data([255, 255, 255, 127])] {
            let pipe = Pipe(); try pipe.fileHandleForWriting.write(contentsOf: corrupt); try pipe.fileHandleForWriting.close()
            XCTAssertThrowsError(try BrowserBridgeProtocol.read(pipe.fileHandleForReading))
        }
        XCTAssertThrowsError(try BrowserBridgeProtocol.framed(Data(repeating: 1, count: 4097)))
    }
    @MainActor func testLastExchangeCannotSurviveANewPreparationGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("configuration.json"), exchange = root.appendingPathComponent("last-exchange.json")
        try BrowserExtensionFiles.write(BrowserBridgeConfiguration(enabled: true, browser: .arc, generation: "second"), to: config)
        try BrowserExtensionFiles.write(BrowserBridgeExchange(extensionID: BrowserBridgeProtocol.extensionID, extensionVersion: "0.2.0", appVersion: "0.3.6", date: Date(), generation: "first"), to: exchange)
        let model = BrowserExtensionModel(root: root, home: root.appendingPathComponent("test-home"))
        XCTAssertNil(model.exchange, "A late response from the previous preparation is not current")
        try BrowserExtensionFiles.write(BrowserBridgeExchange(extensionID: BrowserBridgeProtocol.extensionID, extensionVersion: "0.2.0", appVersion: "0.3.6", date: Date(), generation: "second"), to: exchange)
        model.refresh(); XCTAssertNotNil(model.exchange)
        try BrowserExtensionFiles.write(BrowserBridgeConfiguration(enabled: false, browser: .arc, generation: "second"), to: config)
        model.refresh(); XCTAssertNil(model.exchange)
    }
    func testPreparationAndRevocationOnlyTouchOwnedFilesInTemporaryHome() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temp) }
        let app = temp.appendingPathComponent("Applications/Une app avec espaces.app")
        let helper = app.appendingPathComponent("Contents/MacOS/EasyPaste")
        try FileManager.default.createDirectory(at: helper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("BrowserExtension")
        let root = temp.appendingPathComponent("our-state"), home = temp.appendingPathComponent("home")
        try BrowserExtensionFiles.prepare(resources: resources, application: app, target: .arc, root: root, home: home)
        XCTAssertTrue(BrowserExtensionFiles.read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))?.enabled == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Extension/popup.js").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Extension/tests").path))
        for folder in BrowserExtensionTarget.arc.registries(home: home) {
            let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(BrowserBridgeProtocol.host + ".json"))) as? [String: Any])
            XCTAssertEqual(manifest["allowed_origins"] as? [String], [BrowserBridgeProtocol.origin])
            XCTAssertEqual(manifest["path"] as? String, helper.path)
        }
        let other = BrowserExtensionTarget.arc.registries(home: home)[0].appendingPathComponent("another.host.json")
        try Data("preserve".utf8).write(to: other)
        let exchange = root.appendingPathComponent("last-exchange.json")
        try BrowserExtensionFiles.write(BrowserBridgeExchange(extensionID: BrowserBridgeProtocol.extensionID, extensionVersion: "0.2.0", appVersion: "0.3.6", date: Date()), to: exchange)
        try BrowserExtensionFiles.disable(root: root, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.path))
        XCTAssertTrue(BrowserExtensionFiles.read(BrowserBridgeConfiguration.self, from: root.appendingPathComponent("configuration.json"))?.enabled == false)
        XCTAssertEqual(try Data(contentsOf: other), Data("preserve".utf8))
        for folder in BrowserExtensionTarget.arc.registries(home: home) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(BrowserBridgeProtocol.host + ".json").path))
        }
        try BrowserExtensionFiles.write(BrowserBridgeExchange(extensionID: BrowserBridgeProtocol.extensionID, extensionVersion: "0.2.0", appVersion: "0.3.6", date: Date()), to: exchange)
        try BrowserExtensionFiles.prepare(resources: resources, application: app, target: .chrome, root: root, home: home)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exchange.path), "A new preparation must require a new hello")
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("configuration.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
}
