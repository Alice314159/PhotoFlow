import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScannedFile: Sendable, Equatable {
    let url: URL
    let modificationDate: Date?
    let fileSize: Int64?
    var availability: FileAvailability = .available
}

/// Added / removed / edited files between a loaded library and a fresh folder scan.
struct FolderDiff: Equatable {
    var added: [ScannedFile] = []
    var removedIDs: [String] = []
    var staleDates: [String: Date] = [:]

    var isEmpty: Bool { added.isEmpty && removedIDs.isEmpty && staleDates.isEmpty }

    static func between(known: [PhotoItem], scanned: [ScannedFile]) -> FolderDiff {
        let found = Set(scanned.map(\.url.path))
        let byID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        var diff = FolderDiff()
        diff.added = scanned.filter { byID[$0.url.path] == nil }
        diff.removedIDs = known.filter { !found.contains($0.id) }.map(\.id)
        for file in scanned {
            guard let existing = byID[file.url.path], let date = file.modificationDate else { continue }
            if let old = existing.fileModificationDate, abs(old.timeIntervalSince(date)) <= 1 { continue }
            diff.staleDates[existing.id] = date
        }
        return diff
    }
}

/// Which files PhotoFlow shows: everything ImageIO can decode on this Mac, plus every
/// common camera RAW extension (decoded by macOS's RAW engine).
enum ImageFormats {
    static let rawExtensions: Set<String> = [
        "3fr", "fff",               // Hasselblad
        "ari",                      // ARRI
        "arw", "srf", "sr2",        // Sony
        "bay",                      // Casio
        "cap", "eip", "iiq",        // Phase One
        "cr2", "cr3", "crw",        // Canon
        "dcr", "dcs", "drf", "k25", "kdc", // Kodak
        "dng",                      // Adobe / Leica / Pentax / phones
        "erf",                      // Epson
        "gpr",                      // GoPro
        "mdc", "mrw",               // Minolta
        "mef",                      // Mamiya
        "mos",                      // Leaf
        "nef", "nrw",               // Nikon
        "orf", "ori",               // Olympus / OM System
        "pef", "ptx",               // Pentax
        "pxn",                      // Logitech
        "raf",                      // Fujifilm
        "raw", "rwl", "rw2",        // Panasonic / Leica
        "rwz",                      // Rawzor
        "srw",                      // Samsung
        "x3f"                       // Sigma
    ]

    static let commonExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif",
        "heic", "heif", "hif", "avif",
        "png", "gif", "bmp", "dib",
        "tif", "tiff", "webp",
        "jp2", "j2k", "jpf", "jpx", "jxl",
        "psd", "tga", "exr", "hdr"
    ]

    /// Formats ImageIO can read that aren't photos.
    private static let excluded: Set<String> = [
        "pdf", "ai", "eps", "ps", "svg", "ktx", "ktx2", "astc", "dds", "pvr",
        "icns", "ico", "cur", "xbm", "pbm", "pgm", "ppm", "pnm", "pict", "pct", "pic", "qtif", "qti"
    ]

    static let supportedExtensions: Set<String> = {
        var extensions = commonExtensions.union(rawExtensions)
        let identifiers = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            for ext in type.tags[.filenameExtension] ?? [] {
                extensions.insert(ext.lowercased())
            }
        }
        return extensions.subtracting(excluded)
    }()

    static func isRaw(_ ext: String) -> Bool {
        rawExtensions.contains(ext.lowercased())
    }

    /// Short format name used for badges and the File Type filter.
    static func kind(forExtension raw: String) -> String {
        let ext = raw.lowercased()
        if rawExtensions.contains(ext) { return "RAW" }
        switch ext {
        case "jpg", "jpeg", "jpe", "jfif": return "JPEG"
        case "heic", "heif", "hif": return "HEIF"
        case "tif", "tiff": return "TIFF"
        case "jp2", "j2k", "jpf", "jpx": return "JPEG 2000"
        case "jxl": return "JPEG XL"
        case "webp": return "WebP"
        case "bmp", "dib": return "BMP"
        default: return ext.uppercased()
        }
    }
}

final class FolderScanner: Sendable {
    /// Files referenced by a collection. Missing or unreadable paths stay in the list.
    static func files(atPaths paths: Set<String>) -> [ScannedFile] {
        paths.map { path -> ScannedFile in
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                return ScannedFile(url: url, modificationDate: nil, fileSize: nil, availability: .missing)
            }
            guard FileManager.default.isReadableFile(atPath: path) else {
                return ScannedFile(url: url, modificationDate: nil, fileSize: nil, availability: .noAccess)
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else {
                return ScannedFile(url: url, modificationDate: nil, fileSize: nil, availability: .missing)
            }
            return ScannedFile(
                url: url,
                modificationDate: values?.contentModificationDate,
                fileSize: values?.fileSize.map(Int64.init)
            )
        }
        .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    func scan(folder url: URL) -> [ScannedFile] {
        let fm = FileManager.default
        let supported = ImageFormats.supportedExtensions
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey, .isHiddenKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [ScannedFile] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard supported.contains(ext) else { continue }

            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }

            files.append(ScannedFile(
                url: fileURL,
                modificationDate: values?.contentModificationDate,
                fileSize: values?.fileSize.map(Int64.init)
            ))
        }

        return files.sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
    }
}
