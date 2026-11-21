import Foundation
import ImageIO

enum FolderScanner {
    static let supportedExtensions: Set<String> = ["jpg", "jpeg", "heic", "heif", "png"]

    /// Finner alle bilder rekursivt, sortert på opptakstid.
    static func scan(_ root: URL) -> [Photo] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var photos: [Photo] = []
        for case let url as URL in enumerator {
            guard supportedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let mod = values.contentModificationDate ?? .distantPast
            let date = captureDate(of: url) ?? dateFromFileName(url.lastPathComponent) ?? values.creationDate ?? mod
            photos.append(Photo(
                url: url,
                captureDate: date,
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate: mod
            ))
        }
        return photos.sorted { ($0.captureDate, $0.url.path) < ($1.captureDate, $1.url.path) }
    }

    private static let exifFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f
    }()

    private static let fileNamePattern = #/(20\d{2}|19\d{2})[-_.]?(\d{2})[-_.]?(\d{2})[ _T-]?(?:at )?(\d{2})[._:-]?(\d{2})[._:-]?(\d{2})/#

    /// Tolker tidspunkt fra vanlige filnavn, f.eks. «20261121_164418.jpg», «IMG_20261121_164418.jpg»,
    /// «PXL_20261121_164418123.jpg» og Dropbox «2026-11-21 16.44.18.jpg». Brukes når EXIF mangler.
    static func dateFromFileName(_ name: String) -> Date? {
        guard let m = name.firstMatch(of: fileNamePattern) else { return nil }
        var c = DateComponents()
        c.year = Int(m.1); c.month = Int(m.2); c.day = Int(m.3)
        c.hour = Int(m.4); c.minute = Int(m.5); c.second = Int(m.6)
        guard let mo = c.month, (1...12).contains(mo), let d = c.day, (1...31).contains(d),
              let h = c.hour, h < 24, let mi = c.minute, mi < 60, let s = c.second, s < 60 else { return nil }
        return Calendar.current.date(from: c)
    }

    /// Leser EXIF DateTimeOriginal (+ subsekunder) uten å dekode bildet.
    static func captureDate(of url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let raw = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (exif?[kCGImagePropertyExifDateTimeDigitized] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let raw, var date = exifFormatter.date(from: raw) else { return nil }
        if let sub = exif?[kCGImagePropertyExifSubsecTimeOriginal] as? String,
           let frac = Double("0." + sub) {
            date += frac
        }
        return date
    }
}
