import AppKit
import ImageIO

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    static let gridSize = 360
    static let loupeSize = 2800

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 3000
        cache.totalCostLimit = 512 * 1024 * 1024
    }

    private let lock = NSLock()
    private var inFlight: [NSString: DispatchGroup] = [:]

    /// `version` is the file's modification date, so an image edited elsewhere gets a fresh thumbnail.
    /// Concurrent requests for the same image share one decode.
    func image(for url: URL, version: Date? = nil, maxPixelSize: Int = ThumbnailCache.gridSize) -> NSImage? {
        let key = Self.key(url, maxPixelSize, version)
        if let cached = cache.object(forKey: key) {
            return cached
        }

        lock.lock()
        if let running = inFlight[key] {
            lock.unlock()
            running.wait()
            return cache.object(forKey: key)
        }
        let group = DispatchGroup()
        group.enter()
        inFlight[key] = group
        lock.unlock()
        defer {
            lock.lock()
            inFlight[key] = nil
            lock.unlock()
            group.leave()
        }

        guard let (image, cost) = generate(from: url, maxPixelSize: maxPixelSize) else { return nil }
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    /// Returns an already-decoded image without doing any I/O.
    func cachedImage(for url: URL, version: Date? = nil, maxPixelSize: Int) -> NSImage? {
        cache.object(forKey: Self.key(url, maxPixelSize, version))
    }

    private static func key(_ url: URL, _ size: Int, _ version: Date?) -> NSString {
        "\(url.path)|\(size)|\(version?.timeIntervalSince1970 ?? 0)" as NSString
    }

    private func generate(from url: URL, maxPixelSize: Int) -> (NSImage, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return fallback(url, maxPixelSize)
        }

        // RAW files carry a large embedded JPEG preview; using it for grid-sized
        // thumbnails avoids a full RAW develop per cell.
        var cgImage: CGImage?
        if ImageFormats.isRaw(url.pathExtension), maxPixelSize <= 1024 {
            cgImage = thumbnail(source, maxPixelSize, fromEmbedded: true)
            if let embedded = cgImage, max(embedded.width, embedded.height) < maxPixelSize * 3 / 4 {
                cgImage = nil
            }
        }
        if cgImage == nil {
            cgImage = thumbnail(source, maxPixelSize, fromEmbedded: false)
        }
        guard let cgImage else { return fallback(url, maxPixelSize) }

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return (image, cgImage.bytesPerRow * cgImage.height)
    }

    private func thumbnail(_ source: CGImageSource, _ maxPixelSize: Int, fromEmbedded: Bool) -> CGImage? {
        let options: [CFString: Any] = [
            fromEmbedded ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private func fallback(_ url: URL, _ maxPixelSize: Int) -> (NSImage, Int)? {
        guard let image = NSImage(contentsOf: url), image.isValid,
              image.representations.contains(where: { $0.pixelsWide > 0 }) else { return nil }
        return (image, maxPixelSize * maxPixelSize * 4)
    }
}
