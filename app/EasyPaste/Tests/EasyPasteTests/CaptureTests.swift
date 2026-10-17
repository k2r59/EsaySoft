import XCTest
import AppKit
import CryptoKit
import ImageIO
@testable import EasyPaste

final class MediaTests: XCTestCase {
    func testEncryptedMovieAcrossChunkBoundaries() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        defer { try? FileManager.default.removeItem(at: vault.playbackDirectory) }
        for size in [1, MediaVault.chunkSize-1, MediaVault.chunkSize, MediaVault.chunkSize+1, MediaVault.chunkSize*3+71] {
            let data = Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 17) })
            let source = folder.appendingPathComponent("test.mp4"); try data.write(to: source)
            let id = UUID(); XCTAssertEqual(try vault.importVideo(source, id: id), size)
            let encrypted = try Data(contentsOf: vault.mediaURL(id))
            if size > 100 { XCTAssertNil(encrypted.range(of: data.prefix(100))) }
            let output = try vault.videoURL(id)
            XCTAssertEqual(try Data(contentsOf: output), data)
            XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? Int, 0o600)
            try vault.delete(id)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: vault.mediaURL(id).path))
        }
    }
    func testImportIgnoresCachedSizeOfGrowingRecording() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try ClipVault(directory: folder, key: SymmetricKey(size: .bits256))
        defer { try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: vault.playbackDirectory) }
        let source = folder.appendingPathComponent("growing.mp4")
        try Data().write(to: source)
        XCTAssertEqual(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize, 0)
        let data = Data(repeating: 83, count: MediaVault.chunkSize+11)
        let writer = try FileHandle(forWritingTo: source)
        try writer.write(contentsOf: data); try writer.close()
        let id = UUID()
        XCTAssertEqual(try vault.importVideo(source, id: id), data.count)
        XCTAssertEqual(try Data(contentsOf: vault.videoURL(id)), data)
    }
    func testMovieCorruptionTruncationAndWrongIdentityNeverPublishesPlaintext() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let key = SymmetricKey(size: .bits256), id = UUID()
        let source = folder.appendingPathComponent("input.mp4"), cipher = folder.appendingPathComponent("video.enc"), output = folder.appendingPathComponent("output.mp4")
        try Data(repeating: 71, count: MediaVault.chunkSize+83).write(to: source)
        _ = try MediaVault.encrypt(source, to: cipher, id: id, key: key)
        let pristine = try Data(contentsOf: cipher)
        var corrupt = pristine; corrupt[corrupt.count-12] ^= 1
        for damaged in [corrupt, pristine.dropLast(), pristine.prefix(2), pristine + Data([1])] {
            try Data(damaged).write(to: cipher)
            XCTAssertThrowsError(try MediaVault.decrypt(cipher, to: output, id: id, key: key))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasSuffix(".partial") })
        }
        try pristine.write(to: cipher)
        XCTAssertThrowsError(try MediaVault.decrypt(cipher, to: output, id: UUID(), key: key))
        XCTAssertThrowsError(try MediaVault.decrypt(cipher, to: output, id: id, key: SymmetricKey(size: .bits256)))
    }
    func testLegacyClipMigration() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(makeClip("Ancien historique"))) as? [String: Any])
        json.removeValue(forKey: "parentID"); json.removeValue(forKey: "duration")
        let decoded = try JSONDecoder().decode(Clip.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.text, "Ancien historique"); XCTAssertNil(decoded.parentID); XCTAssertNil(decoded.duration)
    }
    func testRetinaCaptureKeepsEveryPixel() {
        XCTAssertEqual(CaptureImage.pixelSize(CGSize(width: 600,height: 400),scale: 2),CGSize(width: 1200,height: 800))
        XCTAssertEqual(CaptureImage.pixelSize(CGSize(width: 600,height: 400),scale: 1),CGSize(width: 600,height: 400))
        XCTAssertEqual(CaptureImage.pixelSize(CGSize(width: 2560,height: 1440),scale: 2),CGSize(width: 5120,height: 2880))
    }
    func testRecordingSizeIsEvenAndBounded() {
        for size in [CGSize(width: 1511,height: 981), CGSize(width: 6016,height: 3384), CGSize(width: 10,height: 1000)] {
            for full in [true,false] {
                let result = RecordingOptions.dimensions(size, scale: 2, fullResolution: full)
                XCTAssertEqual(result.0 % 2, 0); XCTAssertEqual(result.1 % 2, 0)
                XCTAssertGreaterThanOrEqual(min(result.0,result.1),2); XCTAssertLessThanOrEqual(max(result.0,result.1),full ? 3840 : 1920)
            }
        }
    }
}
final class AnnotationTests: XCTestCase {
    func testOpaqueMaskAndCropPreserveOriginal() throws {
        let data = try fixture(), original = try decode(data)
        let mark = AnnotationMark(tool: .redact, start: CGPoint(x: 20,y: 10), end: CGPoint(x: 60,y: 30), color: .coral, width: 4)
        let output = try AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(marks: [mark]))
        let result = try decode(output)
        XCTAssertEqual(result.width,100); XCTAssertEqual(result.height,80)
        let masked = pixel(result, x: 35,y: 20), untouched = pixel(result,x: 80,y: 20)
        XCTAssertLessThan(masked[0],20); XCTAssertLessThan(masked[1],20); XCTAssertLessThan(masked[2],20); XCTAssertEqual(masked[3],255)
        XCTAssertEqual(untouched,pixel(original,x: 80,y: 20))
        let crop = try decode(AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(marks: [mark], crop: CGRect(x: 20,y: 10,width: 40,height: 20))))
        XCTAssertEqual(crop.width,40); XCTAssertEqual(crop.height,20)
        XCTAssertEqual(pixel(crop,x: 10,y: 10), masked)
        XCTAssertEqual(try fixture(),data)
    }
    func testCropUsesTopLeftCoordinatesAndNoopIsPixelIdentical() throws {
        let data = try fixture(), image = try decode(data)
        let unchanged = try decode(AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot()))
        XCTAssertEqual(pixel(image,x: 5,y: 5),pixel(unchanged,x: 5,y: 5))
        XCTAssertEqual(pixel(image,x: 5,y: 70),pixel(unchanged,x: 5,y: 70))
        let crop = try decode(AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(crop: CGRect(x: 0,y: 0,width: 20,height: 20))))
        XCTAssertEqual(pixel(image,x: 5,y: 5),pixel(crop,x: 5,y: 5))
        XCTAssertThrowsError(try AnnotationRenderer.export(data: data, snapshot: AnnotationSnapshot(crop: CGRect(x: 200,y: 0,width: 20,height: 20))))
    }
    func testEveryAnnotationToolProducesVisibleOutput() throws {
        let data = try fixture()
        for tool in [AnnotationTool.arrow,.rectangle,.text,.highlight] {
            let mark = AnnotationMark(tool: tool, start: CGPoint(x: 5,y: 5), end: CGPoint(x: 70,y: 60), color: .white, width: 3, text: "TEST")
            let output = try AnnotationRenderer.export(data: data,snapshot: AnnotationSnapshot(marks: [mark]))
            XCTAssertNotEqual(output,try AnnotationRenderer.export(data: data,snapshot: AnnotationSnapshot()))
        }
    }
    @MainActor func testUndoRedoIncludingCropAndSaveGuard() throws {
        let data = try fixture(), prepared = try AnnotationModel.prepare(data)
        let model = AnnotationModel(data: data,image: prepared.0,size: prepared.1)
        model.commit(AnnotationMark(tool: .arrow,start: .zero,end: CGPoint(x: 20,y: 20),color: .coral,width: 4))
        model.commit(AnnotationMark(tool: .crop,start: .zero,end: CGPoint(x: 50,y: 40),color: .mint,width: 4))
        model.undo(); XCTAssertNil(model.snapshot.crop); XCTAssertEqual(model.snapshot.marks.count,1)
        model.undo(); XCTAssertFalse(model.dirty)
        model.redo(); model.redo(); XCTAssertEqual(model.snapshot.crop?.width,50)
        model.saving = true; model.undo(); XCTAssertNotNil(model.snapshot.crop); XCTAssertEqual(model.undoStates.count,2)
    }
    @MainActor func testSelectionStressClampsAndCompletesOnce() {
        let view = SelectionView(frame: CGRect(x: 0,y: 0,width: 1000,height: 700))
        var results: [CGRect?] = []; view.done = { results.append($0) }
        view.begin(at: CGPoint(x: 100,y: 50))
        for index in 0..<10_000 { view.update(to: CGPoint(x: index % 1200,y: index % 900)) }
        view.finish(at: CGPoint(x: 1500,y: 1200)); view.cancel(); view.finish(at: .zero)
        XCTAssertEqual(results.count,1); XCTAssertEqual(results[0],CGRect(x: 100,y: 50,width: 900,height: 650))
    }
    private func fixture() throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil,width: 100,height: 80,bitsPerComponent: 8,bytesPerRow: 0,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0,green: 0,blue: 1,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: 100,height: 80))
        context.setFillColor(CGColor(red: 1,green: 0,blue: 0,alpha: 1)); context.fill(CGRect(x: 0,y: 40,width: 100,height: 40))
        return try CaptureImage.png(XCTUnwrap(context.makeImage()))
    }
    private func decode(_ data: Data) throws -> CGImage { let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil)); return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil)) }
    private func pixel(_ image: CGImage,x: Int,y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0,count: image.width*image.height*4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress,width: image.width,height: image.height,bitsPerComponent: 8,bytesPerRow: image.width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in: CGRect(x: 0,y: 0,width: image.width,height: image.height))
        }
        let offset = (y*image.width+x)*4; return Array(bytes[offset..<offset+4])
    }
}
@MainActor final class CaptureHistoryTests: XCTestCase {
    func testCaptureAndRevisionAreDurableAdjacentAndIndependent() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try ClipVault(directory: folder,key: SymmetricKey(size: .bits256))
        let history = History(vault: vault,monitor: false,defaults: UserDefaults(suiteName: UUID().uuidString)!)
        defer { history.stopMonitoring(); try? FileManager.default.removeItem(at: folder) }
        let png = DemoArtwork.png()
        let original = try await history.saveImage(png)
        let revision = try await history.saveImage(png,parent: original)
        XCTAssertNotEqual(original.id,revision.id); XCTAssertEqual(revision.parentID,original.id)
        let fullOriginal = try await history.fullClip(original), fullRevision = try await history.fullClip(revision)
        XCTAssertEqual(fullOriginal.imageData,png); XCTAssertEqual(fullRevision.imageData,png)
        let order = ClipQuery().apply(history.clips).map(\.id)
        XCTAssertEqual(order,[original.id,revision.id])
        history.trash(original); await history.flush()
        XCTAssertEqual(ClipQuery().apply(history.clips).map(\.id),[revision.id])
        history.restore(original); await history.flush()
        XCTAssertEqual(ClipQuery().apply(history.clips).map(\.id),[original.id,revision.id])
        let pb = NSPasteboard(name: .init("EasyPaste-capture-test-"+UUID().uuidString)); defer { pb.releaseGlobally() }
        let copied = await history.copy([revision],to: pb); XCTAssertTrue(copied); XCTAssertEqual(pb.data(forType: .png),png)
        await history.flush()
    }
    func testOCRIsImmediatelySearchableAndCopyable() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try ClipVault(directory: folder,key: SymmetricKey(size: .bits256))
        let history = History(vault: vault,monitor: false,defaults: UserDefaults(suiteName: UUID().uuidString)!)
        defer { history.stopMonitoring(); try? FileManager.default.removeItem(at: folder) }
        let clip = try await history.saveOCR("Une idée française\nÀ retrouver")
        XCTAssertEqual(ClipQuery(text: "idee retrouver").apply(history.clips).map(\.id),[clip.id])
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let copied = await history.copy([clip],to: pb); XCTAssertTrue(copied); XCTAssertEqual(pb.string(forType: .string),clip.text)
        do { _ = try await history.saveOCR(" \n "); XCTFail("Empty OCR must fail") } catch { }
    }
}

import AVFoundation
import SwiftUI
final class VideoIntegrationTests: XCTestCase {
    @MainActor func testRealMP4ImportThumbnailCopyAndDelete() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = try ClipVault(directory: folder,key: SymmetricKey(size: .bits256))
        let history = History(vault: vault,monitor: false,defaults: UserDefaults(suiteName: UUID().uuidString)!)
        defer { history.stopMonitoring(); try? FileManager.default.removeItem(at: folder); try? FileManager.default.removeItem(at: vault.playbackDirectory) }
        let source = folder.appendingPathComponent("fixture.mp4")
        try await Self.movie(at: source)
        let originalBytes = try Data(contentsOf: source)
        let clip = try await history.saveVideo(source)
        XCTAssertEqual(clip.kind,.video); XCTAssertNotNil(clip.thumbnail); XCTAssertGreaterThan(clip.duration ?? 0,0)
        XCTAssertEqual(clip.byteCount,originalBytes.count)
        try FileManager.default.removeItem(at: source)
        let materialized = try await history.videoURL(clip)
        XCTAssertEqual(try Data(contentsOf: materialized),originalBytes)
        let asset = AVURLAsset(url: materialized)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count,1)
        // Exercise actual SwiftUI/AppKit view initialization, where VideoPlayer
        // previously aborted the application before a user could press Play.
        for _ in 0..<3 {
            let player = AVPlayer(url: materialized)
            let host = NSHostingView(rootView: NativeVideoPreview(player: player))
            host.frame = CGRect(x: 0,y: 0,width: 640,height: 360)
            host.layoutSubtreeIfNeeded()
            XCTAssertNotNil(player.currentItem)
            player.pause(); player.replaceCurrentItem(with: nil)
        }
        let pb = NSPasteboard(name: .init(UUID().uuidString)); defer { pb.releaseGlobally() }
        let copied = await history.copy([clip],to: pb)
        XCTAssertTrue(copied); XCTAssertEqual(pb.string(forType: .fileURL),materialized.absoluteString)
        history.trash(clip); await history.flush()
        let trashed = try XCTUnwrap(history.clips.first)
        history.permanentlyDelete([trashed]); await history.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: materialized.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.mediaURL(clip.id).path))
    }
    private static func movie(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url,fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video,outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,AVVideoWidthKey: 128,AVVideoHeightKey: 72])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,kCVPixelBufferWidthKey as String: 128,kCVPixelBufferHeightKey as String: 72])
        writer.add(input); XCTAssertTrue(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for index in 0..<12 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            var pixel: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pixel)
            let buffer = try XCTUnwrap(pixel)
            CVPixelBufferLockBaseAddress(buffer,[])
            memset(CVPixelBufferGetBaseAddress(buffer),Int32(index*20),CVPixelBufferGetBytesPerRow(buffer)*72)
            CVPixelBufferUnlockBaseAddress(buffer,[])
            XCTAssertTrue(adaptor.append(buffer,withPresentationTime: CMTime(value: Int64(index),timescale: 12)))
        }
        input.markAsFinished(); await writer.finishWriting(); XCTAssertEqual(writer.status,.completed)
    }
}
