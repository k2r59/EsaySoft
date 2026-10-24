import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import EasyShoot

final class AnnotationBackdropTests:XCTestCase {
    private func image(_ width:Int=320,_ height:Int=240,draw:(CGContext)->Void = {_ in})->CGImage {
        let c=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setFillColor(CGColor(gray:1,alpha:1));c.fill(CGRect(x:0,y:0,width:width,height:height));draw(c);return c.makeImage()!
    }
    private func pixels(_ image:CGImage)->[UInt8] {
        let c=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        return Array(UnsafeBufferPointer(start:c.data!.assumingMemoryBound(to:UInt8.self),count:image.width*image.height*4))
    }
    func testNoBackdropIsPixelIdenticalAndDoesNotAllocateASecondRaster() throws {
        let original=image();let result=try BackdropRenderer.compose(original,style:AnnotationBackdrop())
        XCTAssertTrue(original === result)
        let exported=try AnnotationRaster.decode(AnnotationRenderer.export(data:AnnotationRaster.png(original),snapshot:AnnotationSnapshot())).0
        XCTAssertEqual(pixels(exported),pixels(original))
    }
    func testEveryRatioAndAlignmentKeepsOriginalImageDimensions() {
        for ratio in AnnotationBackdrop.ratios { for alignment in 0..<9 {
            var style=AnnotationBackdrop();style.background="lagoon";style.ratio=ratio;style.alignment=alignment;style.padding=40;style.inset=12
            let layout=style.layout(for:CGSize(width:1920,height:1080))
            XCTAssertEqual(layout.image.size,CGSize(width:1920,height:1080))
            XCTAssertGreaterThanOrEqual(layout.card.minX,39);XCTAssertGreaterThanOrEqual(layout.card.minY,39)
            XCTAssertGreaterThanOrEqual(layout.size.width-layout.card.maxX,39);XCTAssertGreaterThanOrEqual(layout.size.height-layout.card.maxY,39)
            if ratio != "Auto" {let p=ratio.split(separator:":").map{Double($0)!};XCTAssertEqual(layout.size.width/layout.size.height,p[0]/p[1],accuracy:0.002)}
        } }
    }
    func testAsymmetricAutoBalanceUsesTopLeftCoordinatesAndIncludesAnnotations() {
        // Quartz y=170 corresponds to the top of this source; do not vertically flip the crop.
        let source=image { c in c.setFillColor(CGColor(gray:0,alpha:1));c.fill(CGRect(x:30,y:170,width:80,height:40)) }
        let bounds=BackdropRenderer.contentBounds(source)
        XCTAssertLessThan(bounds.minY,0.15);XCTAssertGreaterThan(bounds.minY,0.08)
        XCTAssertGreaterThan(bounds.maxY,0.29);XCTAssertLessThan(bounds.maxY,0.34)
        var snapshot=AnnotationSnapshot();snapshot.backdrop.background="lagoon";snapshot.backdrop.autoBalance=true
        snapshot.marks=[AnnotationMark(tool:.rectangle,start:CGPoint(x:230,y:180),end:CGPoint(x:300,y:220),color:.coral,width:2)]
        let crop=AnnotationRenderer.cropRect(snapshot:snapshot,size:CGSize(width:320,height:240),balanced:bounds)!
        XCTAssertTrue(crop.contains(CGPoint(x:300,y:220)))
        snapshot.crop=CGRect(x:0,y:0,width:120,height:80)
        XCTAssertEqual(AnnotationRenderer.cropRect(snapshot:snapshot,size:CGSize(width:320,height:240),balanced:bounds),snapshot.crop)
    }
    func testNativePixelsSurviveBorderShadowAndGradientExport() throws {
        let source=image(1200,800) { c in
            c.setFillColor(CGColor(srgbRed:0.9,green:0.2,blue:0.1,alpha:1));c.fill(CGRect(x:45,y:60,width:750,height:240))
            c.setFillColor(CGColor(gray:0,alpha:1));for x in stride(from:80,to:1100,by:2) {c.fill(CGRect(x:x,y:400,width:1,height:200))}
        }
        var style=AnnotationBackdrop();style.background="lagoon";style.padding=80;style.inset=10;style.shadow=50;style.corners=25
        let layout=style.layout(for:CGSize(width:1200,height:800)),result=try BackdropRenderer.compose(source,style:style)
        XCTAssertEqual(result.width,1380);XCTAssertEqual(result.height,980)
        let crop=CGRect(x:layout.image.minX+40,y:layout.size.height-layout.image.maxY+40,width:1120,height:720)
        XCTAssertEqual(pixels(result.cropping(to:crop)!),pixels(source.cropping(to:CGRect(x:40,y:40,width:1120,height:720))!))
    }
    func testMalformedStyleCannotCreateInfiniteCanvas() throws {
        var style=AnnotationBackdrop();style.background="lagoon";style.padding = .nan;style.inset = .infinity;style.corners = .nan;style.shadow = .infinity;style.ratio="1:1e-308";style.alignment=Int.max
        let result=try BackdropRenderer.compose(image(),style:style)
        XCTAssertEqual(result.width,448);XCTAssertEqual(result.height,368)
    }
    func testTransparentRoundedCornerAndOpaqueRedaction() throws {
        var snapshot=AnnotationSnapshot();snapshot.backdrop.background="solid-ff0000";snapshot.backdrop.padding=20;snapshot.backdrop.corners=40;snapshot.backdrop.shadow=0
        snapshot.marks=[AnnotationMark(tool:.redact,start:CGPoint(x:50,y:60),end:CGPoint(x:100,y:100),color:.mint,width:4)]
        let result=try AnnotationRaster.decode(AnnotationRenderer.export(data:AnnotationRaster.png(image()),snapshot:snapshot)).0
        let b=pixels(result)
        let corner=(21*result.width+21)*4
        XCTAssertGreaterThan(b[corner],240);XCTAssertLessThan(b[corner+1],10)
        let redacted=((20+80)*result.width+20+75)*4
        XCTAssertLessThan(b[redacted],20);XCTAssertEqual(b[redacted+3],255)
    }
    @MainActor func testBackgroundSliderAndCustomImageUndoRedo() throws {
        let source=image(),data=try AnnotationRaster.png(source),model=AnnotationModel(data:data,image:source,size:CGSize(width:320,height:240))
        var style=AnnotationBackdrop();style.background="custom"
        model.setBackground(source,style:style)
        model.beginStyleEdit()
        for p in 20...100 {style.padding=Double(p);model.changeBackdrop(style)}
        model.endStyleEdit()
        XCTAssertEqual(model.undoStates.count,2)
        model.undo();XCTAssertEqual(model.snapshot.backdrop.padding,64)
        model.undo();XCTAssertNil(model.customBackground);XCTAssertFalse(model.dirty)
        model.redo();XCTAssertTrue(model.customBackground === source)
        model.redo();XCTAssertEqual(model.snapshot.backdrop.padding,100)
    }
    func testCurvedArrowCanBeSelectedOnItsCurve() {
        let mark=AnnotationMark(tool:.arrow,start:CGPoint(x:20,y:100),end:CGPoint(x:220,y:100),color:.coral,width:3,arrowhead:.curved)
        XCTAssertTrue(mark.contains(CGPoint(x:120,y:75),tolerance:4))
        XCTAssertFalse(mark.contains(CGPoint(x:120,y:100),tolerance:4))
    }
    func testOrientedPhotoPreviewAndExportHaveMatchingDimensions() throws {
        let data=NSMutableData(),destination=CGImageDestinationCreateWithData(data,UTType.tiff.identifier as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image(320,240),[kCGImagePropertyOrientation:6] as CFDictionary);XCTAssertTrue(CGImageDestinationFinalize(destination))
        let preview=try AnnotationRaster.decode(data as Data,maxPixels:160),native=try AnnotationRaster.decode(data as Data)
        XCTAssertEqual(preview.1,CGSize(width:240,height:320));XCTAssertEqual(native.1,preview.1)
        XCTAssertEqual(native.0.width,240);XCTAssertEqual(native.0.height,320);XCTAssertEqual(preview.0.width,120)
    }
    @MainActor func testDragProviderExportsAnnotatedPNGAtNativeResolution() async throws {
        let source=image(),data=try AnnotationRaster.png(source),model=AnnotationModel(data:data,image:source,size:CGSize(width:320,height:240))
        model.commit(AnnotationMark(tool:.rectangle,start:CGPoint(x:20,y:30),end:CGPoint(x:200,y:160),color:.coral,width:4))
        var style=AnnotationBackdrop();style.background="lagoon";style.padding=40;model.changeBackdrop(style)
        let provider=AnnotationActions(model:model).provider()
        let output:Data=try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier:UTType.png.identifier) { data,error in
                if let data {continuation.resume(returning:data)} else {continuation.resume(throwing:error ?? AnnotationRaster.Failure.message("Données absentes"))}
            }
        }
        let raster=try AnnotationRaster.decode(output).0
        XCTAssertEqual(raster.width,400);XCTAssertEqual(raster.height,320)
        XCTAssertEqual(output,try AnnotationRenderer.export(data:data,snapshot:model.snapshot))
    }
    @MainActor func testBackgroundPreviewDoesNotCreateFullSizeBitmapsWhileSliding() throws {
        let source=image(3840,2160),data=try AnnotationRaster.png(source),model=AnnotationModel(data:data,image:source,size:CGSize(width:3840,height:2160))
        let view=AnnotationCanvasView(model:model);view.frame=CGRect(x:0,y:0,width:800,height:600)
        var style=AnnotationBackdrop();style.background="lagoon";model.changeBackdrop(style)
        let bitmap=try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in:view.bounds))
        let start=CFAbsoluteTimeGetCurrent()
        model.beginStyleEdit()
        for value in stride(from:0,through:300,by:10) {
            style.padding=Double(value);model.changeBackdrop(style)
            view.cacheDisplay(in:view.bounds,to:bitmap)
            XCTAssertTrue(model.image === source);XCTAssertNil(model.nativeImage)
        }
        model.endStyleEdit()
        print("Annotation preview: 31 draws \(Int((CFAbsoluteTimeGetCurrent()-start)*1000)) ms, \(bitmap.pixelsWide)×\(bitmap.pixelsHigh) preview surface")
        XCTAssertEqual(model.undoStates.count,2)
    }

}
