import Foundation

/// Lagrer analyser på disk så samme mappe åpnes raskt neste gang.
final class AnalysisCache: @unchecked Sendable {
    static let shared = AnalysisCache()

    private let lock = NSLock()
    private var entries: [String: PhotoAnalysis] = [:]
    private var dirty = false
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ImageSort", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("analysis-cache.plist")
        }
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? PropertyListDecoder().decode([String: PhotoAnalysis].self, from: data) {
            entries = decoded
        }
    }

    static func key(path: String, modificationDate: Date, size: Int64) -> String {
        "\(path)|\(Int64(modificationDate.timeIntervalSince1970 * 1000))|\(size)"
    }

    static func key(for photo: Photo) -> String {
        key(path: photo.url.path, modificationDate: photo.modificationDate, size: photo.fileSize)
    }

    func get(_ photo: Photo) -> PhotoAnalysis? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[Self.key(for: photo)], e.version == PhotoAnalysis.currentVersion else { return nil }
        return e
    }

    func set(_ analysis: PhotoAnalysis, for photo: Photo) {
        lock.lock(); defer { lock.unlock() }
        entries[Self.key(for: photo)] = analysis
        dirty = true
    }

    func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = entries
        dirty = false
        lock.unlock()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
