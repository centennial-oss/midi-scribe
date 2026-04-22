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
        guard !isLive, pixelsPerSecond > 0, rollWidth > 0 else { return }
        guard !isTakePlaying else { return }
        let start = value.startLocation
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
            shouldAnchorPlayheadLeadingAfterDragZoom = false
        }

        guard dragZoomStartLocation != nil else { return }
        let location = value.location
        guard location.x.isFinite, location.y.isFinite else { return }
        dragZoomCurrentLocation = location
    }

    func handleRollPressEnded(
        value: DragGesture.Value,
        context: PianoRollDragZoomReleaseContext
    ) {
        defer { resetDragZoomState() }

        guard !isLive,
              context.pixelsPerSecond > 0,
              context.rollWidth > 0,
              context.timelineLayoutWidth > 0 else { return }

        let start = dragZoomStartLocation ?? value.startLocation
        guard start.x.isFinite, start.y.isFinite else { return }
        guard !isTapOnScrubHandle(
            start,
            pixelsPerSecond: context.pixelsPerSecond,
            playOffset: context.playOffset
        ) else { return }

        if handleRollPressEndedWhilePlaying(start: start, context: context) { return }

        let end = dragZoomCurrentLocation ?? value.location
        guard end.x.isFinite, end.y.isFinite else { return }

        let dragWidth = abs(end.x - start.x)
        let forgivenDragWidth = min(
            max(1, context.layoutWidth * Self.minimumDragZoomWidthFraction),
            Self.maximumForgivenDragWidth
        )
        if dragWidth < forgivenDragWidth {
            handleRollTap(
                at: start,
                rollWidth: context.rollWidth,
                pixelsPerSecond: context.pixelsPerSecond,
                playOffset: context.playOffset
            )
            return
        }

        let selection = normalizedDragZoomSelection(
            startX: start.x,
            endX: end.x,
            rollWidth: context.rollWidth,
            pixelsPerSecond: context.pixelsPerSecond
        )
        guard selection.duration > 0 else { return }

        let snappedSelection = snappedDragZoomSelectionStart(for: selection)
        guard snappedSelection.duration > 0 else { return }

        let nextZoomLevel = zoomLevel(for: snappedSelection, timelineLayoutWidth: context.timelineLayoutWidth)
        let playheadWasInsideSelection =
            context.playOffset >= snappedSelection.start && context.playOffset <= snappedSelection.end
        if !playheadWasInsideSelection {
            seekPlayback(to: snappedSelection.start)
            shouldAnchorPlayheadLeadingAfterDragZoom = true
        } else {
            shouldAnchorPlayheadLeadingAfterDragZoom = false
        }
        shouldCenterPlayheadAfterDragZoom = !shouldAnchorPlayheadLeadingAfterDragZoom
        zoomLevel = nextZoomLevel
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

    private func snappedDragZoomSelectionStart(
        for selection: PianoRollDragZoomSelection
    ) -> PianoRollDragZoomSelection {
        let snappedStart = snappedSeekOffset(forTappedOffset: selection.start)
        return PianoRollDragZoomSelection(
            start: min(snappedStart, selection.end),
            end: selection.end
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
}
