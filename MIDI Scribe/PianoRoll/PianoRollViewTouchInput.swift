import SwiftUI

#if os(iOS)
extension PianoRollView {
    func makeTouchInputModifier(
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            rollWidth: rollWidth,
            pixelsPerSecond: pixelsPerSecond,
            playOffset: playOffset,
            onTap: { location, width, pxPerSec, offset in
                handleRollTap(
                    at: location,
                    rollWidth: width,
                    pixelsPerSecond: pxPerSec,
                    playOffset: offset
                )
            }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let rollWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let playOffset: TimeInterval
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            onTap(value.location, rollWidth, pixelsPerSecond, playOffset)
                        },
                    including: .all
                )
        } else {
            content
        }
    }
}
#else
extension PianoRollView {
    func makeTouchInputModifier(
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            rollWidth: rollWidth,
            pixelsPerSecond: pixelsPerSecond,
            playOffset: playOffset,
            onTap: { _, _, _, _ in }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let rollWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let playOffset: TimeInterval
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void

    func body(content: Content) -> some View { content }
}
#endif
