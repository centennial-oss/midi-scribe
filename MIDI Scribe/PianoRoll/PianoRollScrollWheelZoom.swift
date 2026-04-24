//
//  PianoRollScrollWheelZoom.swift
//  MIDI Scribe
//
//  Translates unmodified scroll-wheel events (from an external mouse)
//  into piano-roll zoom changes. SwiftUI's `MagnificationGesture`
//  handles trackpad pinch and the iPad pinch gesture, but not a mouse
//  scroll wheel on either macOS or iPadOS/iOS. This bridge fills that
//  gap. Shift+scroll is intentionally passed through so the existing
//  horizontal-scroll behavior is preserved on both platforms.
//

import SwiftUI

/// Cross-platform wrapper. Internally dispatches to the platform-native
/// implementation so callers can always attach the overlay without a
/// `#if os(...)` at the call site.
struct PianoRollScrollWheelZoom: View {
    @Binding var zoomLevel: CGFloat

    var body: some View {
        PlatformScrollWheelZoom(zoomLevel: $zoomLevel)
    }
}

// MARK: - macOS

#if os(macOS)
import AppKit

private struct PlatformScrollWheelZoom: NSViewRepresentable {
    @Binding var zoomLevel: CGFloat

    func makeNSView(context: Context) -> MacScrollWheelCatcherView {
        let view = MacScrollWheelCatcherView()
        view.onScroll = { deltaY in
            applyZoomDelta(deltaY, to: $zoomLevel.wrappedValue) { next in
                if next != zoomLevel { zoomLevel = next }
            }
        }
        return view
    }

    func updateNSView(_ nsView: MacScrollWheelCatcherView, context: Context) {}
}

final class MacScrollWheelCatcherView: NSView {
    var onScroll: ((CGFloat) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard shouldHandleZoom(for: event) else {
            super.scrollWheel(with: event)
            return
        }
        onScroll?(event.scrollingDeltaY)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only claim hit-testing for unmodified scroll-wheel events.
        // Modifier-held scrolls (e.g. Shift+scroll for horizontal
        // scrubbing) must fall through to the ScrollView beneath,
        // which requires us to return nil here; forwarding via
        // `super.scrollWheel` is not enough because AppKit dispatches
        // the event to whichever view hit-tests it.
        guard let event = NSApp.currentEvent, event.type == .scrollWheel else {
            return nil
        }
        if shouldHandleZoom(for: event) {
            return super.hitTest(point)
        }
        return nil
    }

    private func shouldHandleZoom(for event: NSEvent) -> Bool {
        guard !event.hasPreciseScrollingDeltas else {
            return false
        }
        guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else {
            return false
        }
        return abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
    }
}

#elseif os(iOS)
import UIKit

private struct PlatformScrollWheelZoom: UIViewRepresentable {
    @Binding var zoomLevel: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(zoomLevel: $zoomLevel) }

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        // `.discrete` covers mouse scroll-wheel notches. `.continuous`
        // covers trackpad two-finger scroll on iPadOS, which we also
        // want to handle for consistency. Modifier keys are filtered
        // out inside the coordinator so Shift+scroll (horizontal) is
        // left alone.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleScroll(_:))
        )
        pan.allowedScrollTypesMask = [.discrete, .continuous]
        pan.maximumNumberOfTouches = 0 // only indirect (mouse/trackpad) scrolls
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var zoomLevel: CGFloat
        private var lastTranslationX: CGFloat = 0
        private var lastTranslationY: CGFloat = 0

        init(zoomLevel: Binding<CGFloat>) {
            self._zoomLevel = zoomLevel
        }

        @objc func handleScroll(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.modifierFlags.rawValue != 0 {
                // Shift or other modifiers: let the system handle it
                // (horizontal scroll, etc.).
                return
            }

            switch recognizer.state {
            case .began:
                lastTranslationX = 0
                lastTranslationY = 0
            case .changed:
                let translation = recognizer.translation(in: recognizer.view)
                let deltaX = translation.x - lastTranslationX
                let deltaY = translation.y - lastTranslationY
                lastTranslationX = translation.x
                lastTranslationY = translation.y

                guard abs(deltaY) > abs(deltaX) else { return }
                applyZoomDelta(deltaY, to: zoomLevel) { next in
                    if next != self.zoomLevel { self.zoomLevel = next }
                }
            default:
                lastTranslationX = 0
                lastTranslationY = 0
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Don't fight the horizontal ScrollView or the playhead drag.
            true
        }
    }
}

/// Fully transparent UIView that doesn't intercept touches/clicks; only
/// its attached gesture recognizer sees events.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

#else

private struct PlatformScrollWheelZoom: View {
    @Binding var zoomLevel: CGFloat
    var body: some View { Color.clear.allowsHitTesting(false) }
}

#endif

/// Shared scaling logic so macOS and iOS produce comparable zoom
/// sensitivity for a given physical scroll notch.
private func applyZoomDelta(
    _ deltaY: CGFloat,
    to currentZoom: CGFloat,
    assign: (CGFloat) -> Void
) {
    // NSEvent / UIGestureRecognizer deltas are small, continuous floats
    // (often 0..5 per tick on a physical wheel). Scale down so a normal
    // flick produces a smooth, non-jumpy change across the 0...1 range.
    let scaled = deltaY * 0.001
    let next = max(0.0, min(1.0, currentZoom + scaled))
    assign(next)
}
