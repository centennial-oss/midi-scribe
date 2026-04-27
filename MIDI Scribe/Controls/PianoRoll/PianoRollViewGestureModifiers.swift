import SwiftUI

struct ThreeFingerZoomActivationAnchorModifier: ViewModifier {
    let isActive: Bool
    let viewportFrameInGlobal: CGRect
    let onActivated: (Bool, CGRect) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: isActive) { _, nextIsActive in
            onActivated(nextIsActive, viewportFrameInGlobal)
        }
    }
}

struct DragZoomGestureModifier<G: Gesture>: ViewModifier {
    let isEnabled: Bool
    let gesture: G
    let including: GestureMask

    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(gesture, including: including)
        } else {
            content
        }
    }
}
