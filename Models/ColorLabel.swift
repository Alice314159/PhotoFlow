import SwiftUI

enum ColorLabel: String, CaseIterable, Identifiable, Codable, Hashable {
    case none
    case red
    case yellow
    case green
    case blue
    case purple

    var id: String { rawValue }

    static var assigned: [ColorLabel] {
        allCases.filter { $0 != .none }
    }

    var color: Color {
        switch self {
        case .none: .clear
        case .red: Color(red: 0.92, green: 0.25, blue: 0.25)
        case .yellow: Color(red: 0.95, green: 0.78, blue: 0.18)
        case .green: Color(red: 0.28, green: 0.78, blue: 0.38)
        case .blue: Color(red: 0.28, green: 0.52, blue: 0.96)
        case .purple: Color(red: 0.66, green: 0.38, blue: 0.90)
        }
    }

    var defaultName: String {
        rawValue.capitalized
    }
}

struct ColorLabelNames: Codable, Equatable {
    var red = "Red"
    var yellow = "Yellow"
    var green = "Green"
    var blue = "Blue"
    var purple = "Purple"

    func name(for label: ColorLabel) -> String {
        switch label {
        case .none: tr("None")
        case .red: tr(red)
        case .yellow: tr(yellow)
        case .green: tr(green)
        case .blue: tr(blue)
        case .purple: tr(purple)
        }
    }

    mutating func setName(_ name: String, for label: ColorLabel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? label.defaultName : trimmed
        switch label {
        case .none: break
        case .red: red = value
        case .yellow: yellow = value
        case .green: green = value
        case .blue: blue = value
        case .purple: purple = value
        }
    }
}
