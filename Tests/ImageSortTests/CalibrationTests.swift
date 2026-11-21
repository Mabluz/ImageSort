import Testing
import Foundation
import Vision
@testable import ImageSort

/// Kjøres bare manuelt for å justere terskler mot ekte bilder:
///   IMAGESORT_CALIBRATE_DIR=/sti/til/mappe swift test --filter Calibration
@Suite struct Calibration {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["IMAGESORT_CALIBRATE_DIR"] != nil))
    func printDistancesAndScores() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["IMAGESORT_CALIBRATE_DIR"]!)
        let photos = FolderScanner.scan(dir)
        var analyses: [URL: PhotoAnalysis] = [:]
        var prints: [URL: VNFeaturePrintObservation] = [:]
        let start = Date()
        for p in photos {
            let a = try await PhotoAnalyzer.analyze(url: p.url)
            analyses[p.url] = a
            prints[p.url] = PhotoAnalyzer.featurePrint(from: a.featurePrint)
        }
        print("Analyserte \(photos.count) bilder på \(String(format: "%.1f", Date().timeIntervalSince(start))) s")

        let names = photos.map { String($0.fileName.prefix(14)) }
        print("\nAvstander (feature print):")
        print("".padding(toLength: 15, withPad: " ", startingAt: 0) + names.map { $0.padding(toLength: 7, withPad: " ", startingAt: 0) }.joined())
        for (i, a) in photos.enumerated() {
            var row = names[i].padding(toLength: 15, withPad: " ", startingAt: 0)
            for b in photos {
                var d: Float = 0
                if let pa = prints[a.url], let pb = prints[b.url] { try? pa.computeDistance(&d, to: pb) }
                row += String(format: "%-7.2f", d)
            }
            print(row)
        }

        print("\nPer bilde:")
        for p in photos {
            let a = analyses[p.url]!
            print("\(p.fileName): dato=\(p.captureDate) aest=\(a.aesthetics.map { String(format: "%.2f", $0) } ?? "-") skarp=\(Int(a.sharpness)) ansikt=\(a.faceQualities.map { String(format: "%.2f", $0) }) lukket=\(a.eyesClosedCount)")
        }

        let threshold = Float(ProcessInfo.processInfo.environment["IMAGESORT_THRESHOLD"] ?? "") ?? Float(Settings.defaultThreshold)
        let groups = SimilarityGrouper.group(photos: photos, featurePrints: prints, maxGap: Settings.defaultTimeGap, threshold: threshold)
        print("\nGrupper med terskel \(threshold):")
        for g in groups {
            let scores = Ranking.score(g.map { analyses[$0.url]! })
            let line = zip(g, scores).map { "\($0.0.fileName)=\(Int($0.1.total))" }.joined(separator: ", ")
            print(" • \(line)")
        }
    }
}
