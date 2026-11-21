import AppKit
import ImageIO

enum ImageLoader {
    /// Rask nedskalert dekoding med riktig orientering.
    static func cgImage(url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 600 }

    func image(for url: URL, maxPixel: Int) async -> NSImage? {
        let key = "\(maxPixel)|\(url.path)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        // Dekoding blokkerer; kjør på GCD i stedet for Swift Concurrency sin trådpool.
        let img: NSImage? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let cg = ImageLoader.cgImage(url: url, maxPixel: maxPixel)
                cont.resume(returning: cg.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) })
            }
        }
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}

extension ImageLoader {
    /// Pikselstørrelse slik bildet vises (tar hensyn til EXIF-rotasjon), uten å dekode.
    static func displayPixelSize(url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = (p[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (p[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
        let orientation = (p[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
}

/// Bilder i full oppløsning. Store, så cachen er begrenset på minne og holder bare noen få.
final class FullImageCache: @unchecked Sendable {
    static let shared = FullImageCache()
    private let cache = NSCache<NSString, NSImage>()
    private let lock = NSLock()
    private var inFlight: [String: [CheckedContinuation<NSImage?, Never>]] = [:]

    init() { cache.totalCostLimit = 1_500_000_000 }

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url.path as NSString) }

    func image(for url: URL) async -> NSImage? {
        let key = url.path
        if let hit = cache.object(forKey: key as NSString) { return hit }
        return await withCheckedContinuation { cont in
            lock.lock()
            if inFlight[key] != nil {
                inFlight[key]!.append(cont)
                lock.unlock()
                return
            }
            inFlight[key] = [cont]
            lock.unlock()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var img: NSImage?
                if let size = ImageLoader.displayPixelSize(url: url),
                   let cg = ImageLoader.cgImage(url: url, maxPixel: Int(max(size.width, size.height))) {
                    img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    cache.setObject(img!, forKey: key as NSString, cost: cg.width * cg.height * 4)
                }
                lock.lock()
                let waiters = inFlight.removeValue(forKey: key) ?? []
                lock.unlock()
                for w in waiters { w.resume(returning: img) }
            }
        }
    }

    /// Last nabobilder i bakgrunnen så bytte går lynraskt.
    func prefetch(_ urls: [URL]) {
        for url in urls where cached(url) == nil {
            Task { _ = await image(for: url) }
        }
    }
}
