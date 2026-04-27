import SwiftUI

#if os(iOS)
import UIKit

struct PianoRollTwoFingerDragCaptureView: UIViewRepresentable {
    enum GestureMode {
        case undecided
        case recting
        case zooming
    }

    let onActiveChanged: (Bool) -> Void
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint, CGPoint) -> Void
    let onPinchChanged: (CGFloat) -> Void
    let onPinchEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onActiveChanged: onActiveChanged,
            onChanged: onChanged,
            onEnded: onEnded,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.hostView = view
        context.coordinator.attachRecognizerIfNeeded()
        return view
    }

    func updateUIView(_: UIView, context: Context) {
        context.coordinator.updateHandlers(
            onActiveChanged: onActiveChanged,
            onChanged: onChanged,
            onEnded: onEnded,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded
        )
        context.coordinator.attachRecognizerIfNeeded()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActiveChanged: (Bool) -> Void
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void
        var onPinchChanged: (CGFloat) -> Void
        var onPinchEnded: () -> Void

        private var mode: GestureMode = .undecided
        private var startPoint: CGPoint?
        private var lastTwoTouchLocation: CGPoint?
        weak var hostView: UIView?
        weak var installedOnView: UIView?
        private var attachRetryCount = 0
        private var attachRetryWorkItem: DispatchWorkItem?
        private lazy var panRecognizer: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            return pan
        }()

        private lazy var pinchRecognizer: UIPinchGestureRecognizer = {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.delegate = self
            return pinch
        }()

        init(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void,
            onPinchChanged: @escaping (CGFloat) -> Void,
            onPinchEnded: @escaping () -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
        }

        func updateHandlers(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void,
            onPinchChanged: @escaping (CGFloat) -> Void,
            onPinchEnded: @escaping () -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
        }

        func attachRecognizerIfNeeded() {
            guard let hostView else { return }
            guard installedOnView == nil else { return }
            guard let targetView = nearestScrollView(from: hostView) else {
                #if DEBUG
                NSLog("[PianoRollTwoFingerPan] attach skipped: no scroll view in ancestor chain")
                #endif
                scheduleAttachRetry()
                return
            }
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            attachRetryCount = 0
            targetView.addGestureRecognizer(panRecognizer)
            targetView.addGestureRecognizer(pinchRecognizer)
            installedOnView = targetView
            #if DEBUG
            NSLog(
                "[PianoRollTwoFingerPan] attached to=%@",
                String(describing: type(of: targetView))
            )
            #endif
        }

        private func scheduleAttachRetry() {
            guard attachRetryCount < 25 else { return }
            attachRetryWorkItem?.cancel()
            attachRetryCount += 1
            let retryIndex = attachRetryCount
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                #if DEBUG
                NSLog("[PianoRollTwoFingerPan] attach retry #%ld", retryIndex)
                #endif
                self.attachRecognizerIfNeeded()
            }
            attachRetryWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }

        private func nearestScrollView(from view: UIView) -> UIView? {
            var current: UIView? = view.superview
            while let candidate = current {
                if candidate is UIScrollView {
                    return candidate
                }
                current = candidate.superview
            }
            return nil
        }

        @objc
        func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let hostView else { return }
            let location = recognizer.location(in: hostView)

            switch recognizer.state {
            case .began:
                handlePanBegan(location: location)
            case .changed:
                handlePanChanged(recognizer: recognizer, location: location, hostView: hostView)
            case .ended, .cancelled, .failed:
                handlePanEnded(recognizer: recognizer, location: location)
            default:
                break
            }
        }

        private func handlePanBegan(location: CGPoint) {
            onActiveChanged(true)
            startPoint = location
        }

        private func handlePanChanged(
            recognizer: UIPanGestureRecognizer,
            location: CGPoint,
            hostView: UIView
        ) {
            guard recognizer.numberOfTouches == 2 else { return }
            if mode == .undecided {
                let translation = recognizer.translation(in: hostView)
                let distance = sqrt(translation.x * translation.x + translation.y * translation.y)
                if distance > 15 {
                    mode = .recting
                    #if DEBUG
                    NSLog("[PianoRollTwoFingerPan] locked into mode=recting (dist=%.2f)", distance)
                    #endif
                }
            }
            if mode == .recting {
                lastTwoTouchLocation = location
                if let startPoint {
                    onChanged(startPoint, location)
                }
            }
        }

        private func handlePanEnded(
            recognizer: UIPanGestureRecognizer,
            location: CGPoint
        ) {
            if mode == .recting {
                let commitLocation = lastTwoTouchLocation ?? location
                if let startPoint {
                    onEnded(startPoint, commitLocation)
                }
            }
            checkAllGesturesEnded()
        }

        @objc
        func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onActiveChanged(true)
            case .changed:
                if mode == .undecided {
                    let scaleChange = abs(recognizer.scale - 1.0)
                    if scaleChange > 0.05 {
                        mode = .zooming
                        #if DEBUG
                        NSLog("[PianoRollTwoFingerPan] locked into mode=zooming (scale=%.4f)", recognizer.scale)
                        #endif
                    }
                }

                if mode == .zooming {
                    let delta = recognizer.scale - 1.0
                    onPinchChanged(delta)
                    recognizer.scale = 1.0
                }
            case .ended, .cancelled, .failed:
                if mode == .zooming {
                    onPinchEnded()
                }
                checkAllGesturesEnded()
            default:
                break
            }
        }

        private func checkAllGesturesEnded() {
            let panActive = panRecognizer.state == .began || panRecognizer.state == .changed
            let pinchActive = pinchRecognizer.state == .began || pinchRecognizer.state == .changed
            if !panActive && !pinchActive {
                onActiveChanged(false)
                mode = .undecided
                startPoint = nil
                lastTwoTouchLocation = nil
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            #if DEBUG
            NSLog(
                "[PianoRollTwoFingerPan] simultaneous self=%@ other=%@",
                String(describing: type(of: gestureRecognizer)),
                String(describing: type(of: otherGestureRecognizer))
            )
            #endif
            return true
        }
    }
}

#endif
