import Foundation

/// Gjør rå analyser om til gruppe-relative scorer 0–100.
enum Ranking {
    static func score(_ items: [PhotoAnalysis]) -> [PhotoScore] {
        guard !items.isEmpty else { return [] }
        let maxSharp = items.map(\.sharpness).max() ?? 0
        let faceMeans = items.map { $0.faceQualities.isEmpty ? nil : Double($0.faceQualities.reduce(0, +)) / Double($0.faceQualities.count) }
        let maxFace = faceMeans.compactMap { $0 }.max() ?? 0
        let groupHasFaces = maxFace > 0
        let aestNorms = items.map { a -> Double in a.aesthetics.map { (Double($0) + 1) / 2 } ?? 0.5 }
        let maxAest = aestNorms.max() ?? 0

        return items.indices.map { i in
            let a = items[i]
            var reasons: [String] = []
            let sharpRel = maxSharp > 0 ? a.sharpness / maxSharp : 1
            let aest = aestNorms[i]

            var total: Double
            if groupHasFaces {
                let faceRel = (faceMeans[i] ?? 0) / maxFace
                total = 100 * (0.35 * aest + 0.35 * sharpRel + 0.30 * faceRel)
                if faceMeans[i] == nil { reasons.append("ansikt ikke synlig") }
                if a.eyesClosedCount > 0 {
                    total -= 20 * Double(a.eyesClosedCount)
                    reasons.append("øyne lukket")
                }
                if faceMeans[i] == maxFace, items.count > 1 { reasons.append("best ansikt") }
            } else {
                total = 100 * (0.5 * aest + 0.5 * sharpRel)
            }

            if sharpRel >= 0.999, items.count > 1 { reasons.append("skarpest") }
            else if sharpRel < 0.5 { reasons.append("uskarpt") }
            if aest >= maxAest - 0.0001, items.count > 1, a.aesthetics != nil { reasons.append("best komposisjon") }
            if a.isUtility { reasons.append("ser ut som skjermbilde/dokument") }

            return PhotoScore(total: min(100, max(0, total)), reasons: reasons)
        }
    }
}
