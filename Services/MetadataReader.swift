import Foundation
import ImageIO

enum MetadataReader {
    static func read(into existing: PhotoItem, modificationDate: Date?) -> PhotoItem {
        var photo = existing
        photo.fileModificationDate = modificationDate

        guard let source = CGImageSourceCreateWithURL(photo.url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return photo
        }

        photo.width = intValue(properties[kCGImagePropertyPixelWidth])
        photo.height = intValue(properties[kCGImagePropertyPixelHeight])

        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let aux = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        photo.shutterSpeed = ExposureFormat.shutterSeconds(from: exif[kCGImagePropertyExifExposureTime])
            ?? ExposureFormat.shutterSeconds(from: exif["ExposureTime" as CFString])
        photo.aperture = ExposureFormat.apertureValue(from: exif[kCGImagePropertyExifFNumber])
        photo.focalLength = doubleValue(exif[kCGImagePropertyExifFocalLength])
        photo.iso = isoValue(from: exif)

        photo.cameraMake = stringValue(tiff[kCGImagePropertyTIFFMake])
        photo.camera = stringValue(tiff[kCGImagePropertyTIFFModel])

        photo.lens = firstNonEmpty([
            stringValue(exif["LensModel" as CFString]),
            stringValue(aux["LensModel" as CFString]),
            stringValue(tiff["LensModel" as CFString])
        ])

        photo.createdDate = dateValue(exif[kCGImagePropertyExifDateTimeOriginal])
            ?? dateValue(tiff[kCGImagePropertyTIFFDateTime])

        return photo
    }

    static func needsRefresh(existing: PhotoItem?, modificationDate: Date?) -> Bool {
        guard let existing else { return true }
        guard let modificationDate else { return existing.shutterSpeed == nil && existing.camera == nil }
        guard let stored = existing.fileModificationDate else { return true }
        return abs(stored.timeIntervalSince(modificationDate)) > 1
    }

    private static func isoValue(from exif: [CFString: Any]) -> Int? {
        if let values = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any],
           let first = values.first {
            if let number = first as? NSNumber { return number.intValue }
            if let number = first as? Int { return number }
        }
        if let number = exif[kCGImagePropertyExifISOSpeedRatings] as? NSNumber {
            return number.intValue
        }
        return intValue(exif["ISOSpeedRatings" as CFString])
    }

    private static func firstNonEmpty(_ values: [String?]) -> String? {
        values.first { ($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) } ?? nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static let exifDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter
    }()

    private static func dateValue(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return exifDateFormatter.date(from: text)
    }
}
