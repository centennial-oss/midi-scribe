import SwiftUI

struct ScrubDragAutoScrollContext {
    let rollWidth: CGFloat
    let layoutWidth: CGFloat
    let viewportFrameInGlobal: CGRect
}

struct ScrubAuditionDiagnostics {
    var startedUptime: TimeInterval?
    var suppressedFrames = 0
    var batches = 0
    var noteOnCount = 0
    var noteOffCount = 0
    var maxIntersectedNotes = 0
}

struct PianoRollModelSnapshot {
    let count: Int
    let signature: String
}

extension PianoRollView {
    private static let minimumScrubAuditionInterval: TimeInterval = 0.01

    func handleScrubDrag(
        value: DragGesture.Value,
        pixelsPerSecond: CGFloat,
        proxy: ScrollViewProxy,
        autoScrollContext: ScrubDragAutoScrollContext
    ) {
        if dragStartOffset == nil {
            dragStartOffset = currentPlaybackOffset
            scrubLastDragTranslationWidth = 0
            beginScrubAuditionDiagnostics(at: currentPlaybackOffset)
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
        auditionScrubNotes(currentlyIntersected)
        updateScrubAutoScrollState(
            dragLocationInGlobal: value.location,
            autoScrollContext: autoScrollContext
        )
        autoScrollIfScrubbingAtViewportEdge(proxy: proxy)
    }

    func handleScrubEnd() {
        logScrubAuditionSummary()
        dragStartOffset = nil
        viewModel.playbackEngine.stopScrubbingNotes()
        dragIntersectedNotes.removeAll()
        lastScrubAuditionUptime = nil
        resetScrubAuditionDiagnostics()
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
        auditionScrubNotes(currentlyIntersected)
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

    private func auditionScrubNotes(_ currentlyIntersected: Set<UUID>) {
        let now = ProcessInfo.processInfo.systemUptime
        scrubAuditionDiagnostics.maxIntersectedNotes = max(
            scrubAuditionDiagnostics.maxIntersectedNotes,
            currentlyIntersected.count
        )
        if let lastScrubAuditionUptime,
           now - lastScrubAuditionUptime < Self.minimumScrubAuditionInterval {
            scrubAuditionDiagnostics.suppressedFrames += 1
            return
        }

        let enteredIDs = currentlyIntersected.subtracting(dragIntersectedNotes)
        let exitedIDs = dragIntersectedNotes.subtracting(currentlyIntersected)
        playScrubTransitions(enteredIDs: enteredIDs, exitedIDs: exitedIDs)
        if !enteredIDs.isEmpty || !exitedIDs.isEmpty {
            scrubAuditionDiagnostics.batches += 1
            scrubAuditionDiagnostics.noteOnCount += enteredIDs.count
            scrubAuditionDiagnostics.noteOffCount += exitedIDs.count
        }
        dragIntersectedNotes = currentlyIntersected
        lastScrubAuditionUptime = now
    }

    private func playScrubTransitions(enteredIDs: Set<UUID>, exitedIDs: Set<UUID>) {
        for noteID in exitedIDs {
            guard let note = notes.first(where: { $0.id == noteID }) else { continue }
            emitScrubEvent(for: note, kind: .noteOff, velocity: 0)
        }
        for noteID in enteredIDs {
            guard let note = notes.first(where: { $0.id == noteID }) else { continue }
            emitScrubEvent(for: note, kind: .noteOn, velocity: note.velocity)
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

    private func beginScrubAuditionDiagnostics(at offset: TimeInterval) {
        resetScrubAuditionDiagnostics()
        scrubAuditionDiagnostics.startedUptime = ProcessInfo.processInfo.systemUptime
        print(
            "MIDI Scribe scrub audition started: " +
                "take=\(take.id) offset=\(String(format: "%.3f", offset)) " +
                "duration=\(String(format: "%.3f", take.duration)) notes=\(notes.count) " +
                "target=\(viewModel.selectedPlaybackTarget)"
        )
    }

    private func logScrubAuditionSummary() {
        let elapsed = scrubAuditionDiagnostics.startedUptime.map {
            max(ProcessInfo.processInfo.systemUptime - $0, 0)
        } ?? 0
        guard scrubAuditionDiagnostics.batches > 0 || scrubAuditionDiagnostics.suppressedFrames > 0 else { return }
        print(
            "MIDI Scribe scrub audition ended: " +
                "take=\(take.id) elapsed=\(String(format: "%.3f", elapsed))s " +
                "batches=\(scrubAuditionDiagnostics.batches) noteOns=\(scrubAuditionDiagnostics.noteOnCount) " +
                "noteOffs=\(scrubAuditionDiagnostics.noteOffCount) " +
                "suppressedFrames=\(scrubAuditionDiagnostics.suppressedFrames) " +
                "maxIntersected=\(scrubAuditionDiagnostics.maxIntersectedNotes) finalOffset=" +
                "\(String(format: "%.3f", currentPlaybackOffset))"
        )
    }

    private func resetScrubAuditionDiagnostics() {
        scrubAuditionDiagnostics = ScrubAuditionDiagnostics()
    }

    func logPlaybackModelDiagnosticsIfNeeded(at offset: TimeInterval) {
        guard isTakePlaying, !isLive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let lastPlaybackModelDiagnosticUptime, now - lastPlaybackModelDiagnosticUptime < 1 {
            return
        }
        lastPlaybackModelDiagnosticUptime = now

        let rendered = renderedModelSnapshot(at: offset)
        let raw = rawEventModelSnapshot(at: offset)
        guard rendered.signature != raw.signature else { return }

        print(
            "MIDI Scribe piano roll model mismatch: " +
                "take=\(take.id) offset=\(String(format: "%.3f", offset)) " +
                "renderedCount=\(rendered.count) rendered=\(rendered.signature) " +
                "rawCount=\(raw.count) raw=\(raw.signature) events=\(take.events.count) notes=\(notes.count)"
        )
    }

    private func renderedModelSnapshot(at offset: TimeInterval) -> PianoRollModelSnapshot {
        let active = notes.filter { note in
            offset >= note.startOffset && offset <= note.startOffset + note.duration
        }
        return PianoRollModelSnapshot(count: active.count, signature: noteSignature(active))
    }

    private func rawEventModelSnapshot(at offset: TimeInterval) -> PianoRollModelSnapshot {
        var activeByChannelAndPitch: [UInt8: Set<UInt8>] = [:]
        for event in take.events.sorted(by: { $0.offsetFromTakeStart < $1.offsetFromTakeStart }) {
            if event.offsetFromTakeStart > offset { break }
            guard event.channel >= 1, event.channel <= 16 else { continue }
            guard let pitch = event.noteNumber else { continue }
            if event.kind == .noteOn && (event.velocity ?? 0) > 0 {
                activeByChannelAndPitch[event.channel, default: []].insert(pitch)
            } else if event.kind == .noteOff || (event.kind == .noteOn && event.velocity == 0) {
                activeByChannelAndPitch[event.channel]?.remove(pitch)
            }
        }

        let pairs = activeByChannelAndPitch.flatMap { channel, pitches in
            pitches.map { pitch in "\(channel):\(pitch)" }
        }.sorted()
        return PianoRollModelSnapshot(count: pairs.count, signature: pairs.prefix(12).joined(separator: ","))
    }

    private func noteSignature(_ notes: [PianoRollNote]) -> String {
        notes.map { "\($0.channel):\($0.pitch)" }.sorted().prefix(12).joined(separator: ",")
    }
}
