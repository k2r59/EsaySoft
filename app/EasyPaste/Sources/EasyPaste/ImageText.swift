import Foundation
import Vision
import ImageIO

enum ImageText {
    static func recognize(_ data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2600, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate; request.recognitionLanguages = ["fr-FR", "en-US"]; request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let fragments = (request.results ?? []).compactMap { observation -> RecognizedTextLayout.Fragment? in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            let box = observation.boundingBox
            return .init(text: text, bounds: CGRect(x: box.minX * CGFloat(cg.width), y: box.minY * CGFloat(cg.height),
                width: box.width * CGFloat(cg.width), height: box.height * CGFloat(cg.height)))
        }
        return RecognizedTextLayout.render(fragments)
    }
}
