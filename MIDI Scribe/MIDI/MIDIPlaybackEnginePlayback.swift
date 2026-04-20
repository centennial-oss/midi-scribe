import Foundation

extension MIDIPlaybackEngine {
    func playOrResume(take: RecordedTake, target: PlaybackOutputTarget) {
        preparePlaybackSession(for: take, target: target)

        let events = take.events
        let startIndex = playbackResumeIndex
        let startOffset = playbackResumeOffset
        let playbackEpoch = Date().addingTimeInterval(-startOffset)

        for event in pedalReentryEvents(in: take, at: startOffset) {
            play(event: event, target: target)
        }

        playbackTask = Task { [weak self] in
            await self?.runPlaybackLoop(
                events: events,
                startIndex: startIndex,
                playbackEpoch: playbackEpoch,
                target: target
            )
        }
    }

    private func preparePlaybackSession(for take: RecordedTake, target: PlaybackOutputTarget) {
        if playbackTask != nil {
            pause()
        }
        if target == .osSpeakers {
            refreshSpeakerOutputRoute()
        }
        if currentTakeID != take.id || currentTarget != target {
            let preservedResumeOffset = playbackResumeOffset
            resetPlaybackPosition()
            if preservedResumeOffset > 0 {
                playbackResumeOffset = preservedResumeOffset
                playbackResumeIndex = firstEventIndex(in: take, atOrAfter: preservedResumeOffset)
            }
        }
        activatePlaybackState(take: take, target: target)
    }

    private func runPlaybackLoop(
        events: [RecordedMIDIEvent],
        startIndex: Int,
        playbackEpoch: Date,
        target: PlaybackOutputTarget
    ) async {
        var immediateBurstCount = 0
        for index in startIndex ..< events.count {
            let event = events[index]
            immediateBurstCount = await waitForPlaybackSlot(
                eventOffset: event.offsetFromTakeStart,
                playbackEpoch: playbackEpoch,
                immediateBurstCount: immediateBurstCount
            )
            if Task.isCancelled { return }
            await MainActor.run {
                self.playbackResumeIndex = index + 1
                self.playbackResumeOffset = event.offsetFromTakeStart
                self.play(event: event, target: target)
            }
        }
        await MainActor.run {
            self.finishPlayback()
        }
    }

    private func waitForPlaybackSlot(
        eventOffset: TimeInterval,
        playbackEpoch: Date,
        immediateBurstCount: Int
    ) async -> Int {
        let targetDate = playbackEpoch.addingTimeInterval(eventOffset)
        let wait = targetDate.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            return 0
        }
        let nextBurstCount = immediateBurstCount + 1
        guard nextBurstCount >= 128 else { return nextBurstCount }
        try? await Task.sleep(nanoseconds: 1_000_000)
        return 0
    }

    func snapResumePositionToActiveNoteStart() {
        guard let playbackTake else { return }
        guard let snappedOffset = activeNoteStartOffset(in: playbackTake, at: playbackResumeOffset) else { return }
        playbackResumeOffset = snappedOffset
        playbackResumeIndex = firstEventIndex(in: playbackTake, atOrAfter: snappedOffset)
    }

    private func activeNoteStartOffset(in take: RecordedTake, at offset: TimeInterval) -> TimeInterval? {
        var activeByChannelAndPitch: [UInt16: TimeInterval] = [:]
        for event in take.events.sorted(by: { $0.offsetFromTakeStart < $1.offsetFromTakeStart }) {
            if event.offsetFromTakeStart > offset { break }
            guard event.channel >= 1, event.channel <= 16 else { continue }
            guard let pitch = event.noteNumber else { continue }
            let key = (UInt16(event.channel) << 8) | UInt16(pitch)

            if event.kind == .noteOn, (event.velocity ?? 0) > 0 {
                activeByChannelAndPitch[key] = event.offsetFromTakeStart
            } else if event.kind == .noteOff || (event.kind == .noteOn && event.velocity == 0) {
                activeByChannelAndPitch.removeValue(forKey: key)
            }
        }
        return activeByChannelAndPitch.values.min()
    }
}
