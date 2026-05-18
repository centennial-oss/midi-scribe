import Foundation

extension MIDIPlaybackEngine {
    func playOrResume(take: RecordedTake, target: PlaybackOutputTarget) {
        preparePlaybackSession(for: take, target: target)

        let events = take.events
        let startIndex = playbackResumeIndex
        let startOffset = playbackResumeOffset
        let startOffsetNanoseconds = Self.nanoseconds(for: startOffset)
        let nowNanoseconds = DispatchTime.now().uptimeNanoseconds
        let playbackStartUptimeNanoseconds = nowNanoseconds > startOffsetNanoseconds
            ? nowNanoseconds - startOffsetNanoseconds
            : 0

        for event in pedalReentryEvents(in: take, at: startOffset) {
            play(event: event, target: target)
        }

        let sessionID = playbackSessionID
        playbackTask = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.runPlaybackLoop(
                events: events,
                startIndex: startIndex,
                playbackStartUptimeNanoseconds: playbackStartUptimeNanoseconds,
                playbackSessionID: sessionID,
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

    nonisolated private func runPlaybackLoop(
        events: [RecordedMIDIEvent],
        startIndex: Int,
        playbackStartUptimeNanoseconds: UInt64,
        playbackSessionID: UUID?,
        target: PlaybackOutputTarget
    ) async {
        var index = startIndex
        while index < events.count {
            let batchStart = index
            let batchUptimeNanoseconds = playbackStartUptimeNanoseconds
                + Self.nanoseconds(for: events[batchStart].offsetFromTakeStart)
            let now = DispatchTime.now().uptimeNanoseconds
            if batchUptimeNanoseconds > now {
                try? await Task.sleep(nanoseconds: batchUptimeNanoseconds - now)
            }
            if Task.isCancelled { return }

            while index < events.count,
                  playbackStartUptimeNanoseconds + Self.nanoseconds(for: events[index].offsetFromTakeStart)
                      == batchUptimeNanoseconds {
                play(event: events[index], target: target)
                index += 1
            }

            let resumeIndex = index
            let resumeOffset = events[resumeIndex - 1].offsetFromTakeStart
            Task { @MainActor [weak self] in
                guard let self, self.playbackSessionID == playbackSessionID, self.isPlaying else { return }
                self.playbackResumeIndex = resumeIndex
                self.playbackResumeOffset = resumeOffset
            }
        }
        await MainActor.run { self.finishPlayback() }
    }

    nonisolated private static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64(max(0, interval) * 1_000_000_000)
    }

    func snapResumePositionToActiveNoteStart() {
        guard let playbackTake else { return }
        guard let snappedOffset = activeNoteStartOffset(in: playbackTake, at: playbackResumeOffset)
        else { return }
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
