//
//  MIDILiveNoteViewModel+Internals.swift
//  MIDI Scribe
//

import Combine
import Foundation

extension MIDILiveNoteViewModel {
    func handleEligibleInput(_ receivedAt: Date) {
        guard settings.isScribingEnabled else { return }
        guard currentTakeSnapshot.isInProgress else { return }
        selectedSidebarItem = .currentTake
        Task {
            await takeLifecycle.ingestInput(at: receivedAt, timeout: settings.newTakePauseSeconds)
        }
    }

    func handleRecordedEvent(_ event: RecordedMIDIEvent) {
        guard settings.isScribingEnabled else { return }
        guard !event.isPresetSelectionEvent else { return }
        let isSuppressedTakeStartControlChange = shouldSuppressTakeStartControlChange(for: event)
        let isTakeInProgress = currentTakeSnapshot.isInProgress || hasStartedRecordableTake
        let shouldStartTake = settings.shouldStartTake(event) && !isSuppressedTakeStartControlChange
        let isTakeStartControlChange = event.kind == .controlChange && shouldStartTake
        guard isTakeInProgress || shouldStartTake else { return }

        if shouldStartTake && !isTakeInProgress {
            playbackEngine.pause()
        }

        hasStartedRecordableTake = true
        selectedSidebarItem = .currentTake

        if isTakeStartControlChange {
            Task {
                await takeLifecycle.ingestInput(at: event.receivedAt, timeout: settings.newTakePauseSeconds)
                if isTakeInProgress, settings.shouldEndTake(event) {
                    suppressComplementaryTakeStartControlChange(afterEndingWith: event)
                    await takeLifecycle.endCurrentTake()
                }
            }
            return
        }

        // Play first, synchronously, so speaker echo isn't delayed by
        // subsequent SwiftData/UI work on this tick.
        playbackEngine.playLiveEventToSpeakers(event)
        // Defer the live piano roll update to the next runloop tick. The
        // @Published mutation triggers a SwiftUI diff of the live piano
        // roll that, when executed inline, adds audible latency to the
        // echoed note.
        Task { @MainActor [weak self] in
            self?.appendToLiveTake(event)
        }
        Task {
            await takeLifecycle.appendEvent(event, timeout: settings.newTakePauseSeconds)
            if isTakeInProgress, settings.shouldEndTake(event) {
                suppressComplementaryTakeStartControlChange(afterEndingWith: event)
                await takeLifecycle.endCurrentTake()
            }
        }
    }

    private func shouldSuppressTakeStartControlChange(for event: RecordedMIDIEvent) -> Bool {
        guard event.kind == .controlChange,
              settings.shouldStartTake(event),
              suppressedTakeStartControlChange == event.data1 else {
            return false
        }
        suppressedTakeStartControlChange = nil
        return true
    }

    private func suppressComplementaryTakeStartControlChange(afterEndingWith event: RecordedMIDIEvent) {
        guard event.kind == .controlChange,
              settings.shouldEndTake(event),
              settings.takeStartControlChanges.contains(event.data1) else {
            return
        }
        suppressedTakeStartControlChange = event.data1
    }

    /// Mirror the lifecycle actor's event normalization on the main actor so
    /// the live piano roll has up-to-date, origin-relative events without a
    /// cross-actor hop on every note.
    private func appendToLiveTake(_ event: RecordedMIDIEvent) {
        let takeStart: Date
        if let existing = liveTakeStartedAt {
            takeStart = existing
        } else {
            takeStart = event.receivedAt
            liveTakeStartedAt = event.receivedAt
            liveTakeID = UUID()
            liveTakeEvents.removeAll(keepingCapacity: true)
        }

        let normalized = RecordedMIDIEvent(
            id: event.id,
            receivedAt: event.receivedAt,
            offsetFromTakeStart: max(event.receivedAt.timeIntervalSince(takeStart), 0),
            kind: event.kind,
            channel: event.channel,
            status: event.status,
            data1: event.data1,
            data2: event.data2
        )
        liveTakeEvents.append(normalized)
    }

    func handleScribingEnabledChanged(isEnabled: Bool) {
        if !isEnabled {
            currentNoteText = emptyLiveValuePlaceholder
            currentChannelText = emptyLiveValuePlaceholder

            Task {
                await takeLifecycle.endCurrentTake()
            }
        } else {
            startMonitorWithRetry(resetBackoff: true)
        }
    }

    func applyCurrentTakeSnapshot(_ snapshot: CurrentTakeSnapshot) {
        currentTakeSnapshot = snapshot

        if snapshot.isInProgress {
            durationTicker?.cancel()
            durationTicker = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        } else {
            durationTicker?.cancel()
            durationTicker = nil
            hasStartedRecordableTake = false
            if liveTakeStartedAt != nil {
                liveTakeStartedAt = nil
                liveTakeEvents.removeAll(keepingCapacity: false)
            }
        }
    }

    func formatDuration(_ duration: TimeInterval) -> String {
        DurationFormatting.compactWholeSeconds(duration)
    }

    func formatNoteRange(lowest: UInt8?, highest: UInt8?) -> String {
        switch (lowest, highest) {
        case let (lowest?, highest?):
            let lowNote = MIDINote(noteNumber: lowest, velocity: 0, channel: 1).displayName
            let highNote = MIDINote(noteNumber: highest, velocity: 0, channel: 1).displayName
            return lowest == highest ? lowNote : "\(lowNote) - \(highNote)"
        default:
            return "None"
        }
    }

    func handleCompletedTakeSelection(for take: RecordedTakeListItem) {
        switch completedTakeSelectionMode {
        case .showCompleted:
            selectedSidebarItem = .recentTake(take.id)
        case .stayOnCurrent:
            selectedSidebarItem = .currentTake
        case .preserveSelection(let selection):
            selectedSidebarItem = selection
        }

        completedTakeSelectionMode = .showCompleted
        performDeferredPlaybackRequestIfNeeded()
    }

    func performDeferredPlaybackRequestIfNeeded() {
        if let request = playbackRequestAfterCurrentTakeEnds {
            playbackRequestAfterCurrentTakeEnds = nil
            loadFullTakeAndPlay(
                takeID: request.takeID,
                restart: request.restart,
                target: request.target,
                saveCurrentTakeFirst: false
            )
        }
    }

    func handleDiscardedTake() {
        completedTakeSelectionMode = .showCompleted
        performDeferredPlaybackRequestIfNeeded()
    }

    func startMonitorWithRetry(resetBackoff: Bool) {
        if resetBackoff {
            monitorRetryTask?.cancel()
            monitorRetryTask = nil
        }

        guard monitorRetryTask == nil else { return }

        monitorRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempt = 0

            while !Task.isCancelled {
                do {
                    try monitor.start()
                    errorText = nil
                    monitorRetryTask = nil
                    return
                } catch {
                    errorText = "MIDI input unavailable. Retrying... \(error.localizedDescription)"
                }

                let delays = MIDILiveNoteViewModel.monitorStartRetryDelays
                let delay = delays[min(attempt, delays.count - 1)]
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            monitorRetryTask = nil
        }
    }
}
