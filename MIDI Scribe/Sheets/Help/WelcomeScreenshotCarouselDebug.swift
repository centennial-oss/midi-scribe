import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if DEBUG
struct DebugUndimmedZoneOverlay: View {
    let imageRect: CGRect
    let originalSize: CGSize
    let zones: [OnboardingUndimmedZone]

    var body: some View {
        Canvas { context, _ in
            for zone in zones {
                context.fill(renderedZonePath(for: zone), with: .color(.red.opacity(0.5)))
            }
        }
        .allowsHitTesting(false)
    }

    private func renderedZonePath(for zone: OnboardingUndimmedZone) -> Path {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return Path()
        }
        let scaleX = imageRect.width / originalSize.width
        let scaleY = imageRect.height / originalSize.height

        switch zone {
        case let .roundedRect(centerX, centerY, width, height, cornerRadius):
            let rect = CGRect(
                x: imageRect.minX + (centerX * scaleX) - ((width * scaleX) / 2),
                y: imageRect.minY + (centerY * scaleY) - ((height * scaleY) / 2),
                width: width * scaleX,
                height: height * scaleY
            )
            return RoundedRectangle(
                cornerRadius: cornerRadius * min(scaleX, scaleY),
                style: .continuous
            )
            .path(in: rect)
        case let .circle(centerX, centerY, diameter):
            let renderedDiameter = diameter * min(scaleX, scaleY)
            let rect = CGRect(
                x: imageRect.minX + (centerX * scaleX) - (renderedDiameter / 2),
                y: imageRect.minY + (centerY * scaleY) - (renderedDiameter / 2),
                width: renderedDiameter,
                height: renderedDiameter
            )
            return Path(ellipseIn: rect)
        }
    }
}

struct OnboardingImageClickLogger: ViewModifier {
    let assetName: String
    let imageRect: CGRect
    let originalSize: CGSize

    @State private var previousSourcePoint: CGPoint?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        logClick(at: value.location)
                    }
            )
    }

    private func logClick(at hitPoint: CGPoint) {
        guard hasValidGeometry else {
            logUnavailableSource(at: hitPoint)
            return
        }

        let sourcePoint = sourcePoint(from: hitPoint)
        if let previousSourcePoint {
            logDragSegment(from: previousSourcePoint, to: sourcePoint, hitPoint: hitPoint)
        } else {
            logSinglePoint(sourcePoint, hitPoint: hitPoint)
        }
        self.previousSourcePoint = sourcePoint
    }

    private var hasValidGeometry: Bool {
        originalSize.width > 0 &&
            originalSize.height > 0 &&
            imageRect.width > 0 &&
            imageRect.height > 0
    }

    private func sourcePoint(from hitPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: ((hitPoint.x - imageRect.minX) / imageRect.width) * originalSize.width,
            y: ((hitPoint.y - imageRect.minY) / imageRect.height) * originalSize.height
        )
    }

    private func logUnavailableSource(at hitPoint: CGPoint) {
        NSLog(
            "[OnboardingImageClick] asset=%@ raw=(x: %.1f, y: %.1f) source unavailable",
            assetName,
            hitPoint.x,
            hitPoint.y
        )
    }

    private func logSinglePoint(_ sourcePoint: CGPoint, hitPoint: CGPoint) {
        NSLog(
            "[OnboardingImageClick] asset=%@ raw=(x: %.1f, y: %.1f) " +
                "source=(x: %.1f, y: %.1f) sourceRounded=(x: %.0f, y: %.0f)",
            assetName,
            hitPoint.x,
            hitPoint.y,
            sourcePoint.x,
            sourcePoint.y,
            sourcePoint.x,
            sourcePoint.y
        )
    }

    private func logDragSegment(from previousPoint: CGPoint, to sourcePoint: CGPoint, hitPoint: CGPoint) {
        let minX = min(previousPoint.x, sourcePoint.x)
        let minY = min(previousPoint.y, sourcePoint.y)
        let width = abs(sourcePoint.x - previousPoint.x)
        let height = abs(sourcePoint.y - previousPoint.y)
        let centerX = minX + (width / 2)
        let centerY = minY + (height / 2)

        NSLog(
            "[OnboardingImageClick] asset=%@ raw=(x: %.1f, y: %.1f) " +
                "source=(x: %.1f, y: %.1f) sourceRounded=(x: %.0f, y: %.0f) " +
                "sourceRect=%.0fx%.0f@%.0f,%.0f",
            assetName,
            hitPoint.x,
            hitPoint.y,
            sourcePoint.x,
            sourcePoint.y,
            sourcePoint.x,
            sourcePoint.y,
            floor(width),
            floor(height),
            floor(centerX),
            floor(centerY)
        )
    }
}

struct DebugUndimmedZoneGestureOverlay: View {
    @Binding var isActive: Bool

    var body: some View {
        PlatformDebugUndimmedZoneGestureOverlay(isActive: $isActive)
    }
}

#if os(macOS)
private struct PlatformDebugUndimmedZoneGestureOverlay: NSViewRepresentable {
    @Binding var isActive: Bool

    func makeNSView(context: Context) -> DebugUndimmedZoneMouseView {
        let view = DebugUndimmedZoneMouseView()
        view.onActiveChanged = { isActive in
            context.coordinator.isActive = isActive
        }
        return view
    }

    func updateNSView(_ nsView: DebugUndimmedZoneMouseView, context: Context) {
        nsView.onActiveChanged = { isActive in
            context.coordinator.isActive = isActive
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive)
    }

    final class Coordinator {
        @Binding var isActive: Bool

        init(isActive: Binding<Bool>) {
            _isActive = isActive
        }
    }
}
#else
private struct PlatformDebugUndimmedZoneGestureOverlay: UIViewRepresentable {
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> DebugUndimmedZoneTouchView {
        let view = DebugUndimmedZoneTouchView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onActiveChanged = { isActive in
            context.coordinator.isActive = isActive
        }
        return view
    }

    func updateUIView(_ uiView: DebugUndimmedZoneTouchView, context: Context) {
        uiView.onActiveChanged = { isActive in
            context.coordinator.isActive = isActive
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isActive: $isActive)
    }

    final class Coordinator {
        @Binding var isActive: Bool

        init(isActive: Binding<Bool>) {
            _isActive = isActive
        }
    }
}
#endif

#if os(macOS)
private final class DebugUndimmedZoneMouseView: NSView {
    var onActiveChanged: ((Bool) -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp]) { [weak self] event in
            guard let self else { return event }

            switch event.type {
            case .rightMouseDown:
                if contains(event) {
                    onActiveChanged?(true)
                }
            case .rightMouseUp:
                onActiveChanged?(false)
            default:
                break
            }
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        onActiveChanged?(false)
    }

    private func contains(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let windowPoint = event.locationInWindow
        let localPoint = convert(windowPoint, from: nil)
        return bounds.contains(localPoint)
    }

    deinit {
        stopMonitoring()
    }
}
#else
private final class DebugUndimmedZoneTouchView: UIView {
    var onActiveChanged: ((Bool) -> Void)?
    private weak var gestureHostView: UIView?
    private var twoFingerPressRecognizer: UILongPressGestureRecognizer?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        installRecognizerIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installRecognizerIfNeeded()
    }

    private func installRecognizerIfNeeded() {
        guard let superview, gestureHostView !== superview else { return }
        if let twoFingerPressRecognizer, let gestureHostView {
            gestureHostView.removeGestureRecognizer(twoFingerPressRecognizer)
        }

        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleTwoFingerPress(_:)))
        recognizer.minimumPressDuration = 0
        recognizer.numberOfTouchesRequired = 2
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        superview.addGestureRecognizer(recognizer)

        twoFingerPressRecognizer = recognizer
        gestureHostView = superview
    }

    @objc private func handleTwoFingerPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            let location = recognizer.location(in: self)
            onActiveChanged?(bounds.contains(location))
        case .ended, .cancelled, .failed:
            onActiveChanged?(false)
        default:
            break
        }
    }

    deinit {
        if let twoFingerPressRecognizer, let gestureHostView {
            gestureHostView.removeGestureRecognizer(twoFingerPressRecognizer)
        }
    }
}
#endif
#endif
