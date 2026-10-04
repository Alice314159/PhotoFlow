import AppKit
import Foundation
import ImageIO

enum PhotoExporter {
    static func copy(_ photos: [PhotoItem], to folder: URL) throws -> Int {
        try export(photos, to: folder, settings: ExportSettings(format: .original))
    }

    static func export(_ photos: [PhotoItem], to folder: URL, settings: ExportSettings) throws -> Int {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var written = 0

        for (offset, photo) in photos.enumerated() {
            let ext = settings.format.fileExtension ?? photo.url.pathExtension
            let name = NameTemplate.resolve(settings.pattern, photo: photo, index: offset + 1, fileExtension: ext)
            let destination = uniqueURL(named: name, in: folder)

            switch settings.format {
            case .original:
                try fm.copyItem(at: photo.url, to: destination)
            case .jpeg, .heic, .png, .tiff:
                // A file macOS can't decode is skipped; the caller reports the shortfall.
                guard let data = encodedData(from: photo, settings: settings) else { continue }
                try data.write(to: destination)
            }
            written += 1
        }

        return written
    }

    /// Writes one photo to an exact destination chosen by the user (Save As).
    /// Replaces an existing file there, but never the photo's own original.
    static func write(_ photo: PhotoItem, to destination: URL, settings: ExportSettings) throws {
        let fm = FileManager.default
        guard destination.standardizedFileURL.path != photo.url.standardizedFileURL.path else {
            throw CocoaError(.fileWriteNoPermission)
        }
        switch settings.format {
        case .original:
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: photo.url, to: destination)
        case .jpeg, .heic, .png, .tiff:
            guard let data = encodedData(from: photo, settings: settings) else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: photo.filePath])
            }
            try data.write(to: destination, options: .atomic)
        }
    }

    static func estimateBytes(for photos: [PhotoItem], settings: ExportSettings) -> Int64 {
        guard !photos.isEmpty else { return 0 }

        if settings.format == .original {
            return photos.reduce(Int64(0)) { $0 + ($1.fileByteSize ?? fallbackSize($1)) }
        }

        let samples = Array(photos.prefix(3))
        var sampleBytes: Int64 = 0
        var sampleCount = 0
        for photo in samples {
            if let data = encodedData(from: photo, settings: settings) {
                sampleBytes += Int64(data.count)
                sampleCount += 1
            } else {
                sampleBytes += scaledOriginalEstimate(photo, settings: settings)
                sampleCount += 1
            }
        }
        guard sampleCount > 0 else { return 0 }
        let average = sampleBytes / Int64(sampleCount)
        return average * Int64(photos.count)
    }

    static func encodedData(from photo: PhotoItem, settings: ExportSettings) -> Data? {
        let originalEdge = photo.width.flatMap { width in photo.height.map { max(width, $0) } } ?? 16_384
        let maxPixel = min(settings.longEdgePixels(for: photo) ?? originalEdge, originalEdge)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let cgImage = convert(decoded, to: settings.colorSpace, keepAlpha: settings.format.keepsAlpha),
              let type = settings.format.typeIdentifier else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }

        // Keep EXIF/GPS/TIFF metadata; pixels are already rotated, so orientation becomes "up".
        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties.removeValue(forKey: kCGImagePropertyPixelWidth)
        properties.removeValue(forKey: kCGImagePropertyPixelHeight)
        // The embedded ICC profile now comes from the converted image's colour space.
        properties.removeValue(forKey: kCGImagePropertyProfileName)
        properties.removeValue(forKey: kCGImagePropertyColorModel)
        properties.removeValue(forKey: kCGImagePropertyDepth)
        properties[kCGImagePropertyDPIWidth] = settings.resolution
        properties[kCGImagePropertyDPIHeight] = settings.resolution
        if settings.format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = settings.quality
        }
        if settings.format == .tiff {
            var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
            tiff[kCGImagePropertyTIFFCompression] = 5 // LZW
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Colour-managed conversion into the export colour space (embeds the matching ICC profile).
    static func convert(_ image: CGImage, to space: ExportColorSpace, keepAlpha: Bool) -> CGImage? {
        let colorSpace = space.cgColorSpace
        let bitmapInfo: UInt32
        if space == .grayscale {
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        } else {
            bitmapInfo = keepAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        }
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Pixel size the export will have (never upscales).
    static func outputSize(for photo: PhotoItem, settings: ExportSettings) -> (Int, Int)? {
        guard let width = photo.width, let height = photo.height, width > 0, height > 0 else { return nil }
        guard let target = settings.longEdgePixels(for: photo) else { return (width, height) }
        let longEdge = max(width, height)
        if longEdge <= target { return (width, height) }
        let scale = Double(target) / Double(longEdge)
        return (Int((Double(width) * scale).rounded()), Int((Double(height) * scale).rounded()))
    }

    private static func scaledOriginalEstimate(_ photo: PhotoItem, settings: ExportSettings) -> Int64 {
        let original = photo.fileByteSize ?? fallbackSize(photo)
        guard let width = photo.width, let height = photo.height, width > 0, height > 0 else { return original }
        let sourcePixels = Double(width * height)
        let target = outputSize(for: photo, settings: settings) ?? (width, height)
        let targetPixels = Double(max(target.0 * target.1, 1))
        let quality = settings.format.isLossy ? max(settings.quality, 0.35) : 1.0
        return Int64((Double(original) * (targetPixels / sourcePixels) * quality).rounded())
    }

    private static func fallbackSize(_ photo: PhotoItem) -> Int64 {
        (try? photo.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 2_000_000
    }

    static func uniqueURL(named name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var index = 2

        while fm.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = folder.appendingPathComponent(suffix)
            index += 1
        }

        return candidate
    }
}
