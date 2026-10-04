import SwiftUI

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
