import SwiftUI

enum PanelEdge {
    case leading, trailing, top, bottom

    var collapseSymbol: String {
        switch self {
        case .leading: "chevron.left"
        case .trailing: "chevron.right"
        case .top: "chevron.up"
        case .bottom: "chevron.down"
        }
    }

    var expandSymbol: String {
        switch self {
        case .leading: "chevron.right"
        case .trailing: "chevron.left"
        case .top: "chevron.down"
        case .bottom: "chevron.up"
        }
    }
}

struct EdgeToggleButton: View {
    let edge: PanelEdge
    var expanded = true
    var title: String?
    var helpText: String?
    let action: () -> Void

    /// Side panels use the standard macOS sidebar glyph so it can't be read as "next / previous".
    private var isSidePanel: Bool { edge == .leading || edge == .trailing }

    private var symbol: String {
        if isSidePanel { return edge == .leading ? "sidebar.left" : "sidebar.right" }
        return expanded ? edge.collapseSymbol : edge.expandSymbol
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if edge == .trailing, let title {
                    Text(title).font(.caption2)
                }
                Image(systemName: symbol)
                    .font(.system(size: isSidePanel ? 13 : 10, weight: isSidePanel ? .regular : .bold))
                if edge == .leading, let title {
                    Text(title).font(.caption2)
                }
                if (edge == .top || edge == .bottom), let title {
                    Text(title).font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, (edge == .top || edge == .bottom) ? 8 : 5)
            .padding(.vertical, (edge == .top || edge == .bottom) ? 4 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText ?? (expanded ? tr("Hide %@", title ?? "panel") : tr("Show %@", title ?? "panel")))
    }
}

struct EdgeRail: View {
    let edge: PanelEdge
    let title: String
    let action: () -> Void
    @Environment(\.appSkin) private var skin

    var body: some View {
        Button(action: action) {
            Group {
                if edge == .leading || edge == .trailing {
                    VStack(spacing: 8) {
                        Image(systemName: edge.expandSymbol)
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(edge == .leading ? -90 : 90))
                            .fixedSize()
                    }
                    .frame(width: 22)
                    .frame(maxHeight: .infinity)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: edge.expandSymbol)
                        Text(title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(height: 22)
                    .frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.secondary)
            .background(skin.palette.rail)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Expand %@", title))
    }
}

struct PanelHeader<Accessory: View>: View {
    let title: String
    let edge: PanelEdge
    let onCollapse: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    private var shortcut: String {
        switch edge {
        case .leading: " (F7)"
        case .trailing: " (F8)"
        case .bottom: title == tr("Filmstrip") ? " (F6)" : ""
        case .top: " (F5)"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            accessory()
            Spacer(minLength: 4)
            EdgeToggleButton(edge: edge, title: nil, helpText: tr("Hide %@%@", title, shortcut), action: onCollapse)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 26)
    }
}

extension PanelHeader where Accessory == EmptyView {
    init(title: String, edge: PanelEdge, onCollapse: @escaping () -> Void) {
        self.init(title: title, edge: edge, onCollapse: onCollapse) { EmptyView() }
    }
}
