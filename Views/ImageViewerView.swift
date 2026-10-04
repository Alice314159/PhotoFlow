import SwiftUI

struct ImageViewerView: View {
    @ObservedObject var library: PhotoLibrary
    private var scale = State(initialValue: CGFloat(1))
    private var offset = State(initialValue: CGSize.zero)
    private var dragOrigin = State(initialValue: CGSize.zero)
    private var pinchOrigin = State(initialValue: CGFloat(1))
    private var canvasSize = State(initialValue: CGSize.zero)
    private var isHovering = State(initialValue: false)

    private var maxScale: CGFloat {
        max(8, (actualPixelsScale ?? 1) * 4)
    }

    /// Screen pixels per image pixel at Fit, from the stored dimensions.
    private var fitPixelRatio: CGFloat? {
        guard let photo = library.selectedPhoto, let w = photo.width, let h = photo.height, w > 0, h > 0 else {
            return nil
        }
        let size = canvasSize.wrappedValue
        let fitPoints = min((size.width - 32) / CGFloat(w), (size.height - 32) / CGFloat(h))
        guard fitPoints > 0 else { return nil }
        return fitPoints * (NSScreen.main?.backingScaleFactor ?? 2)
    }

    /// The zoom factor (relative to Fit) that shows one image pixel per screen pixel.
    private var actualPixelsScale: CGFloat? {
        fitPixelRatio.map { 1 / $0 }
    }

    private var zoomLabel: String {
        guard scale.wrappedValue > 1.001 else { return tr("Fit") }
        if let ratio = fitPixelRatio {
            return "\(Int((scale.wrappedValue * ratio * 100).rounded()))%"
        }
        return "\(Int((scale.wrappedValue * 100).rounded()))%"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                library.skin.palette.canvas

                if let photo = library.selectedPhoto {
                    loupe(photo)
                    ScrollZoomMonitor { delta, anchor in
                        applyScrollZoom(delta, anchor: anchor)
                    }
                    navigationOverlay
                    zoomControls
                    if !library.showInfoBar {
                        positionBadge(photo)
                    }
                } else if library.isLoading {
                    ProgressView(library.scanProgress)
                } else {
                    emptyState
                }
            }
            .clipped()
            .onAppear { canvasSize.wrappedValue = geo.size }
            .onChange(of: geo.size) { _, size in
                canvasSize.wrappedValue = size
                offset.wrappedValue = clampedOffset(offset.wrappedValue, scale: scale.wrappedValue)
                dragOrigin.wrappedValue = offset.wrappedValue
            }
        }
        .onHover { isHovering.wrappedValue = $0 }
        .onChange(of: library.selectedID) { _, _ in
            resetZoom()
        }
        .onChange(of: library.zoomCommand) { _, command in
            guard let command, library.selectedPhoto != nil else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                switch command.kind {
                case .toggle: toggleZoom()
                case .zoomIn: setScale(scale.wrappedValue * 1.5, anchor: .zero)
                case .zoomOut: setScale(scale.wrappedValue / 1.5, anchor: .zero)
                case .fit: resetZoom()
                case .actual: zoomToActualPixels()
                }
            }
        }
    }

    /// Lightroom's Z: Fit ↔ 1:1.
    private func toggleZoom() {
        if scale.wrappedValue > 1.001 {
            resetZoom()
        } else {
            zoomToActualPixels()
        }
    }

    private func zoomToActualPixels() {
        let target = actualPixelsScale ?? 2.5
        setScale(target > 1.2 ? target : 2.5, anchor: .zero)
    }

    // MARK: - Image

    private func loupe(_ photo: PhotoItem) -> some View {
        CachedThumbnail(url: photo.url, maxPixelSize: ThumbnailCache.loupeSize, fill: false, showsBackdrop: false)
            .padding(16)
            .scaleEffect(scale.wrappedValue)
            .offset(offset.wrappedValue)
            .id(photo.id)
            .contextMenu { PhotoActionsMenu(library: library, anchor: photo) }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        setScale(pinchOrigin.wrappedValue * value, anchor: .zero)
                    }
                    .onEnded { _ in
                        pinchOrigin.wrappedValue = scale.wrappedValue
                        if scale.wrappedValue <= 1.001 { resetZoom() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale.wrappedValue > 1 else { return }
                        offset.wrappedValue = clampedOffset(
                            CGSize(
                                width: dragOrigin.wrappedValue.width + value.translation.width,
                                height: dragOrigin.wrappedValue.height + value.translation.height
                            ),
                            scale: scale.wrappedValue
                        )
                    }
                    .onEnded { _ in
                        dragOrigin.wrappedValue = offset.wrappedValue
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    toggleZoom()
                }
            }
    }

    // MARK: - Overlays

    private var navigationOverlay: some View {
        HStack {
            navButton(systemImage: "chevron.left", help: tr("Previous photo (←)"), enabled: library.canSelectPrevious) {
                library.selectPrevious()
            }
            Spacer(minLength: 0)
            navButton(systemImage: "chevron.right", help: tr("Next photo (→)"), enabled: library.canSelectNext) {
                library.selectNext()
            }
        }
        .padding(.horizontal, 10)
    }

    private func navButton(systemImage: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                .frame(width: 64, height: 180)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? (isHovering.wrappedValue ? 1 : 0.45) : 0.12)
        .animation(.easeInOut(duration: 0.15), value: isHovering.wrappedValue)
        .help(help)
    }

    private var zoomControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 2) {
                zoomButton("minus.magnifyingglass", help: tr("Zoom out (⌘−)")) { zoom(by: 1 / 1.25) }
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { toggleZoom() }
                } label: {
                    Text(zoomLabel)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .frame(width: 48, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Toggle Fit / 1:1 (Z, Space, or double-click)"))
                zoomButton("plus.magnifyingglass", help: tr("Zoom in (⌘= or scroll wheel)")) { zoom(by: 1.25) }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .padding(.bottom, 14)
            .opacity(isHovering.wrappedValue || scale.wrappedValue > 1 ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isHovering.wrappedValue)
        }
    }

    private func zoomButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func positionBadge(_ photo: PhotoItem) -> some View {
        VStack {
            HStack(spacing: 8) {
                Text("\((library.selectedVisibleIndex ?? 0) + 1) / \(library.filteredPhotos.count)")
                    .monospacedDigit()
                Text(photo.name)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                if photo.rating > 0 {
                    Text(String(repeating: "★", count: photo.rating))
                        .foregroundStyle(.yellow)
                }
                PickBadge(status: photo.pickStatus, compact: true)
            }
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 12)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let collection = library.activeCollection, library.photos.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text(tr("“%@” is empty", collection.name))
                    .font(.title3.weight(.semibold))
                Text(tr("Select photos in a folder and press B, use “Add to Collection” in the right-click menu, or drag photos onto the collection in the sidebar."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                Button(tr("Back to Folder")) { library.returnToFolder() }
            }
            .padding(32)
        } else {
            folderEmptyState
        }
    }

    private var folderEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: library.folderURL == nil ? "photo.on.rectangle.angled" : "line.3.horizontal.decrease")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(library.folderURL == nil ? tr("Open a folder to begin") : tr("No photos match these filters"))
                .font(.title3.weight(.semibold))
            Text(library.folderURL == nil
                 ? tr("Original files stay untouched. Ratings, colors, and picks live in PhotoFlow’s SQLite database.")
                 : tr("Try clearing filters or choosing another Smart album."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if library.folderURL == nil {
                Button(tr("Open Folder…")) {
                    library.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            } else {
                Button(tr("Clear Filters")) {
                    library.clearFilters()
                }
            }
        }
        .padding(32)
    }

    // MARK: - Zoom

    private func applyScrollZoom(_ delta: CGFloat, anchor: CGPoint) {
        setScale(scale.wrappedValue * (1 + delta * 0.12), anchor: anchor)
    }

    private func zoom(by factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.12)) {
            setScale(scale.wrappedValue * factor, anchor: .zero)
        }
    }

    /// Changes zoom while keeping the image point under `anchor` (relative to the canvas centre) fixed.
    private func setScale(_ proposed: CGFloat, anchor: CGPoint) {
        let old = scale.wrappedValue
        let next = min(max(proposed, 1), maxScale)
        guard next > 1.001 else {
            resetZoom()
            return
        }
        let ratio = next / old
        let current = offset.wrappedValue
        let shifted = CGSize(
            width: anchor.x - ratio * (anchor.x - current.width),
            height: anchor.y - ratio * (anchor.y - current.height)
        )
        scale.wrappedValue = next
        pinchOrigin.wrappedValue = next
        offset.wrappedValue = clampedOffset(shifted, scale: next)
        dragOrigin.wrappedValue = offset.wrappedValue
    }

    private func clampedOffset(_ proposed: CGSize, scale: CGFloat) -> CGSize {
        let size = canvasSize.wrappedValue
        let limitX = max((scale - 1) * size.width / 2, 0)
        let limitY = max((scale - 1) * size.height / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -limitX), limitX),
            height: min(max(proposed.height, -limitY), limitY)
        )
    }

    private func resetZoom() {
        scale.wrappedValue = 1
        offset.wrappedValue = .zero
        dragOrigin.wrappedValue = .zero
        pinchOrigin.wrappedValue = 1
    }
}
