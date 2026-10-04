import SwiftUI

struct FilterSection<Content: View, Accessory: View>: View {
    let title: String
    let content: Content
    let accessory: Accessory

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                accessory
            }
            content
        }
    }
}

extension FilterSection where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

/// Checkbox row with a photo count, used for camera bodies and lenses.
struct FacetRow: View {
    enum CheckState { case off, on, mixed }

    let title: String
    var subtitle: String?
    let count: Int
    let state: CheckState
    var indent: CGFloat = 0
    /// nil = not expandable; otherwise whether it is currently expanded.
    var disclosure: Bool?
    var onDisclose: () -> Void = {}
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let disclosure {
                    Button(action: onDisclose) {
                        Image(systemName: disclosure ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 18)
                }
            }

            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
                    VStack(alignment: .leading, spacing: 0) {
                        // Facet names are data, except the "Unknown camera / lens" placeholders.
                        Text(tr(title))
                            .font(.system(size: 11, weight: state == .off ? .regular : .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let subtitle, subtitle != title {
                            Text(subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text("\(count)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(title)
        }
        .padding(.leading, indent)
    }

    private var symbol: String {
        switch state {
        case .off: "square"
        case .on: "checkmark.square.fill"
        case .mixed: "minus.square.fill"
        }
    }
}

struct FilterChip: View {
    let title: String
    var systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ChipWrap<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}
