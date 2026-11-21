import Foundation

/// «Samlinger»: mapper (f.eks. «Julekalender2026») som utvalgte bilder kopieres inn i.
/// Kopien får navnet «<bildemappe>_<opptaksdato>_<originalnavn>», der bildemappe er mappen bildet lå i,
/// så det er lett å vite hvor bildet kom fra.
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

    static func fileName(prefix: String, captureDate: Date, originalName: String) -> String {
        "\(sanitize(prefix))_\(dateFormatter.string(from: captureDate))_\(originalName)"
    }

    /// Navnet kopien får: «<mappen bildet ligger i>_<dato>_<originalnavn>».
    static func fileName(for photo: Photo, in folder: URL) -> String {
        fileName(prefix: photo.url.deletingLastPathComponent().lastPathComponent,
                 captureDate: photo.captureDate, originalName: photo.fileName)
    }

    /// Eldre versjoner brukte samlingens navn som prefiks. Gjenkjennes fortsatt.
    static func legacyFileName(for photo: Photo, in folder: URL) -> String {
        fileName(prefix: folder.lastPathComponent, captureDate: photo.captureDate, originalName: photo.fileName)
    }

    /// Navnet kopien faktisk har i samlingen (nytt eller gammelt format), hvis den finnes.
    static func existingName(for photo: Photo, in folder: URL, names: Set<String>) -> String? {
        [fileName(for: photo, in: folder), legacyFileName(for: photo, in: folder)].first { names.contains($0) }
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
        for name in [fileName(for: photo, in: folder), legacyFileName(for: photo, in: folder)] {
            let dest = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
            }
        }
    }
}
