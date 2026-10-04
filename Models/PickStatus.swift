import SwiftUI

enum PickStatus: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case picked
    case rejected

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: tr("Unflagged")
        case .picked: tr("Picked")
        case .rejected: tr("Rejected")
        }
    }

    var shortcut: String {
        switch self {
        case .none: "U"
        case .picked: "P"
        case .rejected: "X"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "flag.slash"
        case .picked: "flag.fill"
        case .rejected: "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .none: .secondary
        case .picked: Color(red: 0.35, green: 0.78, blue: 0.45)
        case .rejected: Color(red: 0.92, green: 0.28, blue: 0.28)
        }
    }
}
