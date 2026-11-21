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
        let img: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let cg = ImageLoader.cgImage(url: url, maxPixel: maxPixel) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let img { cache.setObject(img, forKey: key) }
        return img
    }
}
