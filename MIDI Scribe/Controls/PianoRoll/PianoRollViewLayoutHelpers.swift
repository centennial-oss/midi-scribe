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

extension PianoRollView {
    /// Lime note bars on the roll when not under the playhead.
    var noteBarIdleColor: Color {
        // dark: 153, 255, 51,  light: 26, 128, 13
        colorScheme == .dark ? Color(red: 0.6, green: 1.0, blue: 0.2) : Color(red: 0.1, green: 0.5, blue: 0.05)
    }

    /// Pink / fuchsia note bars while the playhead is over the note.
    var noteBarPlayingColor: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.2, blue: 0.8) : Color(red: 0.9, green: 0.1, blue: 0.7)
    }

    var rollBackground: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.975)
    }

    /// Playhead line + scrub handle: orange in both modes.
    var playheadChrome: Color {
        Color.orange
    }

    /// Stroke around the clipped roll (`rollCornerRadius`).
    var rollBorderColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.6, green: 0.6, blue: 0.6)
    }

    var dragZoomShouldHandleInput: Bool {
        BuildInfo.isMac
    }
}
