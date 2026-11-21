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
