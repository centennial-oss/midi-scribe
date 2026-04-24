import SwiftUI

#if os(macOS)
import AppKit

struct TrackpadSwipeModifier: ViewModifier {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func body(content: Content) -> some View {
        content.overlay(
            TrackpadSwipeCaptureView(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
        )
    }
}

private struct TrackpadSwipeCaptureView: NSViewRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeNSView(context: Context) -> NSView {
        TrackpadNSView(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    class TrackpadNSView: NSView {
        var onSwipeLeft: () -> Void
        var onSwipeRight: () -> Void
        private var accumulatedX: CGFloat = 0
        private let threshold: CGFloat = 30 // Reduced for better responsiveness

        init(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) {
            self.onSwipeLeft = onSwipeLeft
            self.onSwipeRight = onSwipeRight
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func scrollWheel(with event: NSEvent) {
            // Check if it's a horizontal-dominant scroll
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                accumulatedX += event.scrollingDeltaX

                if accumulatedX < -threshold {
                    onSwipeLeft()
                    accumulatedX = 0
                } else if accumulatedX > threshold {
                    onSwipeRight()
                    accumulatedX = 0
                }
            } else {
                // For vertical scrolls, reset accumulation so a diagonal doesn't trigger it accidentally
                accumulatedX = 0
                super.scrollWheel(with: event)
            }

            // If the user has ended the gesture, reset
            if event.phase == .ended || event.momentumPhase == .ended {
                accumulatedX = 0
            }
        }
    }
}

extension View {
    func onTrackpadSwipe(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) -> some View {
        self.modifier(TrackpadSwipeModifier(onSwipeLeft: onSwipeLeft, onSwipeRight: onSwipeRight))
    }
}
#else
extension View {
    func onTrackpadSwipe(onSwipeLeft: @escaping () -> Void, onSwipeRight: @escaping () -> Void) -> some View {
        self
    }
}
#endif
