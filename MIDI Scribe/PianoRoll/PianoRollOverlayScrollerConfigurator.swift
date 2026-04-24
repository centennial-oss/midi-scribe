import SwiftUI

#if os(macOS)
import AppKit

struct PianoRollOverlayScrollerConfigurator: NSViewRepresentable {
    let zoomLevel: CGFloat
    let onScrollbarMetricsChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> ConfiguratorView {
        let view = ConfiguratorView()
        view.lastLoggedZoomLevel = zoomLevel
        view.onScrollbarMetricsChanged = onScrollbarMetricsChanged
        view.logMonitorEvent("makeNSView")
        return view
    }

    func updateNSView(_ nsView: ConfiguratorView, context: Context) {
        nsView.onScrollbarMetricsChanged = onScrollbarMetricsChanged
        nsView.logMonitorEvent("updateNSView begin")
        nsView.applyOverlayScrollerStyleIfNeeded()
        nsView.logScrollbarState(reason: "update")
        if nsView.lastLoggedZoomLevel != zoomLevel {
            nsView.lastLoggedZoomLevel = zoomLevel
            nsView.logScrollbarState(reason: String(format: "zoom level=%.4f", zoomLevel))
        }
    }

    final class ConfiguratorView: NSView {
        var lastLoggedZoomLevel: CGFloat?
        var onScrollbarMetricsChanged: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            logMonitorEvent("viewDidMoveToWindow")
            applyOverlayScrollerStyleIfNeeded()
            logScrollbarState(reason: "viewDidMoveToWindow")
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            logMonitorEvent("viewDidMoveToSuperview")
            applyOverlayScrollerStyleIfNeeded()
            logScrollbarState(reason: "viewDidMoveToSuperview")
        }

        func applyOverlayScrollerStyleIfNeeded() {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let scrollView = self.locateOwningScrollView() else {
                    self.logMonitorEvent("applyOverlayScrollerStyleIfNeeded no owning scroll view")
                    return
                }
                let didChange = scrollView.scrollerStyle != .overlay
                if didChange {
                    scrollView.scrollerStyle = .overlay
                    scrollView.flashScrollers()
                }
                self.publishScrollbarMetrics(for: scrollView)
                self.logScrollbarState(reason: didChange ? "forced overlay" : "overlay already active")
            }
        }

        func logScrollbarState(reason: String) {
            #if DEBUG
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let scrollView = self.locateOwningScrollView() else {
                    self.logMonitorEvent("logScrollbarState no owning scroll view reason=\(reason)")
                    return
                }
                self.publishScrollbarMetrics(for: scrollView)
                NSLog(
                    "[ScrollbarMonitor] reason=%@ preferredScrollerStyle=%@ scrollerStyle=%@ " +
                        "hasHorizontalScroller=%@ horizontalScrollerHeight=%.2f contentViewBounds=%@ " +
                        "documentVisibleRect=%@",
                    reason,
                    Self.describe(NSScroller.preferredScrollerStyle),
                    Self.describe(scrollView.scrollerStyle),
                    scrollView.hasHorizontalScroller ? "true" : "false",
                    scrollView.horizontalScroller?.frame.height ?? 0,
                    NSStringFromRect(scrollView.contentView.bounds),
                    NSStringFromRect(scrollView.documentVisibleRect)
                )
            }
            #endif
        }

        private func publishScrollbarMetrics(for scrollView: NSScrollView) {
            let measuredInset: CGFloat
            if scrollView.hasHorizontalScroller {
                let scrollerHeight = scrollView.horizontalScroller?.frame.height ?? 0
                let fallbackHeight = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollView.scrollerStyle)
                measuredInset = max(scrollerHeight, fallbackHeight)
            } else {
                measuredInset = 0
            }
            onScrollbarMetricsChanged?(measuredInset)
        }

        private func locateOwningScrollView() -> NSScrollView? {
            if let enclosingScrollView {
                return enclosingScrollView
            }

            var ancestor: NSView? = superview
            while let current = ancestor {
                if let scrollView = current as? NSScrollView {
                    return scrollView
                }
                if let scrollView = current.enclosingScrollView {
                    return scrollView
                }
                ancestor = current.superview
            }

            guard let window, let rootView = window.contentView else { return nil }
            let monitorFrameInWindow = convert(bounds, to: nil)
            let candidates = rootView.descendantScrollViews().filter { scrollView in
                let scrollFrameInWindow = scrollView.convert(scrollView.bounds, to: nil)
                return scrollFrameInWindow.intersects(monitorFrameInWindow)
            }

            if let exactFrameMatch = candidates.first(where: { scrollView in
                let scrollFrameInWindow = scrollView.convert(scrollView.bounds, to: nil)
                return scrollFrameInWindow.integral == monitorFrameInWindow.integral
            }) {
                return exactFrameMatch
            }

            return candidates.min { lhs, rhs in
                let lhsDelta = abs(lhs.frame.width - frame.width) + abs(lhs.frame.height - frame.height)
                let rhsDelta = abs(rhs.frame.width - frame.width) + abs(rhs.frame.height - frame.height)
                return lhsDelta < rhsDelta
            }
        }

        func logMonitorEvent(_ message: String) {
            #if DEBUG
            NSLog(
                "[ScrollbarMonitor] event=%@ hasWindow=%@ hasSuperview=%@ frame=%@ bounds=%@",
                message,
                window == nil ? "false" : "true",
                superview == nil ? "false" : "true",
                NSStringFromRect(frame),
                NSStringFromRect(bounds)
            )
            #endif
        }

        private static func describe(_ style: NSScroller.Style) -> String {
            switch style {
            case .legacy:
                "legacy"
            case .overlay:
                "overlay"
            @unknown default:
                "unknown"
            }
        }
    }
}

private extension NSView {
    func descendantScrollViews() -> [NSScrollView] {
        var result: [NSScrollView] = []
        if let scrollView = self as? NSScrollView {
            result.append(scrollView)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendantScrollViews())
        }
        return result
    }
}
#endif
