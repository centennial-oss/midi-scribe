import SwiftUI

#if os(macOS)
import AppKit

private let pianoRollMacThreeFingerSwipeSensitivity: CGFloat = 1000

struct PianoRollMacThreeFingerSwipeCaptureView: NSViewRepresentable {
    let onActiveChanged: (Bool) -> Void
    let onChanged: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveChanged: onActiveChanged, onChanged: onChanged)
    }

    func makeNSView(context: Context) -> TouchCaptureView {
        let view = TouchCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.hostView = view
        return view
    }

    func updateNSView(_ nsView: TouchCaptureView, context: Context) {
        context.coordinator.updateHandlers(onActiveChanged: onActiveChanged, onChanged: onChanged)
        nsView.coordinator = context.coordinator
        context.coordinator.hostView = nsView
    }

    final class Coordinator: NSObject {
        var onActiveChanged: (Bool) -> Void
        var onChanged: (CGFloat) -> Void
        weak var hostView: TouchCaptureView?
        private var isActive = false
        private var lastCentroidX: CGFloat?
        private var lastTouchIdentities: Set<ObjectIdentifier> = []

        init(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGFloat) -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
        }

        func updateHandlers(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGFloat) -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
        }

        func handleTouches(_ touches: Set<NSTouch>, phaseLabel: StaticString) {
            guard canProcessTouchesWhileNoButtonsAreDown() else { return }

            let directTouches = touches.filter { $0.type == .indirect }
            guard !directTouches.isEmpty else { return }

            let identities = Set(directTouches.map { ObjectIdentifier($0.identity as AnyObject) })
            let activeTouches = directTouches.filter { $0.phase != .ended && $0.phase != .cancelled }
            let activeTouchArray = Array(activeTouches)
            let touchCount = activeTouchArray.count

            #if DEBUG
            NSLog(
                "[PianoRollMacThreeFingerPan] %@ touches=%ld active=%ld",
                String(describing: phaseLabel),
                directTouches.count,
                touchCount
            )
            #endif

            processActiveTouches(activeTouchArray, identities: identities)
        }

        func resetGesture() {
            lastCentroidX = nil
            lastTouchIdentities = []
            setActive(false)
        }

        private func canProcessTouchesWhileNoButtonsAreDown() -> Bool {
            guard NSEvent.pressedMouseButtons == 0 else {
                if isActive {
                    #if DEBUG
                    NSLog("[PianoRollMacThreeFingerPan] cancelling due to pressed mouse button")
                    #endif
                    resetGesture()
                }
                return false
            }
            return true
        }

        private func processActiveTouches(
            _ activeTouches: [NSTouch],
            identities: Set<ObjectIdentifier>
        ) {
            let touchCount = activeTouches.count
            guard touchCount == 3 else {
                if isActive && touchCount < 3 {
                    resetGesture()
                }
                lastTouchIdentities = identities
                return
            }

            let centroidX = activeTouches.reduce(CGFloat.zero) { partial, touch in
                partial + CGFloat(touch.normalizedPosition.x)
            } / CGFloat(touchCount)

            if !isActive || identities != lastTouchIdentities {
                setActive(true)
                lastCentroidX = centroidX
                lastTouchIdentities = identities
                return
            }

            guard let lastCentroidX else {
                self.lastCentroidX = centroidX
                lastTouchIdentities = identities
                return
            }

            let deltaX = centroidX - lastCentroidX
            self.lastCentroidX = centroidX
            lastTouchIdentities = identities
            emitTouchDelta(deltaX)
        }

        private func emitTouchDelta(_ deltaX: CGFloat) {
            guard deltaX.isFinite, deltaX != 0 else { return }

            let scaledDeltaX = deltaX * pianoRollMacThreeFingerSwipeSensitivity

            #if DEBUG
            NSLog(
                "[PianoRollMacThreeFingerPan] deltaX=%.5f scaledDeltaX=%.5f",
                deltaX,
                scaledDeltaX
            )
            #endif

            onChanged(scaledDeltaX)
        }

        private func setActive(_ isActive: Bool) {
            guard self.isActive != isActive else { return }
            self.isActive = isActive
            onActiveChanged(isActive)
        }
    }

    final class TouchCaptureView: NSView {
        weak var coordinator: Coordinator?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        private func commonInit() {
            wantsLayer = false
            allowedTouchTypes = [.indirect]
            wantsRestingTouches = false
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            if event.type == .leftMouseDown || event.type == .leftMouseUp ||
                event.type == .rightMouseDown || event.type == .rightMouseUp ||
                event.type == .otherMouseDown || event.type == .otherMouseUp ||
                event.type == .leftMouseDragged || event.type == .rightMouseDragged ||
                event.type == .otherMouseDragged || event.type == .mouseMoved {
                return nil
            }
            return super.hitTest(point)
        }

        override func touchesBegan(with event: NSEvent) {
            coordinator?.handleTouches(event.touches(matching: .touching, in: self), phaseLabel: "began")
            super.touchesBegan(with: event)
        }

        override func touchesMoved(with event: NSEvent) {
            coordinator?.handleTouches(event.touches(matching: .touching, in: self), phaseLabel: "moved")
            super.touchesMoved(with: event)
        }

        override func touchesEnded(with event: NSEvent) {
            coordinator?.handleTouches(event.touches(matching: .any, in: self), phaseLabel: "ended")
            super.touchesEnded(with: event)
            coordinator?.resetGesture()
        }

        override func touchesCancelled(with event: NSEvent) {
            coordinator?.handleTouches(event.touches(matching: .any, in: self), phaseLabel: "cancelled")
            super.touchesCancelled(with: event)
            coordinator?.resetGesture()
        }
    }
}
#endif
