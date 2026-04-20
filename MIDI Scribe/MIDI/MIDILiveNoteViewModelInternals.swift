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
        let isTakeInProgress = currentTakeSnapshot.isInProgress || hasStartedRecordableTake
        guard isTakeInProgress || settings.shouldStartTake(event) else { return }

        hasStartedRecordableTake = true
        selectedSidebarItem = .currentTake
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
                await takeLifecycle.endCurrentTake()
            }
        }
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
        let elapsedSeconds = max(0, Int(duration))
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return "\(minutes)m \(seconds)s"
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
        }

        completedTakeSelectionMode = .showCompleted
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
