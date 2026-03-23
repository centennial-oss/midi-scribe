//
//  TakeLifecycleController.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Foundation

struct CurrentTakeSnapshot: Sendable {
    let startedAt: Date?
    let lastEventAt: Date?
    let events: [RecordedMIDIEvent]

    nonisolated var isInProgress: Bool {
        startedAt != nil
    }

    nonisolated var summary: RecordedTakeSummary {
        RecordedTakeSummary(events: events, duration: duration)
    }

    nonisolated var duration: TimeInterval {
        guard let startedAt else { return 0 }
        let endedAt = lastEventAt ?? startedAt
        return max(endedAt.timeIntervalSince(startedAt), 0)
    }
}

actor TakeLifecycleController {
    var onSnapshotChanged: (@Sendable (CurrentTakeSnapshot) -> Void)?
    var onTakeCompleted: (@Sendable (RecordedTake) -> Void)?

    private var currentTake = CurrentTakeSnapshot(startedAt: nil, lastEventAt: nil, events: [])
    private var timeoutGeneration = 0

    func ingestInput(at date: Date, timeout: TimeInterval) {
        if currentTake.startedAt == nil {
            currentTake = CurrentTakeSnapshot(startedAt: date, lastEventAt: date, events: [])
        } else {
            currentTake = CurrentTakeSnapshot(startedAt: currentTake.startedAt, lastEventAt: date, events: currentTake.events)
        }

        timeoutGeneration += 1
        scheduleTimeout(generation: timeoutGeneration, timeout: timeout)
        publish()
    }

    func appendEvent(_ event: RecordedMIDIEvent, timeout: TimeInterval) {
        let takeStart = currentTake.startedAt ?? event.receivedAt
        let normalizedEvent = RecordedMIDIEvent(
            id: event.id,
            receivedAt: event.receivedAt,
            offsetFromTakeStart: max(event.receivedAt.timeIntervalSince(takeStart), 0),
            kind: event.kind,
            channel: event.channel,
            status: event.status,
            data1: event.data1,
            data2: event.data2
        )

        if currentTake.startedAt == nil {
            currentTake = CurrentTakeSnapshot(startedAt: event.receivedAt, lastEventAt: event.receivedAt, events: [normalizedEvent])
        } else {
            currentTake = CurrentTakeSnapshot(
                startedAt: currentTake.startedAt,
                lastEventAt: event.receivedAt,
                events: currentTake.events + [normalizedEvent]
            )
        }

        timeoutGeneration += 1
        scheduleTimeout(generation: timeoutGeneration, timeout: timeout)
        publish()
    }

    func endCurrentTake() {
        guard currentTake.isInProgress else { return }
        let completedTake = RecordedTake(
            startedAt: currentTake.startedAt ?? Date(),
            endedAt: currentTake.lastEventAt ?? currentTake.startedAt ?? Date(),
            events: currentTake.events
        )
        currentTake = CurrentTakeSnapshot(startedAt: nil, lastEventAt: nil, events: [])
        timeoutGeneration += 1
        onTakeCompleted?(completedTake)
        publish()
    }

    func setOnSnapshotChanged(_ callback: @escaping @Sendable (CurrentTakeSnapshot) -> Void) {
        onSnapshotChanged = callback
        publish()
    }

    func setOnTakeCompleted(_ callback: @escaping @Sendable (RecordedTake) -> Void) {
        onTakeCompleted = callback
    }

    private func scheduleTimeout(generation: Int, timeout: TimeInterval) {
        Task { [weak self] in
            let duration = UInt64(timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            await self?.handleTimeout(generation: generation)
        }
    }

    private func handleTimeout(generation: Int) {
        guard generation == timeoutGeneration, currentTake.isInProgress else { return }
        endCurrentTake()
    }

    private func publish() {
        onSnapshotChanged?(currentTake)
    }
}
