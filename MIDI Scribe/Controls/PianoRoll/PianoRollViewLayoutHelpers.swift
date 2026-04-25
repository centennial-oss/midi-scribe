import SwiftUI

struct PlayheadGlobalXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

extension PianoRollView {
    @ViewBuilder
    func playheadMarkers(
        headX: CGFloat,
        rollWidth: CGFloat,
        viewHeight: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
                .frame(width: headX)
            Color.clear
                .frame(width: 1, height: viewHeight)
                .id("playhead")
                .background(
                    GeometryReader { playheadGeo in
                        Color.clear.preference(
                            key: PlayheadGlobalXPreferenceKey.self,
                            value: playheadGeo.frame(in: .global).midX
                        )
                    }
                )
            Spacer(minLength: 0)
        }
        zoomSelectionStartMarker(
            rollWidth: rollWidth,
            viewHeight: viewHeight,
            pixelsPerSecond: pixelsPerSecond
        )
    }

    func logZoomChangeDiagnostics(
        playOffset: TimeInterval,
        pixelsPerSecond: CGFloat,
        layoutWidth: CGFloat
    ) {
        #if DEBUG
        let debugPlayheadX = Self.timelineLeadingInset + (playOffset * pixelsPerSecond)
        let debugViewportMidX = layoutWidth * 0.5
        NSLog(
            "[PianoRollZoomChange] zoom=%.4f play=%.4f playX=%.2f viewportMidX=%.2f " +
                "centerAfter=%@ skipPaused=%@",
            zoomLevel,
            playOffset,
            debugPlayheadX,
            debugViewportMidX,
            shouldCenterPlayheadAfterDragZoom ? "true" : "false",
            skipNextPausedZoomCentering ? "true" : "false"
        )
        #endif
    }

    @ViewBuilder
    func zoomSelectionStartMarker(
        rollWidth: CGFloat,
        viewHeight: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> some View {
        if let dragZoomSelectionStartOffset {
            let dragStartX = Self.timelineLeadingInset + (dragZoomSelectionStartOffset * pixelsPerSecond)
            let clampedX = min(max(Self.timelineLeadingInset, dragStartX), rollWidth)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .frame(width: clampedX)
                Color.clear
                    .frame(width: 1, height: viewHeight)
                    .id("dragZoomSelectionStart")
                Spacer(minLength: 0)
            }
        }
    }
}
