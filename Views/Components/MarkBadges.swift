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
