import Foundation

/// Photo counts per rating, flag, and color, kept up to date for the sidebar.
struct MarkCounts: Equatable {
    /// `atLeast[n]` = photos rated n stars or more.
    var atLeast = [Int](repeating: 0, count: 6)
    var picks: [PickStatus: Int] = [:]
    var colors: [ColorLabel: Int] = [:]

    init() {}

    init(_ photos: [PhotoItem]) {
        var exact = [Int](repeating: 0, count: 6)
        for photo in photos {
            exact[min(max(photo.rating, 0), 5)] += 1
            picks[photo.pickStatus, default: 0] += 1
            colors[photo.colorLabel, default: 0] += 1
        }
        var running = 0
        for rating in stride(from: 5, through: 0, by: -1) {
            running += exact[rating]
            atLeast[rating] = running
        }
    }
}

enum SmartAlbum: Hashable, Identifiable {
    case all
    case rating(Int)
    case color(ColorLabel)
    case pick(PickStatus)

    var id: String {
        switch self {
        case .all: "all"
        case .rating(let value): "rating-\(value)"
        case .color(let label): "color-\(label.rawValue)"
        case .pick(let status): "pick-\(status.rawValue)"
        }
    }
}

struct FilterState: Equatable {
    var searchText = ""
    var selectedBrands: Set<String> = []
    var selectedCameras: Set<String> = []
    var selectedLenses: Set<String> = []
    var selectedKinds: Set<String> = []
    var shutter: ClosedRange<Double>?
    var aperture: ClosedRange<Double>?
    var iso: ClosedRange<Double>?
    var focalLength: ClosedRange<Double>?
    var minimumRating = 0
    var selectedColors: Set<ColorLabel> = []
    var selectedPicks: Set<PickStatus> = []
    var selectedCategories: Set<PhotoCategory> = []
    var selectedPlaces: Set<String> = []
    var smartAlbum: SmartAlbum = .all

    var isActive: Bool {
        !searchText.isEmpty
            || !selectedCategories.isEmpty
            || !selectedPlaces.isEmpty
            || !selectedBrands.isEmpty
            || !selectedCameras.isEmpty
            || !selectedLenses.isEmpty
            || !selectedKinds.isEmpty
            || shutter != nil
            || aperture != nil
            || iso != nil
            || focalLength != nil
            || minimumRating > 0
            || !selectedColors.isEmpty
            || !selectedPicks.isEmpty
            || smartAlbum != .all
    }

    /// Whether changing a rating, color, or flag can move a photo in or out of the results.
    var dependsOnMarks: Bool {
        minimumRating > 0 || !selectedColors.isEmpty || !selectedPicks.isEmpty
    }

    var activeCount: Int {
        var count = 0
        if !selectedCategories.isEmpty { count += 1 }
        if !selectedPlaces.isEmpty { count += 1 }
        if !selectedBrands.isEmpty || !selectedCameras.isEmpty { count += 1 }
        if !selectedLenses.isEmpty { count += 1 }
        if !selectedKinds.isEmpty { count += 1 }
        if shutter != nil { count += 1 }
        if aperture != nil { count += 1 }
        if iso != nil { count += 1 }
        if focalLength != nil { count += 1 }
        if minimumRating > 0 { count += 1 }
        if !selectedColors.isEmpty { count += 1 }
        if !selectedPicks.isEmpty { count += 1 }
        return count
    }

    mutating func clear() {
        self = FilterState(searchText: searchText)
    }

    mutating func applySmartAlbum(_ album: SmartAlbum) {
        smartAlbum = album
        switch album {
        case .all:
            minimumRating = 0
            selectedColors = []
            selectedPicks = []
            selectedCategories = []
            selectedPlaces = []
        case .rating(let value):
            minimumRating = value
            selectedColors = []
            selectedPicks = []
        case .color(let label):
            minimumRating = 0
            selectedColors = [label]
            selectedPicks = []
        case .pick(let status):
            minimumRating = 0
            selectedColors = []
            selectedPicks = [status]
        }
    }

    /// Pass a prebuilt `query` when testing many photos so the search text is parsed once.
    func matches(_ photo: PhotoItem, query: SearchQuery? = nil) -> Bool {
        if !searchText.isEmpty, !(query ?? SearchQuery(searchText)).matches(photo) {
            return false
        }

        if !selectedPlaces.isEmpty, !(photo.placeName.map(selectedPlaces.contains) ?? false) {
            return false
        }

        // Groups combine with OR: "People or Sports".
        if !selectedCategories.isEmpty, photo.categories.isDisjoint(with: selectedCategories) {
            return false
        }

        // A checked brand means "every body of that brand"; individually checked
        // bodies add to it, so brands and bodies combine with OR.
        if !selectedBrands.isEmpty || !selectedCameras.isEmpty {
            let brandHit = photo.cameraBrand.map(selectedBrands.contains) ?? false
            guard brandHit || selectedCameras.contains(photo.cameraDisplayName) else { return false }
        }

        if !selectedLenses.isEmpty {
            guard let lens = photo.lens, selectedLenses.contains(lens) else { return false }
        }

        if !selectedKinds.isEmpty, !selectedKinds.contains(photo.fileKind) {
            return false
        }

        if let shutter, let value = photo.shutterSpeed {
            if value + 1e-9 < shutter.lowerBound || value - 1e-9 > shutter.upperBound {
                return false
            }
        } else if let _ = self.shutter, photo.shutterSpeed == nil {
            return false
        }

        if let aperture, let value = photo.aperture {
            if value + 1e-9 < aperture.lowerBound || value - 1e-9 > aperture.upperBound {
                return false
            }
        } else if let _ = self.aperture, photo.aperture == nil {
            return false
        }

        if let iso, let value = photo.iso {
            let number = Double(value)
            if number < iso.lowerBound - 0.5 || number > iso.upperBound + 0.5 {
                return false
            }
        } else if let _ = self.iso, photo.iso == nil {
            return false
        }

        if let focalLength, let value = photo.focalLength {
            if value + 1e-9 < focalLength.lowerBound || value - 1e-9 > focalLength.upperBound {
                return false
            }
        } else if let _ = self.focalLength, photo.focalLength == nil {
            return false
        }

        if photo.rating < minimumRating {
            return false
        }

        if !selectedColors.isEmpty, !selectedColors.contains(photo.colorLabel) {
            return false
        }

        if !selectedPicks.isEmpty, !selectedPicks.contains(photo.pickStatus) {
            return false
        }

        return true
    }
}

struct FacetCount: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

struct CameraFacet: Identifiable, Hashable {
    let brand: String
    let count: Int
    let models: [FacetCount]
    var id: String { brand }

    static func build(from photos: [PhotoItem]) -> (cameras: [CameraFacet], lenses: [FacetCount], kinds: [FacetCount]) {
        var brandCounts: [String: Int] = [:]
        var modelCounts: [String: [String: Int]] = [:]
        var lensCounts: [String: Int] = [:]
        var kindCounts: [String: Int] = [:]

        for photo in photos {
            kindCounts[photo.fileKind, default: 0] += 1
            if let brand = photo.cameraBrand {
                brandCounts[brand, default: 0] += 1
                modelCounts[brand, default: [:]][photo.cameraDisplayName, default: 0] += 1
            }
            if let lens = photo.lens, !lens.isEmpty {
                lensCounts[lens, default: 0] += 1
            }
        }

        let cameras = brandCounts.map { brand, count in
            CameraFacet(brand: brand, count: count, models: sortedCounts(modelCounts[brand] ?? [:]))
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.brand < $1.brand }

        return (cameras, sortedCounts(lensCounts), sortedCounts(kindCounts))
    }

    private static func sortedCounts(_ counts: [String: Int]) -> [FacetCount] {
        counts.map { FacetCount(name: $0.key, count: $0.value) }
            .sorted {
                $0.count != $1.count
                    ? $0.count > $1.count
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
}

struct FilterBounds: Equatable {
    var shutter = 1.0 / 8000.0 ... 30.0
    var aperture = 1.0 ... 32.0
    var iso = 50.0 ... 12800.0
    var focalLength = 10.0 ... 400.0

    static func from(photos: [PhotoItem]) -> FilterBounds {
        var bounds = FilterBounds()

        let shutters = photos.compactMap(\.shutterSpeed)
        if let min = shutters.min(), let max = shutters.max(), min < max {
            bounds.shutter = min ... max
        } else if let only = shutters.first {
            bounds.shutter = max(only * 0.5, 1.0 / 8000.0) ... max(only * 2, only)
        }

        let apertures = photos.compactMap(\.aperture)
        if let min = apertures.min(), let max = apertures.max(), min < max {
            bounds.aperture = min ... max
        }

        let isos = photos.compactMap(\.iso).map(Double.init)
        if let min = isos.min(), let max = isos.max(), min < max {
            bounds.iso = min ... max
        }

        let focals = photos.compactMap(\.focalLength)
        if let min = focals.min(), let max = focals.max(), min < max {
            bounds.focalLength = min ... max
        }

        return bounds
    }
}
