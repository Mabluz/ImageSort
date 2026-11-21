import Foundation
import Vision
import CoreGraphics

enum AnalyzerError: Error { case cannotDecode(URL) }

/// Kjører Apple Vision lokalt på ett bilde.
enum PhotoAnalyzer {
    static let analysisSize = 1024

    static func analyze(url: URL) async throws -> PhotoAnalysis {
        guard let cg = ImageLoader.cgImage(url: url, maxPixel: analysisSize) else {
            throw AnalyzerError.cannotDecode(url)
        }
        var result = PhotoAnalysis()

        let featureRequest = VNGenerateImageFeaturePrintRequest()
        let faceQualityRequest = VNDetectFaceCaptureQualityRequest()
        let landmarksRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([featureRequest, faceQualityRequest, landmarksRequest])

        if let fp = featureRequest.results?.first {
            result.featurePrint = try? NSKeyedArchiver.archivedData(withRootObject: fp, requiringSecureCoding: true)
        }

        let minFace = 0.05 // ignorer små ansikter i bakgrunnen
        result.faceQualities = (faceQualityRequest.results ?? [])
            .filter { $0.boundingBox.width >= minFace }
            .compactMap { $0.faceCaptureQuality }

        let imgW = Double(cg.width), imgH = Double(cg.height)
        for face in landmarksRequest.results ?? [] where face.boundingBox.width >= minFace {
            guard let lm = face.landmarks else { continue }
            let box = face.boundingBox
            let open = [lm.leftEye, lm.rightEye].compactMap { region -> Double? in
                guard let region else { return nil }
                return eyeOpenness(region.normalizedPoints, faceW: box.width * imgW, faceH: box.height * imgH)
            }
            if !open.isEmpty, open.allSatisfy({ $0 < 0.16 }) {
                result.eyesClosedCount += 1
            }
        }

        result.sharpness = Sharpness.laplacianVariance(cg)

        if let aest = try? await CalculateImageAestheticsScoresRequest().perform(on: cg) {
            result.aesthetics = aest.overallScore
            result.isUtility = aest.isUtility
        }
        return result
    }

    /// Høyde/bredde-forhold for øyekonturen i piksler.
    static func eyeOpenness(_ points: [CGPoint], faceW: Double, faceH: Double) -> Double? {
        guard points.count >= 4 else { return nil }
        let xs = points.map { Double($0.x) * faceW }
        let ys = points.map { Double($0.y) * faceH }
        let w = (xs.max()! - xs.min()!)
        guard w > 0 else { return nil }
        return (ys.max()! - ys.min()!) / w
    }

    static func featurePrint(from data: Data?) -> VNFeaturePrintObservation? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }
}

enum Sharpness {
    /// Varians av Laplace-filter på et 512px gråtonebilde.
    static func laplacianVariance(_ image: CGImage) -> Double {
        let maxSide = 512.0
        let scale = min(1, maxSide / Double(max(image.width, image.height)))
        let w = max(3, Int(Double(image.width) * scale))
        let h = max(3, Int(Double(image.height) * scale))
        var pixels = [UInt8](repeating: 0, count: w * h)
        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(
                data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return 0 }
        return laplacianVariance(gray: pixels, width: w, height: h)
    }

    static func laplacianVariance(gray p: [UInt8], width w: Int, height h: Int) -> Double {
        var sum = 0.0, sumSq = 0.0
        var n = 0.0
        for y in 1..<(h - 1) {
            let row = y * w
            for x in 1..<(w - 1) {
                let i = row + x
                let v = Double(p[i - w]) + Double(p[i + w]) + Double(p[i - 1]) + Double(p[i + 1]) - 4 * Double(p[i])
                sum += v; sumSq += v * v; n += 1
            }
        }
        guard n > 0 else { return 0 }
        let mean = sum / n
        return sumSq / n - mean * mean
    }
}
