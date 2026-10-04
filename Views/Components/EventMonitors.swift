import AppKit
import SwiftUI

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
