import CoreGraphics
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case jpeg
    case heic
    case png
    case tiff
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        case .png: "PNG"
        case .tiff: "TIFF"
        case .original: tr("Original copy")
        }
    }

    var fileExtension: String? {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        case .png: "png"
        case .tiff: "tif"
        case .original: nil
        }
    }

    var typeIdentifier: String? {
        switch self {
        case .jpeg: "public.jpeg"
        case .heic: "public.heic"
        case .png: "public.png"
        case .tiff: "public.tiff"
        case .original: nil
        }
    }

    var isLossy: Bool { self == .jpeg || self == .heic }
    var keepsAlpha: Bool { self == .png || self == .tiff }
}

enum SizeUnit: String, CaseIterable, Identifiable, Codable {
    case pixels
    case percent
    case inches
    case centimeters
    case millimeters

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pixels: "px"
        case .percent: "%"
        case .inches: "in"
        case .centimeters: "cm"
        case .millimeters: "mm"
        }
    }

    var title: String {
        switch self {
        case .pixels: tr("Pixels (px)")
        case .percent: tr("Percent (%)")
        case .inches: tr("Inches (in)")
        case .centimeters: tr("Centimeters (cm)")
        case .millimeters: tr("Millimeters (mm)")
        }
    }

    /// Physical units need a resolution (ppi) to become pixels.
    var isPhysical: Bool {
        self == .inches || self == .centimeters || self == .millimeters
    }

    var presets: [Double] {
        switch self {
        case .pixels: [1080, 1280, 1920, 2048, 2560, 3840, 4096]
        case .percent: [25, 50, 75]
        case .inches: [4, 6, 8, 10, 12, 16]
        case .centimeters: [10, 15, 20, 30, 40]
        case .millimeters: [100, 150, 200, 300]
        }
    }

    /// Physical length of one unit in inches.
    var inches: Double {
        switch self {
        case .inches: 1
        case .centimeters: 1 / 2.54
        case .millimeters: 1 / 25.4
        case .pixels, .percent: 1
        }
    }

    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 0.005 { return "\(Int(value.rounded()))" }
        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }
}

enum ExportColorSpace: String, CaseIterable, Identifiable, Codable {
    case sRGB
    case displayP3
    case adobeRGB
    case grayscale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        case .adobeRGB: "Adobe RGB"
        case .grayscale: tr("Grayscale")
        }
    }

    var detail: String {
        switch self {
        case .sRGB: tr("Web, social media, most screens")
        case .displayP3: tr("Wide gamut for Apple devices and modern displays")
        case .adobeRGB: tr("Wide gamut for print workflows")
        case .grayscale: tr("Black & white")
        }
    }

    var cgColorSpace: CGColorSpace {
        switch self {
        case .sRGB: CGColorSpace(name: CGColorSpace.sRGB)!
        case .displayP3: CGColorSpace(name: CGColorSpace.displayP3)!
        case .adobeRGB: CGColorSpace(name: CGColorSpace.adobeRGB1998)!
        case .grayscale: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        }
    }
}

struct ExportSettings: Equatable, Codable {
    var format: ExportFormat = .jpeg
    var quality: Double = 0.9
    var pattern = "{name}"
    /// false = keep the original pixel size.
    var resize = false
    var sizeValue: Double = 2048
    var sizeUnit: SizeUnit = .pixels
    /// Pixels per inch for physical units; also written to the file's DPI metadata.
    var resolution: Double = 300
    var colorSpace: ExportColorSpace = .sRGB

    var isValid: Bool {
        !resize || (sizeValue > 0 && (!sizeUnit.isPhysical || resolution > 0))
    }

    /// Target long edge in pixels for `photo`, or nil to keep the original size.
    func longEdgePixels(for photo: PhotoItem) -> Int? {
        guard resize, sizeValue > 0 else { return nil }
        let pixels: Double
        switch sizeUnit {
        case .pixels:
            pixels = sizeValue
        case .percent:
            guard let width = photo.width, let height = photo.height else { return nil }
            pixels = Double(max(width, height)) * sizeValue / 100
        case .inches, .centimeters, .millimeters:
            pixels = sizeValue * sizeUnit.inches * resolution
        }
        return max(Int(pixels.rounded()), 16)
    }

    /// Converts the current size into `unit`, keeping the same pixel size for `reference`.
    func converted(to unit: SizeUnit, reference: PhotoItem?) -> Double {
        let longEdge = Double(reference.flatMap { photo in
            photo.width.flatMap { width in photo.height.map { max(width, $0) } }
        } ?? 4000)
        let pixels: Double
        switch sizeUnit {
        case .pixels: pixels = sizeValue
        case .percent: pixels = longEdge * sizeValue / 100
        default: pixels = sizeValue * sizeUnit.inches * resolution
        }
        let value: Double
        switch unit {
        case .pixels: value = pixels.rounded()
        case .percent: value = min(pixels / longEdge * 100, 100)
        default: value = pixels / resolution / unit.inches
        }
        return (value * 100).rounded() / 100
    }
}

enum NameTemplate {
    static func resolve(_ pattern: String, photo: PhotoItem, index: Int, fileExtension: String) -> String {
        let stem = (photo.name as NSString).deletingPathExtension
        let date = photo.createdDate ?? photo.fileModificationDate ?? Date()
        let day = Self.day.string(from: date)
        var text = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "{name}" }
        text = text.replacingOccurrences(of: "{name}", with: stem)
        text = text.replacingOccurrences(of: "{nnn}", with: String(format: "%03d", index))
        text = text.replacingOccurrences(of: "{n}", with: "\(index)")
        text = text.replacingOccurrences(of: "{date}", with: day)
        text = text.replacingOccurrences(of: "{camera}", with: photo.cameraBrand ?? "camera")
        let cleaned = text.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(cleaned).\(fileExtension)"
    }

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

enum ByteCount {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
