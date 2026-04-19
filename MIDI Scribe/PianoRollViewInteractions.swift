import SwiftUI

struct ScrubDragAutoScrollContext {
    let rollWidth: CGFloat
    let layoutWidth: CGFloat
    let viewportFrameInGlobal: CGRect
}

extension PianoRollView {
    func handleScrubDrag(
        value: DragGesture.Value,
        pixelsPerSecond: CGFloat,
        proxy: ScrollViewProxy,
        autoScrollContext: ScrubDragAutoScrollContext
    ) {
        if dragStartOffset == nil {
            dragStartOffset = currentPlaybackOffset
            scrubLastDragTranslationWidth = 0
        }
        guard dragStartOffset != nil else { return }
        guard pixelsPerSecond > 0 else { return }

        let previousTranslationWidth = scrubLastDragTranslationWidth ?? value.translation.width
        let translationDelta = value.translation.width - previousTranslationWidth
        scrubLastDragTranslationWidth = value.translation.width
        let offsetDelta = TimeInterval(translationDelta / pixelsPerSecond)
        let newOffset = min(take.duration, max(0, currentPlaybackOffset + offsetDelta))
        syncScrubOffset(to: newOffset)

        let currentlyIntersected = intersectedNoteIDs(at: newOffset)
        playScrubTransitions(
            enteredIDs: currentlyIntersected.subtracting(dragIntersectedNotes),
            exitedIDs: dragIntersectedNotes.subtracting(currentlyIntersected)
        )
        dragIntersectedNotes = currentlyIntersected
        updateScrubAutoScrollState(
            dragLocationInGlobal: value.location,
            autoScrollContext: autoScrollContext
        )
        autoScrollIfScrubbingAtViewportEdge(proxy: proxy)
    }

    func handleScrubEnd() {
        dragStartOffset = nil
        playScrubTransitions(enteredIDs: [], exitedIDs: dragIntersectedNotes)
        dragIntersectedNotes.removeAll()
        scrubEdgeAutoScrollDirection = 0
        scrubLastDragTranslationWidth = nil
    }

    func handleRollTap(
        at location: CGPoint,
        rollWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        viewHeight _: CGFloat,
        playOffset: TimeInterval
    ) {
        guard !isLive, pixelsPerSecond > 0, rollWidth > 0 else { return }
        guard location.x.isFinite, location.y.isFinite else { return }
        guard !isTapOnScrubHandle(location, pixelsPerSecond: pixelsPerSecond, playOffset: playOffset) else { return }

        let timelinePixelWidth = max(0, rollWidth - Self.timelineLeadingInset)
        let timelineX = min(max(0, location.x - Self.timelineLeadingInset), timelinePixelWidth)
        let tappedOffset = min(take.duration, max(0, TimeInterval(timelineX / pixelsPerSecond)))
        seekPlayback(to: snappedSeekOffset(forTappedOffset: tappedOffset))
    }

    private func syncScrubOffset(to offset: TimeInterval) {
        viewModel.playbackEngine.updatePausedOffset(to: offset, takeID: take.id)
        if viewModel.playbackEngine.currentTakeID != take.id {
            localScrubOffset = offset
        }
    }

    private func updateScrubAutoScrollState(
        dragLocationInGlobal: CGPoint,
        autoScrollContext: ScrubDragAutoScrollContext
    ) {
        guard autoScrollContext.rollWidth > autoScrollContext.layoutWidth else {
            scrubEdgeAutoScrollDirection = 0
            return
        }
        let edgeThreshold: CGFloat = 36
        let leftTriggerX = autoScrollContext.viewportFrameInGlobal.minX + edgeThreshold
        let rightTriggerX = autoScrollContext.viewportFrameInGlobal.maxX - edgeThreshold
        if dragLocationInGlobal.x <= leftTriggerX {
            scrubEdgeAutoScrollDirection = -1
        } else if dragLocationInGlobal.x >= rightTriggerX {
            scrubEdgeAutoScrollDirection = 1
        } else {
            scrubEdgeAutoScrollDirection = 0
        }
    }

    func continueScrubAutoScrollIfNeeded(
        proxy: ScrollViewProxy,
        pixelsPerSecond: CGFloat,
        autoScrollContext: ScrubDragAutoScrollContext
    ) {
        guard dragStartOffset != nil else { return }
        guard autoScrollContext.rollWidth > autoScrollContext.layoutWidth else { return }
        guard scrubEdgeAutoScrollDirection != 0 else { return }
        guard pixelsPerSecond > 0 else { return }

        // Keep advancing while the pointer remains pressed at an edge.
        let pixelsPerFrame: CGFloat = 12
        let offsetDelta = TimeInterval((scrubEdgeAutoScrollDirection * pixelsPerFrame) / pixelsPerSecond)
        let targetOffset = min(take.duration, max(0, currentPlaybackOffset + offsetDelta))
        guard targetOffset != currentPlaybackOffset else { return }

        syncScrubOffset(to: targetOffset)
        let currentlyIntersected = intersectedNoteIDs(at: targetOffset)
        playScrubTransitions(
            enteredIDs: currentlyIntersected.subtracting(dragIntersectedNotes),
            exitedIDs: dragIntersectedNotes.subtracting(currentlyIntersected)
        )
        dragIntersectedNotes = currentlyIntersected
        autoScrollIfScrubbingAtViewportEdge(proxy: proxy)
    }

    private func autoScrollIfScrubbingAtViewportEdge(proxy: ScrollViewProxy) {
        if scrubEdgeAutoScrollDirection < 0 {
            proxy.scrollTo("playhead", anchor: .leading)
        } else if scrubEdgeAutoScrollDirection > 0 {
            proxy.scrollTo("playhead", anchor: .trailing)
        }
    }

    private func intersectedNoteIDs(at offset: TimeInterval) -> Set<UUID> {
        var intersectedIDs: Set<UUID> = []
        for note in notes where intersectedIDs.count < Self.maxConcurrentScrubAuditionNotes {
            if offset >= note.startOffset, offset <= (note.startOffset + note.duration) {
                intersectedIDs.insert(note.id)
            }
        }
        return intersectedIDs
    }

    private func playScrubTransitions(enteredIDs: Set<UUID>, exitedIDs: Set<UUID>) {
        for noteID in enteredIDs {
            guard let note = notes.first(where: { $0.id == noteID }) else { continue }
            emitScrubEvent(for: note, kind: .noteOn, velocity: note.velocity)
        }
        for noteID in exitedIDs {
            guard let note = notes.first(where: { $0.id == noteID }) else { continue }
            emitScrubEvent(for: note, kind: .noteOff, velocity: 0)
        }
    }

    private func emitScrubEvent(for note: PianoRollNote, kind: MIDIChannelEventKind, velocity: UInt8) {
        guard let channelNibble = midiChannelNibble(for: note.channel) else { return }
        let statusBase: UInt8 = kind == .noteOn ? 0x90 : 0x80
        let event = RecordedMIDIEvent(
            receivedAt: Date(),
            offsetFromTakeStart: 0,
            kind: kind,
            channel: note.channel,
            status: UInt8(statusBase | channelNibble),
            data1: note.pitch & 0x7F,
            data2: velocity & 0x7F
        )
        viewModel.playbackEngine.playScrubEvent(event, target: viewModel.selectedPlaybackTarget)
    }

    private func isTapOnScrubHandle(
        _ location: CGPoint,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) -> Bool {
        guard !isTakePlaying else { return false }
        let playheadX = Self.timelineLeadingInset + (CGFloat(playOffset) * pixelsPerSecond)
        let scrubHandleCenterY = 12 + Self.playheadKnobVerticalOffset
        let scrubHandleCenter = CGPoint(x: playheadX, y: scrubHandleCenterY)
        let deltaX = location.x - scrubHandleCenter.x
        let deltaY = location.y - scrubHandleCenter.y
        let distance = (deltaX * deltaX + deltaY * deltaY).squareRoot()
        return distance <= 18
    }

    private func seekPlayback(to offset: TimeInterval) {
        let wasPlaying = isTakePlaying
        if wasPlaying {
            viewModel.playbackEngine.pause()
        }
        viewModel.playbackEngine.updatePausedOffset(to: offset, takeID: take.id)
        localScrubOffset = offset
        if wasPlaying {
            viewModel.playbackEngine.togglePlayback(for: take, target: viewModel.selectedPlaybackTarget)
        }
    }

    private func snappedSeekOffset(forTappedOffset tappedOffset: TimeInterval) -> TimeInterval {
        let intersectedNotes = notes.filter { note in
            tappedOffset >= note.startOffset && tappedOffset <= (note.startOffset + note.duration)
        }
        return intersectedNotes.map(\.startOffset).min() ?? tappedOffset
    }

    private func midiChannelNibble(for channel: UInt8) -> UInt8? {
        guard channel >= 1, channel <= 16 else { return nil }
        return channel - 1
    }
}
