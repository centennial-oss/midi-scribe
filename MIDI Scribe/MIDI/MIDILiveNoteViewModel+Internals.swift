//
//  MIDILiveNoteViewModel+Internals.swift
//  MIDI Scribe
//

import Combine
import Foundation

extension MIDILiveNoteViewModel {
    func handleEligibleInput(_ receivedAt: Date) {
        guard settings.isScribingEnabled else { return }
        Task {
            await takeLifecycle.ingestInput(at: receivedAt, timeout: settings.newTakePauseSeconds)
        }
    }

    func handleRecordedEvent(_ event: RecordedMIDIEvent) {
        guard settings.isScribingEnabled else { return }
        playbackEngine.playLiveEventToSpeakers(event)
        Task {
            await takeLifecycle.appendEvent(event, timeout: settings.newTakePauseSeconds)
        }
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
