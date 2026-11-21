import Foundation
import Vision

struct UnionFind {
    private var parent: [Int]
    init(_ n: Int) { parent = Array(0..<n) }

    mutating func find(_ x: Int) -> Int {
        var r = x
        while parent[r] != r { r = parent[r] }
        var c = x
        while parent[c] != r { let next = parent[c]; parent[c] = r; c = next }
        return r
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }

    /// Grupper i stigende rekkefølge etter første element.
    mutating func groups() -> [[Int]] {
        var map: [Int: [Int]] = [:]
        for i in parent.indices { map[find(i), default: []].append(i) }
        return map.values.sorted { $0[0] < $1[0] }
    }
}

enum SimilarityGrouper {
    /// Deler en tidssortert liste i klynger der pausen mellom to bilder er <= maxGap sekunder.
    static func timeClusters(dates: [Date], maxGap: TimeInterval) -> [[Int]] {
        guard !dates.isEmpty else { return [] }
        var clusters: [[Int]] = [[0]]
        for i in 1..<dates.count {
            if dates[i].timeIntervalSince(dates[i - 1]) > maxGap {
                clusters.append([i])
            } else {
                clusters[clusters.count - 1].append(i)
            }
        }
        return clusters
    }

    /// Slår sammen elementer med avstand < threshold. Sammenligner kun innen `window` naboer.
    static func cluster(count: Int, window: Int = 40, threshold: Float, distance: (Int, Int) -> Float?) -> [[Int]] {
        var uf = UnionFind(count)
        for i in 0..<count {
            for j in (i + 1)..<min(count, i + 1 + window) {
                if let d = distance(i, j), d < threshold { uf.union(i, j) }
            }
        }
        return uf.groups()
    }

    /// Full gruppering: tid først, deretter visuell likhet. Returnerer kun grupper med >= 2 bilder.
    static func group(
        photos: [Photo],
        featurePrints: [URL: VNFeaturePrintObservation],
        maxGap: TimeInterval,
        threshold: Float
    ) -> [[Photo]] {
        let sorted = photos.sorted { $0.captureDate < $1.captureDate }
        var result: [[Photo]] = []
        for tc in timeClusters(dates: sorted.map(\.captureDate), maxGap: maxGap) where tc.count >= 2 {
            let items = tc.map { sorted[$0] }
            let prints = items.map { featurePrints[$0.url] }
            let groups = cluster(count: items.count, threshold: threshold) { a, b in
                guard let pa = prints[a], let pb = prints[b] else { return nil }
                var d: Float = 0
                do { try pa.computeDistance(&d, to: pb) } catch { return nil }
                return d
            }
            for g in groups where g.count >= 2 {
                result.append(g.map { items[$0] })
            }
        }
        return result
    }
}
