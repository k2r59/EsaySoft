import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import EasyPaste

final class ClipPresentationTests: XCTestCase {
    private func clip(_ text: String, title: String? = nil) -> Clip {
        let payload = ClipPayload(representations: [[.init(type: "public.utf8-plain-text", data: Data(text.utf8))]])
        return Clip(title: title ?? String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(90)), text: text, source: "QA", sourceID: "test", kind: .text, fingerprint: Clip.fingerprint(payload), payload: payload)
    }
    func testGeneratedTextTitleIsNotRepeatedButRealSnippetTitleIsKept() {
        for text in ["Une copie très simple", "  Bonjour\n\nle monde  ", "# Titre\nUn article Markdown", String(repeating: "Mot et emoji 🧑🏽‍💻 ", count: 100)] {
            let value = clip(text)
            XCTAssertNil(value.cardTitle)
            XCTAssertEqual(value.text, text)
            XCTAssertEqual(value.payload.representations[0][0].data, Data(text.utf8))
        }
        XCTAssertEqual(clip("Bonjour Hervé,\nVoici les informations.", title: "Réponse client").cardTitle, "Réponse client")
        XCTAssertNil(clip("", title: "").cardTitle)
        XCTAssertEqual(clip("", title: "Sans contenu").cardTitle, "Sans contenu")
    }
    func testRetinaDimensionsComeFromOriginalAndSurviveMetadataAndReload() throws {
        let image = try ImageQualityTests.fixture(width: 2400, height: 1600)
        let data = try CaptureImage.png(image)
        let payload = ClipPayload(representations: [[.init(type: NSPasteboard.PasteboardType.png.rawValue, data: data)]])
        var value = Clip(title: "Capture d’écran", text: "", source: "EasyPaste", sourceID: "app.easypaste.mac", kind: .image, fingerprint: Clip.fingerprint(payload), payload: payload)
        value.prepareThumbnail()
        XCTAssertEqual(value.imageMetadata?.width, 2400)
        XCTAssertEqual(value.imageMetadata?.height, 1600)
        XCTAssertEqual(value.imageMetadata?.bytes, data.count)
        XCTAssertEqual(value.imageMetadata?.dimensions, "2400 × 1600 px")
        XCTAssertNil(value.cardTitle)
        let thumb = try XCTUnwrap(value.thumbnail)
        XCTAssertEqual(ClipImageMetadata.read(thumb)?.width, 640)
        XCTAssertEqual(value.metadata().imageMetadata, value.imageMetadata)
        XCTAssertEqual(value.imageData, data, "Displaying dimensions never recompresses the original")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = try ClipVault(directory: root, key: SymmetricKey(size: .bits256))
        try vault.save(value)
        let loaded = try XCTUnwrap(vault.load(metadataOnly: true).first)
        XCTAssertEqual(loaded.imageMetadata, value.imageMetadata)
        var legacy = value; legacy.imageMetadata = nil; try vault.save(legacy)
        XCTAssertEqual(try vault.load(metadataOnly: true).first?.imageMetadata, value.imageMetadata, "Old histories get header metadata without using the thumbnail")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "imageMetadata")
        XCTAssertNoThrow(try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json)))
    }
    func testOrientationAndCropMetadataFollowDisplayedPixels() throws {
        let image = try ImageQualityTests.fixture(width: 800, height: 600)
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(ClipImageMetadata.read(jpeg as Data)?.dimensions, "600 × 800 px")
        let original = try CaptureImage.png(image)
        let cropped = try AnnotationRenderer.export(data: original, snapshot: AnnotationSnapshot(crop: CGRect(x: 50, y: 25, width: 401, height: 301)))
        XCTAssertEqual(ClipImageMetadata.read(cropped)?.dimensions, "401 × 301 px")
        for invalid in [Data(), Data("not a raster".utf8), Data("<svg width='200' height='50'/>".utf8)] {
            XCTAssertNil(ClipImageMetadata.read(invalid))
        }
    }
    @MainActor func testAnnotationDimensionLabelMatchesFractionalPixelCrop() throws {
        let image = try ImageQualityTests.fixture(width: 800, height: 600)
        let original = try CaptureImage.png(image)
        let model = AnnotationModel(data: original, image: image, size: CGSize(width: 800, height: 600))
        model.snapshot.crop = CGRect(x: 50.25, y: 25.5, width: 400.1, height: 300.2)
        let metadata = try XCTUnwrap(ClipImageMetadata.read(AnnotationRenderer.export(data: original, snapshot: model.snapshot)))
        XCTAssertEqual(model.outputSize.width, CGFloat(metadata.width))
        XCTAssertEqual(model.outputSize.height, CGFloat(metadata.height))
        XCTAssertEqual(metadata.dimensions, "401 × 301 px")
    }
}
