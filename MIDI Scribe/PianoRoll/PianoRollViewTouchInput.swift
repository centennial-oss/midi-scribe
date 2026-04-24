import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PianoRollTouchInputContext {
    let rollWidth: CGFloat
    let layoutWidth: CGFloat
    let timelineLayoutWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let playOffset: TimeInterval
}

#if os(iOS)
extension PianoRollView {
    func makeTouchInputModifier(
        context: PianoRollTouchInputContext,
        isTwoFingerZoomDragActive: Binding<Bool>
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            context: context,
            isTwoFingerZoomDragActive: isTwoFingerZoomDragActive,
            onTap: { location, width, pxPerSec, offset in
                handleRollTap(
                    at: location,
                    rollWidth: width,
                    pixelsPerSecond: pxPerSec,
                    playOffset: offset
                )
            },
            onTwoFingerDragChanged: { start, location, width, pxPerSec, offset in
                handleRollPressChanged(
                    start: start,
                    location: location,
                    rollWidth: width,
                    pixelsPerSecond: pxPerSec,
                    playOffset: offset
                )
            },
            onTwoFingerDragEnded: { start, end, width, layout, timeline, pxPerSec, offset in
                handleRollPressEnded(
                    start: start,
                    end: end,
                    context: PianoRollDragZoomReleaseContext(
                        rollWidth: width,
                        layoutWidth: layout,
                        timelineLayoutWidth: timeline,
                        pixelsPerSecond: pxPerSec,
                        playOffset: offset
                    )
                )
            }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let context: PianoRollTouchInputContext
    @Binding var isTwoFingerZoomDragActive: Bool
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragEnded: (CGPoint, CGPoint, CGFloat, CGFloat, CGFloat, CGFloat, TimeInterval) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onTap(value.location, context.rollWidth, context.pixelsPerSecond, context.playOffset)
                        },
                    including: .all
                )
                .overlay {
                    PianoRollTwoFingerDragCaptureView(
                        onActiveChanged: { isActive in
                            isTwoFingerZoomDragActive = isActive
                            #if DEBUG
                            NSLog("[PianoRollTwoFingerPan] activeChanged=%@", isActive ? "true" : "false")
                            #endif
                        },
                        onChanged: { start, location in
                            onTwoFingerDragChanged(
                                start,
                                location,
                                context.rollWidth,
                                context.pixelsPerSecond,
                                context.playOffset
                            )
                        },
                        onEnded: { start, end in
                            onTwoFingerDragEnded(
                                start,
                                end,
                                context.rollWidth,
                                context.layoutWidth,
                                context.timelineLayoutWidth,
                                context.pixelsPerSecond,
                                context.playOffset
                            )
                        }
                    )
                }
        } else {
            content
        }
    }
}
#else
extension PianoRollView {
    func makeTouchInputModifier(
        context: PianoRollTouchInputContext,
        isTwoFingerZoomDragActive _: Binding<Bool>
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            context: context,
            isTwoFingerZoomDragActive: .constant(false),
            onTap: { _, _, _, _ in },
            onTwoFingerDragChanged: { _, _, _, _, _ in },
            onTwoFingerDragEnded: { _, _, _, _, _, _, _ in }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let context: PianoRollTouchInputContext
    @Binding var isTwoFingerZoomDragActive: Bool
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragEnded: (CGPoint, CGPoint, CGFloat, CGFloat, CGFloat, CGFloat, TimeInterval) -> Void

    func body(content: Content) -> some View { content }
}
#endif

#if os(iOS)
private struct PianoRollTwoFingerDragCaptureView: UIViewRepresentable {
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
        private lazy var panRecognizer: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
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
            guard let targetView = nearestScrollView(from: hostView) else { return }
            targetView.addGestureRecognizer(panRecognizer)
            installedOnView = targetView
            #if DEBUG
            NSLog(
                "[PianoRollTwoFingerPan] attached to=%@",
                String(describing: type(of: targetView))
            )
            #endif
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
            case .ended:
                handleEndedOrCancelled(location: location)
            case .cancelled, .failed:
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
            // iOS may cancel the two-finger pan when competing with
            // scroll recognizers at non-fit zoom. Commit using the
            // last stable two-touch location so drag-zoom still completes.
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
#endif
