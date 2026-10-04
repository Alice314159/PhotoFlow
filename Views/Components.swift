import AppKit
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

struct CachedThumbnail: View {
    let url: URL
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
        .task(id: "\(url.path)-\(maxPixelSize)-\(fill)") {
            failed.wrappedValue = false
            if let cached = ThumbnailCache.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                image.wrappedValue = cached
                return
            }
            let path = url
            let size = maxPixelSize
            let loaded = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.image(for: path, maxPixelSize: size)
            }.value
            image.wrappedValue = loaded
            failed.wrappedValue = loaded == nil
        }
    }

    /// Falls back to the small grid thumbnail while the large one decodes.
    private var displayedImage: NSImage? {
        if let current = image.wrappedValue { return current }
        let cache = ThumbnailCache.shared
        if let ready = cache.cachedImage(for: url, maxPixelSize: maxPixelSize) { return ready }
        guard maxPixelSize > ThumbnailCache.gridSize else { return nil }
        return cache.cachedImage(for: url, maxPixelSize: ThumbnailCache.gridSize)
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
            CachedThumbnail(url: photo.url)
                .frame(width: width, height: height)
                .clipped()

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

/// Scroll delta plus the cursor position relative to the view centre (SwiftUI orientation, y down).
struct ScrollZoomMonitor: View {
    let handler: (CGFloat, CGPoint) -> Void

    var body: some View {
        ScrollZoomView(handler: handler)
            .allowsHitTesting(false)
    }
}

private struct ScrollZoomView: NSViewRepresentable {
    let handler: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> ScrollZoomNSView {
        let view = ScrollZoomNSView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: ScrollZoomNSView, context: Context) {
        view.handler = handler
    }

    final class ScrollZoomNSView: NSView {
        var handler: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window == window,
                      window.attachedSheet == nil else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(location) else { return event }
                let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 80 : event.scrollingDeltaY
                if raw != 0 {
                    let dy = self.isFlipped ? location.y - self.bounds.midY : self.bounds.midY - location.y
                    self.handler?(raw, CGPoint(x: location.x - self.bounds.midX, y: dy))
                }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

/// Lets a plain mouse wheel scroll a horizontal strip: while the pointer is over this view,
/// vertical wheel motion is re-sent as horizontal motion. Real horizontal swipes pass through.
struct HorizontalWheelScroll: NSViewRepresentable {
    func makeNSView(context: Context) -> WheelNSView { WheelNSView() }
    func updateNSView(_ view: WheelNSView, context: Context) {}

    final class WheelNSView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window == window,
                      window.attachedSheet == nil,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
                      let cgEvent = event.cgEvent?.copy() else { return event }
                Self.moveVerticalToHorizontal(cgEvent)
                return NSEvent(cgEvent: cgEvent) ?? event
            }
        }

        private static func moveVerticalToHorizontal(_ event: CGEvent) {
            let pairs: [(CGEventField, CGEventField)] = [
                (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
                (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
                (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            ]
            for (vertical, horizontal) in pairs {
                let integer = event.getIntegerValueField(vertical)
                let double = event.getDoubleValueField(vertical)
                event.setIntegerValueField(horizontal, value: integer)
                event.setDoubleValueField(horizontal, value: double)
                event.setIntegerValueField(vertical, value: 0)
                event.setDoubleValueField(vertical, value: 0)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

struct RangeFilterRow: View {
    let title: String
    let range: ClosedRange<Double>
    @Binding var selection: ClosedRange<Double>?
    var usesLog = false
    var format: (Double) -> String

    private var low = State(initialValue: 0.0)
    private var high = State(initialValue: 1.0)
    private var isSyncing = State(initialValue: false)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(format(current.lowerBound))  –  \(format(current.upperBound))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            DualRangeSlider(low: low.projectedValue, high: high.projectedValue)
        }
        .onAppear { syncFromSelection() }
        .onChange(of: range) { _, _ in syncFromSelection() }
        .onChange(of: selection) { _, _ in syncFromSelection() }
        .onChange(of: low.wrappedValue) { _, _ in commit() }
        .onChange(of: high.wrappedValue) { _, _ in commit() }
    }

    private var current: ClosedRange<Double> {
        selection ?? range
    }

    private func syncFromSelection() {
        isSyncing.wrappedValue = true
        let value = selection ?? range
        if usesLog {
            low.wrappedValue = ExposureFormat.logPosition(value.lowerBound, range: range)
            high.wrappedValue = ExposureFormat.logPosition(value.upperBound, range: range)
        } else {
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            low.wrappedValue = (value.lowerBound - range.lowerBound) / span
            high.wrappedValue = (value.upperBound - range.lowerBound) / span
        }
        DispatchQueue.main.async { isSyncing.wrappedValue = false }
    }

    private func commit() {
        guard !isSyncing.wrappedValue else { return }
        let a = min(low.wrappedValue, high.wrappedValue)
        let b = max(low.wrappedValue, high.wrappedValue)
        // Compare in slider space: on a log scale (shutter 1/8000…30s) almost every
        // value is "close" to the minimum in seconds, which used to reset the handle.
        if a <= 0.005 && b >= 0.995 {
            selection = nil
            return
        }
        let start = usesLog ? ExposureFormat.logInterpolate(t: a, range: range) : linear(a)
        let end = usesLog ? ExposureFormat.logInterpolate(t: b, range: range) : linear(b)
        selection = start ... end
    }

    private func linear(_ t: Double) -> Double {
        range.lowerBound + min(max(t, 0), 1) * (range.upperBound - range.lowerBound)
    }
}

struct DualRangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double

    private var draggingLow = State<Bool?>(initialValue: nil)

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let lo = CGFloat(min(low, high)) * width
            let hi = CGFloat(max(low, high)) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(hi - lo, 4), height: 4)
                    .offset(x: lo)

                handle(at: lo)
                handle(at: hi)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = min(max(Double(value.location.x / width), 0), 1)
                        if draggingLow.wrappedValue == nil {
                            draggingLow.wrappedValue = abs(next - low) <= abs(next - high)
                        }
                        if draggingLow.wrappedValue == true {
                            low = min(next, high - 0.02)
                        } else {
                            high = max(next, low + 0.02)
                        }
                    }
                    .onEnded { _ in
                        draggingLow.wrappedValue = nil
                    }
            )
        }
        .frame(height: 22)
    }

    private func handle(at x: CGFloat) -> some View {
        Circle()
            .fill(Color.primary.opacity(0.04))
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            .overlay {
                Circle().strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
            .frame(width: 16, height: 16)
            .offset(x: x - 8)
            .allowsHitTesting(false)
    }
}
