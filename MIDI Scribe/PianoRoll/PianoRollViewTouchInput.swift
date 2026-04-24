import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
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
        isTwoFingerZoomDragActive: Binding<Bool>,
        isIndirectPointerDragActive: Binding<Bool>,
        isThreeFingerZoomSwipeActive: Binding<Bool>
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            context: context,
            isTwoFingerZoomDragActive: isTwoFingerZoomDragActive,
            isIndirectPointerDragActive: isIndirectPointerDragActive,
            isThreeFingerZoomSwipeActive: isThreeFingerZoomSwipeActive,
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
            },
            shouldBeginIndirectPointerDragAt: { location, pxPerSec, offset in
                !isTapOnScrubHandle(
                    location,
                    pixelsPerSecond: pxPerSec,
                    playOffset: offset
                )
            },
            onIndirectPointerDragChanged: { start, location, width, pxPerSec, offset in
                let didAccept = handleRollPressChanged(
                    start: start,
                    location: location,
                    rollWidth: width,
                    pixelsPerSecond: pxPerSec,
                    playOffset: offset
                )
                isIndirectPointerDragActive.wrappedValue = didAccept
            },
            onThreeFingerSwipeChanged: { deltaX in
                handleThreeFingerSwipeZoom(deltaX: deltaX)
            }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let context: PianoRollTouchInputContext
    @Binding var isTwoFingerZoomDragActive: Bool
    @Binding var isIndirectPointerDragActive: Bool
    @Binding var isThreeFingerZoomSwipeActive: Bool
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragEnded: (CGPoint, CGPoint, CGFloat, CGFloat, CGFloat, CGFloat, TimeInterval) -> Void
    let shouldBeginIndirectPointerDragAt: (CGPoint, CGFloat, TimeInterval) -> Bool
    let onIndirectPointerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onThreeFingerSwipeChanged: (CGFloat) -> Void

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
                .overlay { iosGestureOverlay }
        } else {
            content
        }
    }

    @ViewBuilder
    private var iosGestureOverlay: some View {
        ZStack {
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
            PianoRollThreeFingerSwipeCaptureView(
                onActiveChanged: { isActive in
                    isThreeFingerZoomSwipeActive = isActive
                    #if DEBUG
                    NSLog("[PianoRollThreeFingerPan] activeChanged=%@", isActive ? "true" : "false")
                    #endif
                },
                onChanged: { deltaX in
                    onThreeFingerSwipeChanged(deltaX)
                }
            )
            PianoRollIndirectPointerDragCaptureView(
                shouldBeginAt: { location in
                    shouldBeginIndirectPointerDragAt(
                        location,
                        context.pixelsPerSecond,
                        context.playOffset
                    )
                },
                onActiveChanged: { isActive in
                    if !isActive {
                        isIndirectPointerDragActive = false
                    }
                },
                onChanged: { start, location in
                    onIndirectPointerDragChanged(
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
    }
}
#elseif os(macOS)
extension PianoRollView {
    func makeTouchInputModifier(
        context: PianoRollTouchInputContext,
        isTwoFingerZoomDragActive _: Binding<Bool>,
        isIndirectPointerDragActive _: Binding<Bool>,
        isThreeFingerZoomSwipeActive: Binding<Bool>
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            context: context,
            isTwoFingerZoomDragActive: .constant(false),
            isIndirectPointerDragActive: .constant(false),
            isThreeFingerZoomSwipeActive: isThreeFingerZoomSwipeActive,
            onTap: { _, _, _, _ in },
            onTwoFingerDragChanged: { _, _, _, _, _ in },
            onTwoFingerDragEnded: { _, _, _, _, _, _, _ in },
            shouldBeginIndirectPointerDragAt: { _, _, _ in false },
            onIndirectPointerDragChanged: { _, _, _, _, _ in },
            onThreeFingerSwipeChanged: { deltaX in
                handleThreeFingerSwipeZoom(deltaX: deltaX)
            }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let context: PianoRollTouchInputContext
    @Binding var isTwoFingerZoomDragActive: Bool
    @Binding var isIndirectPointerDragActive: Bool
    @Binding var isThreeFingerZoomSwipeActive: Bool
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragEnded: (CGPoint, CGPoint, CGFloat, CGFloat, CGFloat, CGFloat, TimeInterval) -> Void
    let shouldBeginIndirectPointerDragAt: (CGPoint, CGFloat, TimeInterval) -> Bool
    let onIndirectPointerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onThreeFingerSwipeChanged: (CGFloat) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .overlay {
                    PianoRollMacThreeFingerSwipeCaptureView(
                        onActiveChanged: { isActive in
                            isThreeFingerZoomSwipeActive = isActive
                            #if DEBUG
                            NSLog("[PianoRollMacThreeFingerPan] activeChanged=%@", isActive ? "true" : "false")
                            #endif
                        },
                        onChanged: { deltaX in
                            onThreeFingerSwipeChanged(deltaX)
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
        isTwoFingerZoomDragActive _: Binding<Bool>,
        isIndirectPointerDragActive _: Binding<Bool>,
        isThreeFingerZoomSwipeActive _: Binding<Bool>
    ) -> PianoRollTouchInputModifier {
        PianoRollTouchInputModifier(
            isEnabled: !isLive,
            context: context,
            isTwoFingerZoomDragActive: .constant(false),
            isIndirectPointerDragActive: .constant(false),
            isThreeFingerZoomSwipeActive: .constant(false),
            onTap: { _, _, _, _ in },
            onTwoFingerDragChanged: { _, _, _, _, _ in },
            onTwoFingerDragEnded: { _, _, _, _, _, _, _ in },
            shouldBeginIndirectPointerDragAt: { _, _, _ in false },
            onIndirectPointerDragChanged: { _, _, _, _, _ in },
            onThreeFingerSwipeChanged: { _ in }
        )
    }
}

struct PianoRollTouchInputModifier: ViewModifier {
    let isEnabled: Bool
    let context: PianoRollTouchInputContext
    @Binding var isTwoFingerZoomDragActive: Bool
    @Binding var isIndirectPointerDragActive: Bool
    @Binding var isThreeFingerZoomSwipeActive: Bool
    let onTap: (CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onTwoFingerDragEnded: (CGPoint, CGPoint, CGFloat, CGFloat, CGFloat, CGFloat, TimeInterval) -> Void
    let shouldBeginIndirectPointerDragAt: (CGPoint, CGFloat, TimeInterval) -> Bool
    let onIndirectPointerDragChanged: (CGPoint, CGPoint, CGFloat, CGFloat, TimeInterval) -> Void
    let onThreeFingerSwipeChanged: (CGFloat) -> Void

    func body(content: Content) -> some View { content }
}
#endif
