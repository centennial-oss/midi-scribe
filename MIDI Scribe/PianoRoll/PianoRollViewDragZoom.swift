import SwiftUI

struct PianoRollDragZoomReleaseContext {
    let rollWidth: CGFloat
    let layoutWidth: CGFloat
    let timelineLayoutWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let playOffset: TimeInterval
}

struct PianoRollDragZoomSelection {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }
    var midpoint: TimeInterval { (start + end) / 2 }
}

extension PianoRollView {
    private static let minimumDragZoomWidthFraction: CGFloat = 0.01
    private static let maximumForgivenDragWidth: CGFloat = 10
    private static let dragZoomVerticalInset: CGFloat = 3

    func dragZoomGesture(
        rollWidth: CGFloat,
        layoutWidth: CGFloat,
        timelineLayoutWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                handleRollPressChanged(
                    value: value,
                    rollWidth: rollWidth,
                    pixelsPerSecond: pixelsPerSecond,
                    playOffset: playOffset
                )
            }
            .onEnded { value in
                handleRollPressEnded(
                    value: value,
                    context: PianoRollDragZoomReleaseContext(
                        rollWidth: rollWidth,
                        layoutWidth: layoutWidth,
                        timelineLayoutWidth: timelineLayoutWidth,
                        pixelsPerSecond: pixelsPerSecond,
                        playOffset: playOffset
                    )
                )
            }
    }

    @ViewBuilder
    func dragZoomSelectionOverlay(viewHeight: CGFloat) -> some View {
        if let dragZoomRect = dragZoomRect(viewHeight: viewHeight) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.18))
                .overlay {
                    Rectangle()
                        .stroke(
                            Color.accentColor.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                }
                .frame(width: dragZoomRect.width, height: dragZoomRect.height)
                .offset(x: dragZoomRect.minX, y: dragZoomRect.minY)
                .allowsHitTesting(false)
        }
    }

    func handleRollPressChanged(
        value: DragGesture.Value,
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) {
        handleRollPressChanged(
            start: value.startLocation,
            location: value.location,
            rollWidth: rollWidth,
            pixelsPerSecond: pixelsPerSecond,
            playOffset: playOffset
        )
    }

    func handleRollPressChanged(
        start: CGPoint,
        location: CGPoint,
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) {
        guard !isLive, pixelsPerSecond > 0, rollWidth > 0 else { return }
        guard !isTakePlaying else { return }
        guard start.x.isFinite, start.y.isFinite else { return }

        if dragZoomStartLocation == nil {
            guard !isTapOnScrubHandle(
                start,
                pixelsPerSecond: pixelsPerSecond,
                playOffset: playOffset
            ) else { return }
            dragZoomStartLocation = start
            dragZoomCurrentLocation = start
            shouldCenterPlayheadAfterDragZoom = false
        }

        guard dragZoomStartLocation != nil else { return }
        guard location.x.isFinite, location.y.isFinite else { return }
        dragZoomCurrentLocation = location
    }

    func handleRollPressEnded(
        value: DragGesture.Value,
        context: PianoRollDragZoomReleaseContext
    ) {
        handleRollPressEnded(
            start: dragZoomStartLocation ?? value.startLocation,
            end: dragZoomCurrentLocation ?? value.location,
            context: context
        )
    }

    func handleRollPressEnded(
        start: CGPoint,
        end: CGPoint,
        context: PianoRollDragZoomReleaseContext
    ) {
        defer { resetDragZoomState() }
        guard shouldHandleRollPressEnd(start: start, context: context) else { return }
        guard end.x.isFinite, end.y.isFinite else { return }

        let dragWidth = abs(end.x - start.x)
        let forgivenDragWidth = min(
            max(1, context.layoutWidth * Self.minimumDragZoomWidthFraction),
            Self.maximumForgivenDragWidth
        )
        logDragZoomRelease(startX: start.x, endX: end.x, dragWidth: dragWidth, forgivenDragWidth: forgivenDragWidth)
        if dragWidth < forgivenDragWidth {
            handleRollTap(
                at: start,
                rollWidth: context.rollWidth,
                pixelsPerSecond: context.pixelsPerSecond,
                playOffset: context.playOffset
            )
            logDragZoomOutcomeTap()
            return
        }

        let selection = normalizedDragZoomSelection(
            startX: start.x,
            endX: end.x,
            rollWidth: context.rollWidth,
            pixelsPerSecond: context.pixelsPerSecond
        )
        applyDragZoomSelection(selection: selection, context: context)
    }

    private func handleRollPressEndedWhilePlaying(
        start: CGPoint,
        context: PianoRollDragZoomReleaseContext
    ) -> Bool {
        guard isTakePlaying else { return false }
        handleRollTap(
            at: start,
            rollWidth: context.rollWidth,
            pixelsPerSecond: context.pixelsPerSecond,
            playOffset: context.playOffset
        )
        return true
    }

    func dragZoomRect(viewHeight: CGFloat) -> CGRect? {
        guard let start = dragZoomStartLocation, let current = dragZoomCurrentLocation else { return nil }
        let minX = min(start.x, current.x)
        let maxX = max(start.x, current.x)
        let verticalInset = Self.dragZoomVerticalInset
        let insetHeight = max(0, viewHeight - (verticalInset * 2))
        return CGRect(x: minX, y: verticalInset, width: max(0, maxX - minX), height: insetHeight)
    }

    private func resetDragZoomState() {
        dragZoomStartLocation = nil
        dragZoomCurrentLocation = nil
    }

    private func normalizedDragZoomSelection(
        startX: CGFloat,
        endX: CGFloat,
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat
    ) -> PianoRollDragZoomSelection {
        let timelinePixelWidth = max(0, rollWidth - Self.timelineLeadingInset)
        let clampedStartX = min(max(0, startX - Self.timelineLeadingInset), timelinePixelWidth)
        let clampedEndX = min(max(0, endX - Self.timelineLeadingInset), timelinePixelWidth)
        let startOffset = min(take.duration, max(0, TimeInterval(clampedStartX / pixelsPerSecond)))
        let endOffset = min(take.duration, max(0, TimeInterval(clampedEndX / pixelsPerSecond)))
        return PianoRollDragZoomSelection(
            start: min(startOffset, endOffset),
            end: max(startOffset, endOffset)
        )
    }

    private func zoomLevel(
        for selection: PianoRollDragZoomSelection,
        timelineLayoutWidth: CGFloat
    ) -> CGFloat {
        let secondsLength = max(0.01, take.duration)
        let minPixelsPerSecond = timelineLayoutWidth / secondsLength
        let maxPixelsPerSecond = timelineLayoutWidth / 5.0
        let desiredPixelsPerSecond = timelineLayoutWidth / CGFloat(selection.duration)

        guard secondsLength >= 5.0, maxPixelsPerSecond > minPixelsPerSecond else {
            return 0.0
        }

        return max(
            0.0,
            min(
                1.0,
                (desiredPixelsPerSecond - minPixelsPerSecond) /
                    (maxPixelsPerSecond - minPixelsPerSecond)
            )
        )
    }

    private func logDragZoomRelease(
        startX: CGFloat,
        endX: CGFloat,
        dragWidth: CGFloat,
        forgivenDragWidth: CGFloat
    ) {
        #if DEBUG
        NSLog(
            "[PianoRollDragZoom] release startX=%.2f endX=%.2f dragWidth=%.4f forgivenWidth=%.4f",
            startX,
            endX,
            dragWidth,
            forgivenDragWidth
        )
        #endif
    }

    private func logDragZoomOutcomeTap() {
        #if DEBUG
        NSLog("[PianoRollDragZoom] outcome=tap")
        #endif
    }

    private func logDragZoomOutcomeCommit(
        selection: PianoRollDragZoomSelection,
        snappedSelection: PianoRollDragZoomSelection,
        nextZoomLevel: CGFloat,
        playheadWasInsideSelection: Bool
    ) {
        #if DEBUG
        NSLog(
            "[PianoRollDragZoom] outcome=commit selStart=%.4f selEnd=%.4f snappedStart=%.4f " +
                "nextZoom=%.4f playheadInside=%@",
            selection.start,
            selection.end,
            snappedSelection.start,
            nextZoomLevel,
            playheadWasInsideSelection ? "true" : "false"
        )
        #endif
    }

    private func applyDragZoomSelection(
        selection: PianoRollDragZoomSelection,
        context: PianoRollDragZoomReleaseContext
    ) {
        guard selection.duration > 0 else {
            #if DEBUG
            NSLog(
                "[PianoRollDragZoom] outcome=abort reason=zeroSelection selStart=%.4f selEnd=%.4f",
                selection.start,
                selection.end
            )
            #endif
            return
        }
        let effectiveSelection = selection
        let nextZoomLevel = zoomLevel(for: effectiveSelection, timelineLayoutWidth: context.timelineLayoutWidth)
        let playheadWasInsideSelection =
            context.playOffset >= effectiveSelection.start && context.playOffset <= effectiveSelection.end
        logDragZoomPreCommit(
            effectiveSelection: effectiveSelection,
            nextZoomLevel: nextZoomLevel,
            context: context,
            playheadWasInsideSelection: playheadWasInsideSelection
        )
        if !playheadWasInsideSelection {
            let snappedSeek = snappedSeekOffset(forTappedOffset: effectiveSelection.start)
            let clampedSeek = min(max(snappedSeek, effectiveSelection.start), effectiveSelection.end)
            seekPlayback(to: clampedSeek)
            delayPlaybackCenteringUntilCenter = true
        } else {
            let selectionMidpoint = (effectiveSelection.start + effectiveSelection.end) * 0.5
            delayPlaybackCenteringUntilCenter = context.playOffset < selectionMidpoint
        }
        // Preserve the user-selected zoom window; do not auto-center
        // when selection already includes the playhead.
        shouldCenterPlayheadAfterDragZoom = false
        logDragZoomOutcomeCommit(
            selection: selection,
            snappedSelection: effectiveSelection,
            nextZoomLevel: nextZoomLevel,
            playheadWasInsideSelection: playheadWasInsideSelection
        )
        dragZoomSelectionStartOffset = effectiveSelection.start
        shouldAnchorDragZoomSelectionStart = true
        skipNextPausedZoomCentering = true
        zoomLevel = nextZoomLevel
        logDragZoomPostCommit(
            shouldCenterAfter: shouldCenterPlayheadAfterDragZoom,
            skipPausedCenter: skipNextPausedZoomCentering,
            delayPlaybackCenter: delayPlaybackCenteringUntilCenter
        )
    }

    private func logDragZoomPreCommit(
        effectiveSelection: PianoRollDragZoomSelection,
        nextZoomLevel: CGFloat,
        context: PianoRollDragZoomReleaseContext,
        playheadWasInsideSelection: Bool
    ) {
        #if DEBUG
        let selectionMidpoint = (effectiveSelection.start + effectiveSelection.end) * 0.5
        let selectionHalfDuration = effectiveSelection.duration * 0.5
        let playheadDeltaFromMid = context.playOffset - selectionMidpoint
        let normalizedPlayheadPosition = selectionHalfDuration > 0
            ? (playheadDeltaFromMid / selectionHalfDuration)
            : 0
        NSLog(
            "[PianoRollDragZoom] pre-commit zoom=%.4f->%.4f play=%.4f inside=%@ " +
                "selStart=%.4f selEnd=%.4f selDur=%.4f playDeltaMid=%.4f playNorm=%.4f " +
                "layoutW=%.2f rollW=%.2f pxPerSec=%.4f",
            zoomLevel,
            nextZoomLevel,
            context.playOffset,
            playheadWasInsideSelection ? "true" : "false",
            effectiveSelection.start,
            effectiveSelection.end,
            effectiveSelection.duration,
            playheadDeltaFromMid,
            normalizedPlayheadPosition,
            context.layoutWidth,
            context.rollWidth,
            context.pixelsPerSecond
        )
        #endif
    }

    private func logDragZoomPostCommit(
        shouldCenterAfter: Bool,
        skipPausedCenter: Bool,
        delayPlaybackCenter: Bool
    ) {
        #if DEBUG
        NSLog(
            "[PianoRollDragZoom] post-commit flags centerAfter=%@ skipPausedCenter=%@ delayPlaybackCenter=%@",
            shouldCenterAfter ? "true" : "false",
            skipPausedCenter ? "true" : "false",
            delayPlaybackCenter ? "true" : "false"
        )
        #endif
    }

    private func shouldHandleRollPressEnd(
        start: CGPoint,
        context: PianoRollDragZoomReleaseContext
    ) -> Bool {
        guard !isLive,
              context.pixelsPerSecond > 0,
              context.rollWidth > 0,
              context.timelineLayoutWidth > 0 else { return false }
        guard start.x.isFinite, start.y.isFinite else { return false }
        guard !isTapOnScrubHandle(
            start,
            pixelsPerSecond: context.pixelsPerSecond,
            playOffset: context.playOffset
        ) else { return false }
        if handleRollPressEndedWhilePlaying(start: start, context: context) { return false }
        return true
    }
}
