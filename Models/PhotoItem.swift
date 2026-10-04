import Foundation

struct PhotoItem: Identifiable, Hashable {
    var filePath: String
    var rating: Int = 0
    var colorLabel: ColorLabel = .none
    var pickStatus: PickStatus = .none

    var camera: String?
    var cameraMake: String?
    var lens: String?
    var shutterSpeed: Double?
    var aperture: Double?
    var iso: Int?
    var focalLength: Double?
    var width: Int?
    var height: Int?
    var fileByteSize: Int64?
    var createdDate: Date?
    var fileModificationDate: Date?

    /// On-device content groups; empty until analyzed.
    var categories: Set<PhotoCategory> = []
    var contentLabels: [String] = []
    var isAnalyzed = false
    var categoriesEditedByUser = false

    /// GPS from EXIF, plus place names looked up for it or typed by the user.
    var latitude: Double?
    var longitude: Double?
    /// Short display name, e.g. "上海市" or "Yosemite".
    var placeName: String?
    /// Every name for the place in Chinese and English, for search.
    var placeText: String?
    var locationChecked = false
    var availability: FileAvailability = .available

    var id: String { filePath }
    var url: URL { URL(fileURLWithPath: filePath) }
    var name: String { url.lastPathComponent }

    var fileKind: String { ImageFormats.kind(forExtension: url.pathExtension) }
    var isRaw: Bool { ImageFormats.isRaw(url.pathExtension) }

    var cameraBrand: String? {
        CameraBrand.normalized(from: cameraMake, model: camera)
    }

    var cameraDisplayName: String {
        let model = camera?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let brand = cameraBrand, !model.lowercased().contains(brand.lowercased()), !model.isEmpty {
            return "\(brand) \(model)"
        }
        if !model.isEmpty { return model }
        return cameraBrand ?? "Unknown camera"
    }

    var lensDisplayName: String {
        let value = lens?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Unknown lens" : value
    }

    var hasUserMarks: Bool {
        rating > 0 || colorLabel != .none || pickStatus != .none
    }
}

/// Only the marks undo cares about — not the whole photo row.
struct MarkDelta: Equatable, Sendable {
    var id: String
    var rating: Int
    var colorLabel: ColorLabel
    var pickStatus: PickStatus

    init(_ photo: PhotoItem) {
        id = photo.id
        rating = photo.rating
        colorLabel = photo.colorLabel
        pickStatus = photo.pickStatus
    }
}

enum FileAvailability: String, Hashable {
    case available
    case missing
    case noAccess
}

enum CameraBrand {
    static let known = ["Canon", "Sony", "Nikon", "Fujifilm", "Leica", "Olympus", "Panasonic", "Hasselblad", "Apple", "Google", "Samsung", "Ricoh", "Pentax"]

    static func normalized(from make: String?, model: String?) -> String? {
        let haystack = [make, model]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard !haystack.isEmpty else { return nil }

        if haystack.contains("fujifilm") || haystack.contains("fuji") { return "Fujifilm" }
        if haystack.contains("om digital") || haystack.contains("olympus") { return "Olympus" }
        if haystack.contains("apple") { return "Apple" }

        for brand in known where haystack.contains(brand.lowercased()) {
            return brand
        }

        if let make, !make.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return make.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
