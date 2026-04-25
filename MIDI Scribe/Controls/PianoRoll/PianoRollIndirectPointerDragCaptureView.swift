import SwiftUI

#if os(iOS)
import UIKit

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
            _: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
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
