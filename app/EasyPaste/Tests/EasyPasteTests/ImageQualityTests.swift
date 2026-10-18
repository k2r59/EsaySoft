import XCTest
import AppKit
import ImageIO
import CoreVideo
import CryptoKit
import ScreenCaptureKit
@testable import EasyPaste

final class ImageQualityTests: XCTestCase {
    func testFractionalSelectionsKeepWholePixelsOnBothScreens() throws {
        for scale: CGFloat in [1, 2] {
            for origin: CGFloat in [-5120.25, -0.5, 0, 0.25, 5120.5] {
                let selection = CGRect(x: origin, y: 10.25, width: 751.5, height: 270.75)
                let area = try CaptureImage.pixelAligned(selection, scale: scale)
                XCTAssertTrue(area.contains(selection))
                for edge in [area.minX, area.minY, area.maxX, area.maxY] {
                    XCTAssertEqual(edge * scale, (edge * scale).rounded())
                }
                XCTAssertLessThan(area.width-selection.width, 2/scale)
                XCTAssertEqual(try CaptureImage.pixelAligned(area, scale: scale), area)
            }
        }
    }
    func testInvalidAndOversizeSelectionsFailBeforeAllocation() {
        for rect in [CGRect(x: 0,y: 0,width: 0,height: 4), CGRect(x: 0,y: 0,width: CGFloat.infinity,height: 4), CGRect(x: CGFloat.nan,y: 0,width: 4,height: 4), CGRect(x: 0,y: 0,width: 10_000,height: 6000)] {
            XCTAssertThrowsError(try CaptureImage.pixelAligned(rect, scale: 1))
        }
        XCTAssertThrowsError(try CaptureImage.configuration(size: CGSize(width: 5120,height: 2880), scale: 2))
    }
    func testEveryCaptureUsesFullColorAndNativeResolution() throws {
        for scale: CGFloat in [1,2] {
            let config = try CaptureImage.configuration(size: CGSize(width: 752,height: 271), scale: scale)
            XCTAssertEqual(config.width, Int(752*scale)); XCTAssertEqual(config.height, Int(271*scale))
            XCTAssertEqual(config.pixelFormat, kCVPixelFormatType_32BGRA)
            XCTAssertEqual(config.captureResolution, .best)
            XCTAssertFalse(config.showsCursor); XCTAssertFalse(config.scalesToFit)
        }
    }
    func testPNGPreservesFineLinesAt1xAnd2x() throws {
        for (width,height) in [(752,271), (1504,542), (5120,2880)] {
            try autoreleasepool {
                let image = try Self.fixture(width:width,height:height)
                let data = try CaptureImage.png(image)
                let (decoded,size) = try ImageRaster.decode(data)
                XCTAssertEqual(size, CGSize(width:width,height:height))
                XCTAssertEqual(Self.pixels(decoded), Self.pixels(image), "PNG must preserve every pixel, including single-pixel lines")
            }
        }
    }
    func testPreviewFitNeverUpscalesSmallImagesAndNativeDecodeStaysExact() throws {
        let original = try Self.fixture(width:752,height:271)
        let data = try CaptureImage.png(original)
        for scale: CGFloat in [1,2] {
            let fitted = ImageRaster.fittedSize(pixels:CGSize(width:752,height:271),available:CGSize(width:600,height:360),displayScale:scale)
            XCTAssertLessThanOrEqual(fitted.width*scale,752)
            XCTAssertLessThanOrEqual(fitted.height*scale,271)
        }
        let (native,_) = try ImageRaster.decode(data,maxPixels:1200)
        XCTAssertEqual(native.width,752); XCTAssertEqual(Self.pixels(native),Self.pixels(original))
        let (small,size) = try ImageRaster.decode(data,maxPixels:320)
        XCTAssertEqual(size.width,752); XCTAssertEqual(small.width,320)
        XCTAssertEqual(try ImageRaster.decode(data).0.width,752)
    }
    func testCorruptDataIsRejected() {
        for data in [Data(), Data("not an image".utf8), Data([137,80,78,71])] {
            XCTAssertThrowsError(try ImageRaster.decode(data))
        }
    }
    func testAnnotationsKeepUntouchedPixelsAndCropDoesNotRescale() throws {
        let original = try Self.fixture(width:1504,height:542)
        let data = try CaptureImage.png(original)
        let (noop,_) = try ImageRaster.decode(AnnotationRenderer.export(data:data,snapshot:AnnotationSnapshot()))
        XCTAssertEqual(Self.pixels(noop),Self.pixels(original))
        let crop = CGRect(x: 251,y: 31,width: 401,height: 301)
        let (cropped,_) = try ImageRaster.decode(AnnotationRenderer.export(data:data,snapshot:AnnotationSnapshot(crop:crop)))
        XCTAssertEqual(cropped.width,401); XCTAssertEqual(cropped.height,301)
        XCTAssertEqual(Self.pixels(cropped),Self.pixels(try XCTUnwrap(original.cropping(to:crop))))
        let mark = AnnotationMark(tool:.arrow,start:CGPoint(x:40,y:20),end:CGPoint(x:120,y:80),color:.coral,width:4)
        let (marked,_) = try ImageRaster.decode(AnnotationRenderer.export(data:data,snapshot:AnnotationSnapshot(marks:[mark])))
        let untouched = CGRect(x:250,y:0,width:1254,height:542)
        XCTAssertEqual(Self.pixels(try XCTUnwrap(marked.cropping(to:untouched))),Self.pixels(try XCTUnwrap(original.cropping(to:untouched))))
        XCTAssertNotEqual(Self.pixels(marked),Self.pixels(original))
    }
    func testWideGamutColorProfileSurvivesAnnotation() throws {
        let original = try Self.fixture(width:500,height:300,space:CGColorSpace(name:CGColorSpace.displayP3)!)
        let data = try CaptureImage.png(original)
        let mark = AnnotationMark(tool:.rectangle,start:CGPoint(x:20,y:20),end:CGPoint(x:80,y:80),color:.mint,width:3)
        let (result,_) = try ImageRaster.decode(AnnotationRenderer.export(data:data,snapshot:AnnotationSnapshot(marks:[mark])))
        XCTAssertEqual(result.colorSpace?.name,original.colorSpace?.name)
        let area = CGRect(x:150,y:0,width:350,height:300)
        XCTAssertEqual(Self.pixels(try XCTUnwrap(result.cropping(to:area))),Self.pixels(try XCTUnwrap(original.cropping(to:area))))
    }
    func testMixedDensityCompositionPreservesNativePixelsAndSharpEdges() throws {
        let one = try Self.fixture(width:100,height:50), two = try Self.fixture(width:200,height:100)
        let combined = try CaptureImage.composite([(one,CGRect(x:0,y:0,width:200,height:100)),(two,CGRect(x:200,y:0,width:200,height:100))],width:400,height:100)
        let right = try XCTUnwrap(combined.cropping(to:CGRect(x:200,y:0,width:200,height:100)))
        XCTAssertEqual(Self.pixels(right),Self.pixels(two))
        let pixels = Self.pixels(combined), source = Self.pixels(one)
        for y in 0..<100 {
            for x in 0..<200 {
                let offset = (y*400+x)*4, original = ((y/2)*100+x/2)*4
                XCTAssertEqual(pixels[offset..<offset+4],source[original..<original+4])
            }
        }
        XCTAssertThrowsError(try CaptureImage.composite([],width:Int.max,height:100))
    }
    @MainActor func testAnnotationCanvasDoesNotEnlargeOrShiftNativePixels() throws {
        let data = try CaptureImage.png(Self.fixture(width:752,height:271))
        let prepared = try AnnotationModel.prepare(data)
        let model = AnnotationModel(data:data,image:prepared.0,size:prepared.1)
        let view = AnnotationCanvasView(model:model)
        view.frame = CGRect(x:0,y:0,width:1021,height:701)
        XCTAssertEqual(view.imageRect.size,CGSize(width:752,height:271))
        XCTAssertEqual(view.imageRect.minX,view.imageRect.minX.rounded())
        XCTAssertEqual(view.imageRect.minY,view.imageRect.minY.rounded())
    }
    static func fixture(width:Int,height:Int,space:CGColorSpace = CGColorSpace(name:CGColorSpace.sRGB)!) throws -> CGImage {
        let c = try XCTUnwrap(CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        c.setShouldAntialias(false)
        c.setFillColor(CGColor(gray:0.1,alpha:1)); c.fill(CGRect(x:0,y:0,width:width,height:height))
        for x in stride(from:0,to:width,by:3) {
            c.setFillColor(CGColor(red:CGFloat(x % 255)/255,green:1,blue:0.8,alpha:1))
            c.fill(CGRect(x:x,y:0,width:1,height:height))
        }
        for y in stride(from:0,to:height,by:7) {
            c.setFillColor(CGColor(gray:1,alpha:1)); c.fill(CGRect(x:0,y:y,width:width,height:1))
        }
        return try XCTUnwrap(c.makeImage())
    }
    static func pixels(_ image:CGImage)->Data {
        let c = CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:image.colorSpace ?? CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.interpolationQuality = .none; c.setBlendMode(.copy); c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return Data(bytes:c.data!,count:image.width*image.height*4)
    }
}

@MainActor final class ImagePipelineTests: XCTestCase {
    func testOriginalSurvivesStorageCopyDragAndRepeatedPreview() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("EasyPaste-quality-"+UUID().uuidString)
        let vault = try ClipVault(directory:folder,key:SymmetricKey(size:.bits256))
        let history = History(vault:vault,monitor:false,defaults:UserDefaults(suiteName:UUID().uuidString)!)
        let pb = NSPasteboard(name:.init("EasyPaste-quality-"+UUID().uuidString))
        defer { history.stopMonitoring(); pb.releaseGlobally(); try? FileManager.default.removeItem(at:folder) }
        let data = try await Task.detached { try CaptureImage.png(ImageQualityTests.fixture(width:5120,height:2880)) }.value
        let clip = try await history.saveImage(data)
        XCTAssertTrue(clip.payload.representations.isEmpty)
        for _ in 0..<3 {
            let full = try await history.fullClip(clip)
            XCTAssertEqual(full.imageData,data)
            let copied = await history.copy([clip],to:pb)
            XCTAssertTrue(copied); XCTAssertEqual(pb.data(forType:.png),data)
            let read = try XCTUnwrap(ClipboardReader.read(pb,source:"QA",sourceID:"quality.test",exclusions:[]))
            XCTAssertEqual(read.imageData,data)
            let dims = try await Task.detached { try ImageRaster.decode(data,maxPixels:1200).1 }.value
            XCTAssertEqual(dims,CGSize(width:5120,height:2880))
        }
        let provider = DragProvider.make(clip,history:history)
        let dragged:Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier:"public.png") { data,error in
                if let data { continuation.resume(returning:data) } else { continuation.resume(throwing:error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        XCTAssertEqual(dragged,data)
        await history.flush()
    }
    func testLargeImageWorkLeavesMainActorResponsive() async throws {
        var ticks:[Double] = []
        let clock = ContinuousClock()
        let heartbeat = Task { @MainActor in
            while !Task.isCancelled {
                let start = clock.now
                do { try await Task.sleep(for:.milliseconds(16)) } catch { return }
                ticks.append(Double((clock.now-start).components.attoseconds)/1e18 + Double((clock.now-start).components.seconds))
            }
        }
        defer { heartbeat.cancel() }
        let start = clock.now
        try await Task.detached(priority:.userInitiated) {
            for _ in 0..<3 {
                try autoreleasepool {
                    let data = try CaptureImage.png(ImageQualityTests.fixture(width:5120,height:2880))
                    _ = try ImageRaster.decode(data,maxPixels:1200)
                    let crop = CGRect(x:100,y:100,width:3000,height:1800)
                    _ = try AnnotationRenderer.export(data:data,snapshot:AnnotationSnapshot(crop:crop))
                }
            }
        }.value
        XCTAssertGreaterThan(ticks.count,10)
        let worst = ticks.max() ?? 0
        print("QUALITY_BENCHMARK three_5k_cycles=\(clock.now-start) main_actor_max_interval_ms=\(worst*1000) heartbeats=\(ticks.count)")
        XCTAssertLessThan(worst,0.5,"Heavy ImageIO work must not monopolize the main actor")
    }
}
