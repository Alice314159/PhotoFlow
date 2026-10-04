import AppKit
import SwiftUI

struct CachedThumbnail: View {
    let url: URL
    /// File modification date; a new value forces a fresh decode.
    var version: Date?
    var maxPixelSize: Int = ThumbnailCache.gridSize
    var fill = true
    var showsBackdrop = true

    private var image = State<NSImage?>(initialValue: nil)
    private var failed = State(initialValue: false)

    var body: some View {
        ZStack {
            if showsBackdrop {
                Color.primary.opacity(0.08)
            }
            if let shown = displayedImage {
                Image(nsImage: shown)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else if failed.wrappedValue {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: maxPixelSize > 1000 ? 40 : 20))
                    Text(tr("%@ preview unavailable", url.pathExtension.uppercased()))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task(id: "\(url.path)-\(maxPixelSize)-\(fill)-\(version?.timeIntervalSince1970 ?? 0)") {
            failed.wrappedValue = false
            if let cached = ThumbnailCache.shared.cachedImage(for: url, version: version, maxPixelSize: maxPixelSize) {
                image.wrappedValue = cached
                return
            }
            let path = url
            let size = maxPixelSize
            let version = version
            let priority: TaskPriority = size > ThumbnailCache.gridSize ? .userInitiated : .utility
            let loaded = await Task.detached(priority: priority) {
                ThumbnailCache.shared.image(for: path, version: version, maxPixelSize: size)
            }.value
            image.wrappedValue = loaded
            failed.wrappedValue = loaded == nil
        }
    }

    /// Falls back to the small grid thumbnail while the large one decodes.
    private var displayedImage: NSImage? {
        if let current = image.wrappedValue { return current }
        let cache = ThumbnailCache.shared
        if let ready = cache.cachedImage(for: url, version: version, maxPixelSize: maxPixelSize) { return ready }
        guard maxPixelSize > ThumbnailCache.gridSize else { return nil }
        return cache.cachedImage(for: url, version: version, maxPixelSize: ThumbnailCache.gridSize)
    }
}

struct ThumbnailCell: View {
    let photo: PhotoItem
    var isSelected: Bool
    var isChecked: Bool = false
    var width: CGFloat = 168
    var height: CGFloat = 118
    var inTargetCollection = false
    var onToggleCheck: (() -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if photo.availability == .available {
                CachedThumbnail(url: photo.url, version: photo.fileModificationDate)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                VStack(spacing: 4) {
                    Image(systemName: photo.availability == .missing ? "questionmark.folder" : "lock.fill")
                        .font(.system(size: 18, weight: .medium))
                    Text(photo.availability == .missing ? tr("Missing") : tr("No access"))
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(.secondary)
                .frame(width: width, height: height)
                .background(Color.primary.opacity(0.08))
            }

            HStack(spacing: 4) {
                PickBadge(status: photo.pickStatus, compact: true)
                if photo.isRaw {
                    Text(tr("RAW"))
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                }
                if inTargetCollection {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
                        .help(tr("In the target collection"))
                }
                Spacer()
                Button {
                    onToggleCheck?()
                } label: {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isChecked ? Color.accentColor : Color.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.45), radius: 2)
                }
                .buttonStyle(.plain)
            }
            .padding(6)

            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 6) {
                    if photo.rating > 0 {
                        Text(String(repeating: "★", count: photo.rating))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.yellow)
                            .shadow(color: .black.opacity(0.7), radius: 1)
                    }
                    Spacer()
                    if photo.colorLabel != .none {
                        ColorDot(label: photo.colorLabel, size: 10)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    }
                }
                .padding(6)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2.5 : 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 6 : 2, y: 1)
    }
}
