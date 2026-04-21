//
//  TakeLifecycleController.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Foundation

/// Lightweight snapshot published on every MIDI event.
///
/// Intentionally does NOT carry the full events array: for a long take that
/// array can be tens of thousands of items, and copying it to the main actor
/// on every note is what caused the recording beachball. Instead we publish
/// an incrementally-maintained summary, and hand the full event list over
/// exactly once when the take completes.
struct CurrentTakeSnapshot: Sendable, Equatable {
    let startedAt: Date?
    let lastEventAt: Date?
    let summary: RecordedTakeSummary

    nonisolated var isInProgress: Bool {
        startedAt != nil
    }

    nonisolated var duration: TimeInterval {
        guard let startedAt else { return 0 }
        let endedAt = lastEventAt ?? startedAt
        return max(endedAt.timeIntervalSince(startedAt), 0)
    }

    static let empty = CurrentTakeSnapshot(
        startedAt: nil,
        lastEventAt: nil,
        summary: RecordedTakeSummary.empty
    )
}

actor TakeLifecycleController {
    var onSnapshotChanged: (@Sendable (CurrentTakeSnapshot) -> Void)?
    var onTakeCompleted: (@Sendable (RecordedTake) -> Void)?
    var onTakeDiscarded: (@Sendable () -> Void)?

    private var startedAt: Date?
    private var lastEventAt: Date?
    private var events: [RecordedMIDIEvent] = []
    private var summaryBuilder = RecordedTakeSummaryBuilder()
    private var timeoutGeneration = 0

    func ingestInput(at date: Date, timeout: TimeInterval) {
        if startedAt == nil {
            startedAt = date
            events.reserveCapacity(1024)
        }
        lastEventAt = date

        timeoutGeneration += 1
        scheduleTimeout(generation: timeoutGeneration, timeout: timeout)
        publish()
    }

    func appendEvent(_ event: RecordedMIDIEvent, timeout: TimeInterval) {
        let takeStart: Date
        if let existing = startedAt {
            takeStart = existing
        } else {
            takeStart = event.receivedAt
            startedAt = event.receivedAt
            events.reserveCapacity(1024)
        }

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

        events.append(normalizedEvent)
        summaryBuilder.add(normalizedEvent)
        lastEventAt = event.receivedAt

        timeoutGeneration += 1
        scheduleTimeout(generation: timeoutGeneration, timeout: timeout)
        publish()
    }

    @discardableResult
    func endCurrentTake() -> Bool {
        guard startedAt != nil else { return false }
        if events.isEmpty {
            startedAt = nil
            lastEventAt = nil
            summaryBuilder = RecordedTakeSummaryBuilder()
            timeoutGeneration += 1
            onTakeDiscarded?()
            publish()
            return false
        }

        let completedTake = RecordedTake(
            startedAt: startedAt ?? Date(),
            endedAt: lastEventAt ?? startedAt ?? Date(),
            events: events
        )
        startedAt = nil
        lastEventAt = nil
        events = []
        summaryBuilder = RecordedTakeSummaryBuilder()
        timeoutGeneration += 1
        onTakeCompleted?(completedTake)
        publish()
        return true
    }

    func discardCurrentTake() {
        guard startedAt != nil else { return }
        startedAt = nil
        lastEventAt = nil
        events = []
        summaryBuilder = RecordedTakeSummaryBuilder()
        timeoutGeneration += 1
        onTakeDiscarded?()
        publish()
    }

    func setOnSnapshotChanged(_ callback: @escaping @Sendable (CurrentTakeSnapshot) -> Void) {
        onSnapshotChanged = callback
        publish()
    }

    func setOnTakeCompleted(_ callback: @escaping @Sendable (RecordedTake) -> Void) {
        onTakeCompleted = callback
    }

    func setOnTakeDiscarded(_ callback: @escaping @Sendable () -> Void) {
        onTakeDiscarded = callback
    }

    private func scheduleTimeout(generation: Int, timeout: TimeInterval) {
        Task { [weak self] in
            let duration = UInt64(timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)
            await self?.handleTimeout(generation: generation)
        }
    }

    private func handleTimeout(generation: Int) {
        guard generation == timeoutGeneration, startedAt != nil else { return }
        endCurrentTake()
    }

    private func publish() {
        let snapshot = CurrentTakeSnapshot(
            startedAt: startedAt,
            lastEventAt: lastEventAt,
            summary: summaryBuilder.build(duration: currentDuration)
        )
        onSnapshotChanged?(snapshot)
    }

    private var currentDuration: TimeInterval {
        guard let startedAt else { return 0 }
        let endedAt = lastEventAt ?? startedAt
        return max(endedAt.timeIntervalSince(startedAt), 0)
    }
}
