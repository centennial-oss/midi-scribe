import SwiftUI

#if os(iOS)
import UIKit

struct PianoRollTwoFingerDragCaptureView: UIViewRepresentable {
    let onActiveChanged: (Bool) -> Void
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveChanged: onActiveChanged, onChanged: onChanged, onEnded: onEnded)
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
            onEnded: onEnded
        )
        context.coordinator.attachRecognizerIfNeeded()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActiveChanged: (Bool) -> Void
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void
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

        init(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func updateHandlers(
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void
        ) {
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
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
            let touchCount = recognizer.numberOfTouches
            #if DEBUG
            let translation = recognizer.translation(in: hostView)
            NSLog(
                "[PianoRollTwoFingerPan] state=%ld touches=%ld x=%.2f y=%.2f tx=%.2f ty=%.2f",
                recognizer.state.rawValue,
                touchCount,
                location.x,
                location.y,
                translation.x,
                translation.y
            )
            #endif
            switch recognizer.state {
            case .began:
                handleBegan(location: location, touchCount: touchCount)
            case .changed:
                handleChanged(location: location, touchCount: touchCount)
            case .ended, .cancelled, .failed:
                handleEndedOrCancelled(location: location)
            default:
                break
            }
        }

        private func handleBegan(location: CGPoint, touchCount: Int) {
            onActiveChanged(true)
            startPoint = location
            guard touchCount == 2 else { return }
            lastTwoTouchLocation = location
            onChanged(location, location)
        }

        private func handleChanged(location: CGPoint, touchCount: Int) {
            guard touchCount == 2 else { return }
            lastTwoTouchLocation = location
            if let startPoint {
                onChanged(startPoint, location)
            }
        }

        private func handleEndedOrCancelled(location: CGPoint) {
            let commitLocation = lastTwoTouchLocation ?? location
            if let startPoint {
                onEnded(startPoint, commitLocation)
            }
            onActiveChanged(false)
            startPoint = nil
            lastTwoTouchLocation = nil
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

struct PianoRollThreeFingerSwipeCaptureView: UIViewRepresentable {
    let onActiveChanged: (Bool) -> Void
    let onChanged: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onActiveChanged: onActiveChanged, onChanged: onChanged)
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
        context.coordinator.updateHandlers(onActiveChanged: onActiveChanged, onChanged: onChanged)
        context.coordinator.attachRecognizerIfNeeded()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onActiveChanged: (Bool) -> Void
        var onChanged: (CGFloat) -> Void
        weak var hostView: UIView?
        weak var installedOnView: UIView?
        private var lastTranslationX: CGFloat = 0
        private var attachRetryCount = 0
        private var attachRetryWorkItem: DispatchWorkItem?
        private lazy var panRecognizer: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 3
            pan.maximumNumberOfTouches = 3
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            return pan
        }()

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

        func attachRecognizerIfNeeded() {
            guard let hostView else { return }
            guard installedOnView == nil else { return }
            guard let targetView = nearestScrollView(from: hostView) else {
                #if DEBUG
                NSLog("[PianoRollThreeFingerPan] attach skipped: no scroll view in ancestor chain")
                #endif
                scheduleAttachRetry()
                return
            }
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            attachRetryCount = 0
            targetView.addGestureRecognizer(panRecognizer)
            installedOnView = targetView
            #if DEBUG
            NSLog(
                "[PianoRollThreeFingerPan] attached to=%@",
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
                NSLog("[PianoRollThreeFingerPan] attach retry #%ld", retryIndex)
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
            let translation = recognizer.translation(in: hostView)
            let touchCount = recognizer.numberOfTouches
            #if DEBUG
            NSLog(
                "[PianoRollThreeFingerPan] state=%ld touches=%ld tx=%.2f",
                recognizer.state.rawValue,
                touchCount,
                translation.x
            )
            #endif
            switch recognizer.state {
            case .began:
                onActiveChanged(true)
                lastTranslationX = translation.x
            case .changed:
                guard touchCount == 3 else {
                    #if DEBUG
                    NSLog("[PianoRollThreeFingerPan] ignoring changed state with touchCount=%ld", touchCount)
                    #endif
                    return
                }
                let deltaX = translation.x - lastTranslationX
                lastTranslationX = translation.x
                if deltaX.isFinite, deltaX != 0 {
                    onChanged(deltaX)
                }
            case .ended, .cancelled, .failed:
                onActiveChanged(false)
                lastTranslationX = 0
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            #if DEBUG
            NSLog(
                "[PianoRollThreeFingerPan] simultaneous self=%@ other=%@",
                String(describing: type(of: gestureRecognizer)),
                String(describing: type(of: otherGestureRecognizer))
            )
            #endif
            return true
        }
    }
}

struct PianoRollIndirectPointerDragCaptureView: UIViewRepresentable {
    let shouldBeginAt: (CGPoint) -> Bool
    let onActiveChanged: (Bool) -> Void
    let onChanged: (CGPoint, CGPoint) -> Void
    let onEnded: (CGPoint, CGPoint) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            shouldBeginAt: shouldBeginAt,
            onActiveChanged: onActiveChanged,
            onChanged: onChanged,
            onEnded: onEnded
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
            shouldBeginAt: shouldBeginAt,
            onActiveChanged: onActiveChanged,
            onChanged: onChanged,
            onEnded: onEnded
        )
        context.coordinator.attachRecognizerIfNeeded()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var shouldBeginAt: (CGPoint) -> Bool
        var onActiveChanged: (Bool) -> Void
        var onChanged: (CGPoint, CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint) -> Void
        private var startPoint: CGPoint?
        private var lastLocation: CGPoint?
        weak var hostView: UIView?
        weak var installedOnView: UIView?
        private var attachRetryCount = 0
        private var attachRetryWorkItem: DispatchWorkItem?
        private lazy var panRecognizer: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            pan.delegate = self
            return pan
        }()

        init(
            shouldBeginAt: @escaping (CGPoint) -> Bool,
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void
        ) {
            self.shouldBeginAt = shouldBeginAt
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func updateHandlers(
            shouldBeginAt: @escaping (CGPoint) -> Bool,
            onActiveChanged: @escaping (Bool) -> Void,
            onChanged: @escaping (CGPoint, CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint) -> Void
        ) {
            self.shouldBeginAt = shouldBeginAt
            self.onActiveChanged = onActiveChanged
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func attachRecognizerIfNeeded() {
            guard let hostView else { return }
            guard installedOnView == nil else { return }
            guard let targetView = nearestScrollView(from: hostView) else {
                scheduleAttachRetry()
                return
            }
            attachRetryWorkItem?.cancel()
            attachRetryWorkItem = nil
            attachRetryCount = 0
            targetView.addGestureRecognizer(panRecognizer)
            installedOnView = targetView
        }

        private func scheduleAttachRetry() {
            guard attachRetryCount < 25 else { return }
            attachRetryWorkItem?.cancel()
            attachRetryCount += 1
            let workItem = DispatchWorkItem { [weak self] in
                self?.attachRecognizerIfNeeded()
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
                onActiveChanged(true)
                startPoint = location
                lastLocation = location
                onChanged(location, location)
            case .changed:
                lastLocation = location
                if let startPoint {
                    onChanged(startPoint, location)
                }
            case .ended, .cancelled, .failed:
                let commitLocation = lastLocation ?? location
                if let startPoint {
                    onEnded(startPoint, commitLocation)
                }
                onActiveChanged(false)
                startPoint = nil
                lastLocation = nil
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let hostView else { return true }
            let location = gestureRecognizer.location(in: hostView)
            return shouldBeginAt(location)
        }
    }
}
#endif
