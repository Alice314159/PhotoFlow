import SwiftUI

enum SkinFamily: String, CaseIterable, Identifiable {
    case adobe
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adobe: tr("Adobe Style")
        case .dark: tr("Dark")
        case .light: tr("Light")
        }
    }
}

enum AppSkin: String, CaseIterable, Identifiable {
    case lightroom
    case photoshop
    case adobeLight
    case neutralGray
    case midnight
    case graphite
    case forest
    case nord
    case solarized
    case noir
    case daylight
    case paper
    case sakura
    case ocean

    var id: String { rawValue }

    var family: SkinFamily {
        switch self {
        case .lightroom, .photoshop, .adobeLight, .neutralGray: .adobe
        case .daylight, .paper, .sakura, .ocean: .light
        default: .dark
        }
    }

    var title: String {
        switch self {
        case .lightroom: "Lightroom Classic"
        case .photoshop: "Photoshop"
        case .adobeLight: tr("Adobe Light Gray")
        case .neutralGray: tr("Neutral Gray 18%")
        case .midnight: tr("Midnight")
        case .graphite: tr("Graphite")
        case .forest: tr("Forest")
        case .nord: tr("Nord")
        case .solarized: "Solarized"
        case .noir: tr("Noir")
        case .daylight: tr("Daylight")
        case .paper: tr("Paper")
        case .sakura: tr("Sakura")
        case .ocean: tr("Ocean")
        }
    }

    var subtitle: String {
        switch self {
        case .lightroom: tr("Charcoal panels, silver highlights")
        case .photoshop: tr("Dark gray UI, Photoshop blue")
        case .adobeLight: tr("Bridge / Photoshop light theme")
        case .neutralGray: tr("18% gray canvas for color-critical culling")
        case .midnight: tr("Cool dark culling desk")
        case .graphite: tr("Graphite gray with amber")
        case .forest: tr("Muted deep green")
        case .nord: tr("Nordic cool blue-gray")
        case .solarized: tr("Classic Solarized dark")
        case .noir: tr("Pure black cinema, photos stand out")
        case .daylight: tr("Light gray for daytime")
        case .paper: tr("Warm paper white")
        case .sakura: tr("Soft pink white")
        case .ocean: tr("Fresh blue-green light")
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .adobeLight, .daylight, .paper, .sakura, .ocean: .light
        default: .dark
        }
    }

    var palette: SkinPalette {
        switch self {
        case .lightroom:
            return SkinPalette(
                window: rgb(38, 38, 38),
                chrome: rgb(26, 26, 26),
                panel: rgb(51, 51, 51),
                canvas: rgb(36, 36, 36),
                rail: rgb(44, 44, 44),
                search: rgb(66, 66, 66),
                accent: rgb(84, 140, 210),
                navFill: rgb(0, 0, 0).opacity(0.45)
            )
        case .photoshop:
            return SkinPalette(
                window: rgb(40, 40, 40),
                chrome: rgb(50, 50, 50),
                panel: rgb(50, 50, 50),
                canvas: rgb(30, 30, 30),
                rail: rgb(44, 44, 44),
                search: rgb(30, 30, 30),
                accent: rgb(49, 168, 255),
                navFill: rgb(0, 0, 0).opacity(0.45)
            )
        case .adobeLight:
            return SkinPalette(
                window: rgb(222, 222, 222),
                chrome: rgb(240, 240, 240),
                panel: rgb(232, 232, 232),
                canvas: rgb(184, 184, 184),
                rail: rgb(214, 214, 214),
                search: rgb(255, 255, 255),
                accent: rgb(20, 115, 230),
                navFill: rgb(255, 255, 255).opacity(0.75)
            )
        case .neutralGray:
            return SkinPalette(
                window: rgb(56, 56, 56),
                chrome: rgb(46, 46, 46),
                panel: rgb(60, 60, 60),
                canvas: rgb(118, 118, 118),
                rail: rgb(52, 52, 52),
                search: rgb(76, 76, 76),
                accent: rgb(200, 200, 200),
                navFill: rgb(30, 30, 30).opacity(0.6)
            )
        case .midnight:
            return SkinPalette(
                window: rgb(18, 20, 26),
                chrome: rgb(28, 31, 40),
                panel: rgb(24, 27, 34),
                canvas: rgb(12, 13, 18),
                rail: rgb(22, 24, 30),
                search: rgb(40, 44, 56),
                accent: rgb(56, 132, 199),
                navFill: rgb(0, 0, 0).opacity(0.45)
            )
        case .graphite:
            return SkinPalette(
                window: rgb(36, 36, 36),
                chrome: rgb(48, 48, 48),
                panel: rgb(42, 42, 42),
                canvas: rgb(28, 28, 28),
                rail: rgb(40, 40, 40),
                search: rgb(58, 58, 58),
                accent: rgb(230, 168, 62),
                navFill: rgb(0, 0, 0).opacity(0.4)
            )
        case .forest:
            return SkinPalette(
                window: rgb(16, 24, 20),
                chrome: rgb(26, 38, 32),
                panel: rgb(22, 34, 28),
                canvas: rgb(10, 16, 13),
                rail: rgb(20, 30, 25),
                search: rgb(34, 50, 42),
                accent: rgb(110, 186, 132),
                navFill: rgb(0, 0, 0).opacity(0.45)
            )
        case .nord:
            return SkinPalette(
                window: rgb(46, 52, 64),
                chrome: rgb(59, 66, 82),
                panel: rgb(52, 58, 72),
                canvas: rgb(36, 41, 51),
                rail: rgb(56, 62, 77),
                search: rgb(67, 76, 94),
                accent: rgb(136, 192, 208),
                navFill: rgb(20, 24, 30).opacity(0.55)
            )
        case .solarized:
            return SkinPalette(
                window: rgb(0, 43, 54),
                chrome: rgb(7, 54, 66),
                panel: rgb(4, 49, 60),
                canvas: rgb(0, 34, 43),
                rail: rgb(6, 52, 63),
                search: rgb(14, 66, 80),
                accent: rgb(181, 137, 0),
                navFill: rgb(0, 20, 26).opacity(0.55)
            )
        case .noir:
            return SkinPalette(
                window: rgb(6, 6, 6),
                chrome: rgb(14, 14, 14),
                panel: rgb(10, 10, 10),
                canvas: rgb(0, 0, 0),
                rail: rgb(12, 12, 12),
                search: rgb(24, 24, 24),
                accent: rgb(220, 220, 220),
                navFill: rgb(30, 30, 30).opacity(0.7)
            )
        case .daylight:
            return SkinPalette(
                window: rgb(236, 238, 242),
                chrome: rgb(246, 247, 250),
                panel: rgb(241, 243, 247),
                canvas: rgb(214, 218, 226),
                rail: rgb(228, 231, 237),
                search: rgb(255, 255, 255),
                accent: rgb(36, 99, 186),
                navFill: rgb(255, 255, 255).opacity(0.72)
            )
        case .paper:
            return SkinPalette(
                window: rgb(236, 226, 210),
                chrome: rgb(246, 238, 224),
                panel: rgb(241, 232, 216),
                canvas: rgb(214, 200, 178),
                rail: rgb(230, 220, 202),
                search: rgb(255, 250, 240),
                accent: rgb(176, 92, 48),
                navFill: rgb(255, 248, 236).opacity(0.78)
            )
        case .sakura:
            return SkinPalette(
                window: rgb(246, 234, 238),
                chrome: rgb(252, 244, 247),
                panel: rgb(249, 239, 243),
                canvas: rgb(228, 210, 217),
                rail: rgb(240, 226, 232),
                search: rgb(255, 255, 255),
                accent: rgb(204, 82, 124),
                navFill: rgb(255, 250, 252).opacity(0.78)
            )
        case .ocean:
            return SkinPalette(
                window: rgb(226, 238, 240),
                chrome: rgb(240, 248, 249),
                panel: rgb(233, 243, 245),
                canvas: rgb(196, 216, 220),
                rail: rgb(218, 232, 235),
                search: rgb(255, 255, 255),
                accent: rgb(0, 128, 140),
                navFill: rgb(250, 255, 255).opacity(0.75)
            )
        }
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }
}

struct SkinPalette {
    var window: Color
    var chrome: Color
    var panel: Color
    var canvas: Color
    var rail: Color
    var search: Color
    var accent: Color
    var navFill: Color
}

private struct AppSkinKey: EnvironmentKey {
    static let defaultValue: AppSkin = .midnight
}

extension EnvironmentValues {
    var appSkin: AppSkin {
        get { self[AppSkinKey.self] }
        set { self[AppSkinKey.self] = newValue }
    }
}

struct SkinPreviewSwatch: View {
    let skin: AppSkin
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                skin.palette.panel
                skin.palette.canvas
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(skin.palette.accent)
                            .frame(width: 8, height: 8)
                            .padding(5)
                    }
                skin.palette.chrome
            }
            .frame(height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? skin.palette.accent : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }

            Text(skin.title)
                .font(.caption.weight(.semibold))
            Text(skin.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
