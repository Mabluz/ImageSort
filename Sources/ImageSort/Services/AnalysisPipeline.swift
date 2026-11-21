import Foundation

/// Analyserer mange bilder parallelt (med cache). Brukes både av appen og kalibreringstesten.
enum AnalysisPipeline {
    /// Vision bruker GPU/Neural Engine; flere enn ~4 samtidige gir lite og koster minne.
    static var defaultConcurrency: Int {
        min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    static func run(
        _ list: [Photo],
        cache: AnalysisCache?,
        concurrency: Int = defaultConcurrency,
        progress: @escaping @Sendable (Int) -> Void = { _ in }
    ) async -> [URL: PhotoAnalysis] {
        var results: [URL: PhotoAnalysis] = [:]
        var done = 0
        await withTaskGroup(of: (Photo, PhotoAnalysis?).self) { group in
            var iterator = list.makeIterator()
            func addNext() -> Bool {
                guard let photo = iterator.next() else { return false }
                group.addTask {
                    if let cached = cache?.get(photo) { return (photo, cached) }
                    let a = try? await PhotoAnalyzer.analyze(url: photo.url)
                    if let a { cache?.set(a, for: photo) }
                    return (photo, a)
                }
                return true
            }
            for _ in 0..<max(1, concurrency) { if !addNext() { break } }
            while let (photo, analysis) = await group.next() {
                if Task.isCancelled { group.cancelAll(); return }
                if let analysis { results[photo.url] = analysis }
                done += 1
                progress(done)
                if done % 200 == 0 { cache?.save() }
                _ = addNext()
            }
        }
        return results
    }
}
