import Foundation

enum PhotoSort: String, CaseIterable, Identifiable {
    case filename
    case captureDate
    case rating
    case pickStatus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filename: tr("Filename")
        case .captureDate: tr("Capture Date")
        case .rating: tr("Rating")
        case .pickStatus: tr("Pick")
        }
    }

    func compare(_ lhs: PhotoItem, _ rhs: PhotoItem) -> Bool {
        switch self {
        case .filename:
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .captureDate:
            let left = lhs.createdDate ?? lhs.fileModificationDate ?? .distantPast
            let right = rhs.createdDate ?? rhs.fileModificationDate ?? .distantPast
            if left != right { return left > right }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .rating:
            if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        case .pickStatus:
            if lhs.pickStatus.rank != rhs.pickStatus.rank {
                return lhs.pickStatus.rank < rhs.pickStatus.rank
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case filter
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .filter: tr("Filter")
        case .info: tr("Info")
        }
    }
}

extension PickStatus {
    var rank: Int {
        switch self {
        case .picked: 0
        case .none: 1
        case .rejected: 2
        }
    }
}
