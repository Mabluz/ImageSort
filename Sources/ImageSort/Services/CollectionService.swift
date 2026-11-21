import Foundation

/// «Samlinger»: mapper (f.eks. «Julekalender2026») som utvalgte bilder kopieres inn i.
/// Kopien får navnet «<Samling>_<opptaksdato>_<originalnavn>» så det er lett å vite hvor bildet hører hjemme.
enum CollectionService {
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    static func fileName(collection: String, captureDate: Date, originalName: String) -> String {
        "\(sanitize(collection))_\(dateFormatter.string(from: captureDate))_\(originalName)"
    }

    static func fileName(for photo: Photo, in folder: URL) -> String {
        fileName(collection: folder.lastPathComponent, captureDate: photo.captureDate, originalName: photo.fileName)
    }

    static func existingNames(in folder: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return Set(names)
    }

    /// Kopierer bildet inn i samlingen (gjør ingenting om kopien allerede finnes).
    static func add(_ photo: Photo, to folder: URL) throws {
        let dest = folder.appendingPathComponent(fileName(for: photo, in: folder))
        guard !FileManager.default.fileExists(atPath: dest.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: photo.url, to: dest)
    }

    /// Fjerner kopien fra samlingen (til Papirkurven, så den kan hentes tilbake).
    static func remove(_ photo: Photo, from folder: URL) throws {
        let dest = folder.appendingPathComponent(fileName(for: photo, in: folder))
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
    }
}
