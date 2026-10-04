import SwiftUI

/// Content groups detected on-device by Vision. A photo can belong to several.
enum PhotoCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case people
    case sports
    case pets
    case birds
    case animals
    case nature
    case flowers
    case architecture
    case food
    case vehicles
    case night
    case events
    case documents
    case other

    var id: String { rawValue }

    var title: String {
        L10n.isChinese ? chineseTitle : englishTitle
    }

    var chineseTitle: String {
        switch self {
        case .people: "人物"
        case .sports: "竞技体育"
        case .pets: "宠物"
        case .birds: "鸟类"
        case .animals: "动物"
        case .nature: "自然风光"
        case .flowers: "花卉植物"
        case .architecture: "建筑城市"
        case .food: "美食"
        case .vehicles: "交通工具"
        case .night: "夜景"
        case .events: "活动演出"
        case .documents: "文档截图"
        case .other: "其他"
        }
    }

    var englishTitle: String {
        switch self {
        case .people: "People"
        case .sports: "Sports"
        case .pets: "Pets"
        case .birds: "Birds"
        case .animals: "Animals"
        case .nature: "Nature"
        case .flowers: "Flowers & Plants"
        case .architecture: "Architecture"
        case .food: "Food"
        case .vehicles: "Vehicles"
        case .night: "Night"
        case .events: "Events"
        case .documents: "Documents"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .people: "person.2.fill"
        case .sports: "figure.run"
        case .pets: "pawprint.fill"
        case .birds: "bird.fill"
        case .animals: "hare.fill"
        case .nature: "mountain.2.fill"
        case .flowers: "camera.macro"
        case .architecture: "building.2.fill"
        case .food: "fork.knife"
        case .vehicles: "car.fill"
        case .night: "moon.stars.fill"
        case .events: "party.popper.fill"
        case .documents: "doc.text.fill"
        case .other: "square.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .people: .orange
        case .sports: .red
        case .pets: .brown
        case .birds: .cyan
        case .animals: .mint
        case .nature: .green
        case .flowers: .pink
        case .architecture: .gray
        case .food: .yellow
        case .vehicles: .blue
        case .night: .indigo
        case .events: .purple
        case .documents: .teal
        case .other: .secondary
        }
    }

    static func decode(_ raw: String?) -> Set<PhotoCategory> {
        guard let raw, !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").compactMap { PhotoCategory(rawValue: String($0)) })
    }

    static func encode(_ set: Set<PhotoCategory>) -> String {
        allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}

struct PhotoCollection: Identifiable, Hashable {
    let id: Int64
    var name: String
    var paths: Set<String>
    var createdAt: Date
}
