import SwiftUI

struct RatingStarsView: View {
    let rating: Int
    var size: CGFloat = 14
    var interactive = false
    var onSelect: (Int) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(value <= rating ? Color.yellow : Color.secondary.opacity(0.55))
                    .onTapGesture {
                        guard interactive else { return }
                        onSelect(value)
                    }
            }
        }
        .accessibilityLabel(tr("%@ stars", rating))
    }
}

struct ColorDot: View {
    let label: ColorLabel
    var isSelected = false
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(label == .none ? Color.clear : label.color)
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            }
    }
}

struct PickBadge: View {
    let status: PickStatus
    var compact = false

    var body: some View {
        if status != .none {
            Image(systemName: status.systemImage)
                .font(.system(size: compact ? 11 : 13, weight: .bold))
                .foregroundStyle(status.tint)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
        }
    }
}

/// Pick / Reject / Unflag as icon buttons, shared by the info bar and the batch bar.
/// `current` is nil when a batch has mixed flags.
struct PickButtons: View {
    let current: PickStatus?
    var appliesToSelection = false
    let action: (PickStatus) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach([PickStatus.picked, .rejected, .none]) { status in
                button(status)
            }
        }
    }

    private func button(_ status: PickStatus) -> some View {
        let active = current == status
        return Button {
            action(status)
        } label: {
            Image(systemName: status == .none ? "flag.slash" : status.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(active && status != .none ? status.tint : Color.secondary)
                .frame(width: 22, height: 20)
                .background(active ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(appliesToSelection
              ? tr("%@ all selected (%@)", status.title, status.shortcut)
              : "\(status.title) (\(status.shortcut))")
    }
}
