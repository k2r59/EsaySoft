import AppKit
import XCTest
@testable import EasyPaste

final class ArrowRenderingTests: XCTestCase {
    func testFilledArrowNeverPaintsBeyondItsTipInAnyDirection() throws {
        for width: CGFloat in [2, 8, 16] {
            for step in 0..<8 {
                let angle = CGFloat(step) * .pi / 4
                let start = CGPoint(x: 128, y: 128)
                let end = CGPoint(x: 128 + 80*cos(angle), y: 128 + 80*sin(angle))
                let bytes = try render(start: start, end: end, width: width)
                var painted = 0
                for y in 0..<256 { for x in 0..<256 where bytes[(y*256+x)*4+3] > 32 {
                    painted += 1
                    let projection = (CGFloat(x)+0.5-end.x)*cos(angle) + (CGFloat(y)+0.5-end.y)*sin(angle)
                    XCTAssertLessThanOrEqual(projection, 1, "Shaft protrudes: width \(width), direction \(step), point \(x),\(y)")
                } }
                XCTAssertGreaterThan(painted, 40)
            }
        }
    }

    func testShortArrowsDoNotTurnIntoRoundCapsBeyondTheTip() throws {
        for width: CGFloat in [2, 8, 16] {
            for length: CGFloat in [1, 4, 12] {
                let bytes = try render(start: CGPoint(x: 100, y: 128), end: CGPoint(x: 100+length, y: 128), width: width)
                for y in 0..<256 { for x in Int(ceil(101+length))..<256 {
                    XCTAssertEqual(bytes[(y*256+x)*4+3], 0)
                } }
            }
        }
    }

    func testZeroLengthIsEmptyAndAllHeadStylesStillRender() throws {
        let zero = try render(start: CGPoint(x: 128, y: 128), end: CGPoint(x: 128, y: 128), width: 8)
        XCTAssertTrue(zero.allSatisfy { $0 == 0 })
        for style in [AnnotationArrowhead.open, .filled, .dot] {
            let bytes = try render(start: CGPoint(x: 40, y: 128), end: CGPoint(x: 210, y: 128), width: 8, style: style)
            XCTAssertTrue(bytes.contains { $0 != 0 })
            XCTAssertGreaterThan(bytes[(128*256+100)*4+3], 0)
        }
    }

    private func render(start: CGPoint, end: CGPoint, width: CGFloat, style: AnnotationArrowhead = .filled) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 256*256*4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 256*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let mark = AnnotationMark(tool: .arrow, start: start, end: end, color: .coral, width: width, arrowhead: style)
            AnnotationRenderer.draw([mark], in: context, size: CGSize(width: 256, height: 256))
        }
        return bytes
    }
}
