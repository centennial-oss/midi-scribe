//
//  TakePersistenceService.swift
//  MIDI Scribe
//
//  Single place that owns all mutating operations against the SwiftData
//  store (star, rename, split, merge, delete, erase). Every operation runs
//  on a background `ModelContext` so the UI stays responsive even when a
//  take has tens of thousands of events.
//
//  Views should not talk to `modelContext` directly for mutations; they go
//  through this service. Reads still use `@Query` for live updates.
//

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

actor TakePersistenceService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Star / unstar

    func setStarred(_ isStarred: Bool, takeID: UUID) async throws {
        try await run { context in
            guard let take = try Self.fetchTake(id: takeID, in: context) else { return }
            take.isStarred = isStarred
            try context.save()
        }
    }

    // MARK: - Rename

    /// Pass nil or empty to reset to the default date/time title.
    func renameTake(id takeID: UUID, to newName: String?) async throws {
        try await run { context in
            guard let take = try Self.fetchTake(id: takeID, in: context) else { return }
            let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                take.userTitle = trimmed
            } else {
                take.userTitle = nil
            }
            try context.save()
        }
    }

    // MARK: - Delete

    func deleteTake(id takeID: UUID) async throws {
        try await run { context in
            // Store-level predicate delete avoids faulting a potentially large
            // event relationship graph into memory before removal.
            let idString = takeID.uuidString
            try context.delete(
                model: StoredTake.self,
                where: #Predicate<StoredTake> { $0.takeID == idString }
            )
            try context.save()
        }
    }

    // MARK: - Samples

    func importSampleTakes(_ samples: [SampleMIDIFile]) async throws -> [UUID] {
        try await runReturning { context -> [UUID] in
            let existingTitles = try Set(
                context.fetch(FetchDescriptor<StoredTake>())
                    .map(\.displayTitle)
            )

            var insertedIDs: [UUID] = []
            for sample in samples where !existingTitles.contains(sample.title) {
                let asset = NSDataAsset(name: "SampleTakes/\(sample.assetName)") ?? NSDataAsset(name: sample.assetName)
                guard let asset else {
                    continue
                }

                let take = try StandardMIDIFileReader.take(from: asset.data, title: sample.title)
                let stored = StoredTake(recordedTake: take)
                stored.title = sample.title
                context.insert(stored)
                insertedIDs.append(take.id)
            }

            if !insertedIDs.isEmpty {
                try context.save()
            }
            return insertedIDs
        }
    }

    // MARK: - Split

    /// Split a take in two at the given offset (in seconds from the take's
    /// start). Events at or after `splitOffset` go to the second half. Both
    /// halves have their silence trimmed (events are rebased so offset 0 is
    /// the first event; endedAt is the last event).
    ///
    /// Both new takes are titled `"<base> (N)"` where N is the next available
    /// suffix for that base title in the store.
    func splitTake(id takeID: UUID, at splitOffset: TimeInterval) async throws -> (firstID: UUID, secondID: UUID)? {
        try await runReturning { context -> (UUID, UUID)? in
            guard let original = try Self.fetchTake(id: takeID, in: context) else { return nil }

            // Partition existing event rows without copying them. Keep the
            // "before" rows attached to the (renamed) original take, move the
            // "after" rows to a new take. This avoids cascading a delete and
            // re-inserting thousands of rows, which is what made split slow.
            let allEvents = original.events
            guard !allEvents.isEmpty else { return nil }
            guard let partitioned = Self.partitionEventsForSplit(allEvents, at: splitOffset) else { return nil }
            var beforeEvents = partitioned.before
            var afterEvents = partitioned.after

            // Sort only the minimal slices we need for first/last offsets.
            beforeEvents.sort { $0.offsetFromTakeStart < $1.offsetFromTakeStart }
            afterEvents.sort { $0.offsetFromTakeStart < $1.offsetFromTakeStart }

            let splitNaming = Self.splitNamingBase(for: original.displayTitle)
            let baseTitle = splitNaming.baseTitle
            let nextSuffixes = try Self.nextSplitSuffixes(
                baseTitle: baseTitle,
                startingAt: splitNaming.startingSuffix,
                count: 2,
                in: context
            )

            // Cache the pre-mutation start date so we can compute absolute
            // start/end times for both halves in original-take coordinates.
            let originalStartDate = original.startedAt

            // --- First half: reuse the original take in place ---
            let beforeFirstOffset = beforeEvents.first!.offsetFromTakeStart
            let beforeLastOffset = beforeEvents.last!.offsetFromTakeStart
            if beforeFirstOffset != 0 {
                for event in beforeEvents {
                    event.offsetFromTakeStart -= beforeFirstOffset
                }
            }
            original.title = baseTitle
            original.startedAt = originalStartDate.addingTimeInterval(beforeFirstOffset)
            original.endedAt = originalStartDate.addingTimeInterval(beforeLastOffset)
            original.userTitle = "\(baseTitle) (\(nextSuffixes[0]))"
            Self.recomputeSummary(on: original, events: beforeEvents)

            // --- Second half: new StoredTake that adopts the "after" events ---
            let afterFirstOffset = afterEvents.first!.offsetFromTakeStart
            let afterLastOffset = afterEvents.last!.offsetFromTakeStart

            let secondTake = StoredTake(
                takeID: UUID().uuidString,
                startedAt: originalStartDate.addingTimeInterval(afterFirstOffset),
                endedAt: originalStartDate.addingTimeInterval(afterLastOffset),
                title: baseTitle
            )
            secondTake.userTitle = "\(baseTitle) (\(nextSuffixes[1]))"
            context.insert(secondTake)

            for event in afterEvents {
                event.offsetFromTakeStart -= afterFirstOffset
                event.take = secondTake
            }
            Self.recomputeSummary(on: secondTake, events: afterEvents)

            try context.save()

            let firstID = UUID(uuidString: original.takeID) ?? UUID()
            let secondID = UUID(uuidString: secondTake.takeID) ?? UUID()
            return (firstID, secondID)
        }
    }

    /// Partition events into before/after slices at `splitOffset`, or nil if a half would be empty.
    private static func partitionEventsForSplit(
        _ allEvents: [StoredMIDIEvent],
        at splitOffset: TimeInterval
    ) -> (before: [StoredMIDIEvent], after: [StoredMIDIEvent])? {
        var beforeEvents: [StoredMIDIEvent] = []
        var afterEvents: [StoredMIDIEvent] = []
        beforeEvents.reserveCapacity(allEvents.count)
        afterEvents.reserveCapacity(allEvents.count)
        for event in allEvents {
            if event.offsetFromTakeStart < splitOffset {
                beforeEvents.append(event)
            } else {
                afterEvents.append(event)
            }
        }
        guard !beforeEvents.isEmpty, !afterEvents.isEmpty else { return nil }
        return (beforeEvents, afterEvents)
    }

    /// Populate cached summary fields without constructing a RecordedTake.
    private static func recomputeSummary(on take: StoredTake, events: [StoredMIDIEvent]) {
        var noteOn = 0
        var noteOff = 0
        var channelMask = 0
        var lowest: Int?
        var highest: Int?
        let noteOnRaw = MIDIChannelEventKind.noteOn.rawValue
        let noteOffRaw = MIDIChannelEventKind.noteOff.rawValue
        for event in events {
            if event.kindRawValue == noteOnRaw {
                noteOn += 1
                if let lowNote = lowest {
                    lowest = min(lowNote, event.data1)
                } else {
                    lowest = event.data1
                }
                if let highNote = highest {
                    highest = max(highNote, event.data1)
                } else {
                    highest = event.data1
                }
            } else if event.kindRawValue == noteOffRaw {
                noteOff += 1
            }
            let channelIndex = event.channel
            if channelIndex >= 1 && channelIndex <= 16 {
                channelMask |= (1 << (channelIndex - 1))
            }
        }
        take.eventCount = events.count
        take.noteOnCount = noteOn
        take.noteOffCount = noteOff
        take.channelMask = channelMask
        take.lowestNote = lowest
        take.highestNote = highest
    }

    // MARK: - Merge

    /// Merge the given takes (in order of their `startedAt`) into a single
    /// new take. Between consecutive takes we insert `silenceBetweenMs` of
    /// silence (events' offsets are shifted accordingly). Originals are
    /// deleted.
    func mergeTakes(ids: [UUID], silenceBetweenMs: Int) async throws -> UUID? {
        try await runReturning { context -> UUID? in
            let takes = try ids.compactMap { try Self.fetchTake(id: $0, in: context) }
            guard takes.count >= 2 else { return nil }
            let sortedTakes = takes.sorted { $0.startedAt < $1.startedAt }
            let gap = max(TimeInterval(silenceBetweenMs) / 1000.0, 0)

            // Build merged event list with rebased offsets.
            var mergedEvents: [RecordedMIDIEvent] = []
            var cursor: TimeInterval = 0
            for (index, take) in sortedTakes.enumerated() {
                let takeEvents = take.events.sorted { $0.offsetFromTakeStart < $1.offsetFromTakeStart }
                let takeDuration = takeEvents.last?.offsetFromTakeStart ?? 0

                for event in takeEvents {
                    let rebased = RecordedMIDIEvent(
                        id: UUID(),
                        receivedAt: event.receivedAt,
                        offsetFromTakeStart: cursor + event.offsetFromTakeStart,
                        kind: MIDIChannelEventKind(rawValue: event.kindRawValue) ?? .controlChange,
                        channel: UInt8(event.channel),
                        status: UInt8(event.status),
                        data1: UInt8(event.data1),
                        data2: event.data2.map(UInt8.init)
                    )
                    mergedEvents.append(rebased)
                }

                cursor += takeDuration
                if index < sortedTakes.count - 1 {
                    cursor += gap
                }
            }

            let firstStart = sortedTakes.first!.startedAt
            let endedAt = firstStart.addingTimeInterval(cursor)
            let mergedRecordedTake = RecordedTake(
                startedAt: firstStart,
                endedAt: endedAt,
                events: mergedEvents
            )
            let mergedStored = StoredTake(recordedTake: mergedRecordedTake)
            context.insert(mergedStored)

            for take in sortedTakes {
                context.delete(take)
            }
            try context.save()

            return mergedRecordedTake.id
        }
    }

    // MARK: - Internals

    private static func fetchTake(id takeID: UUID, in context: ModelContext) throws -> StoredTake? {
        let idString = takeID.uuidString
        let descriptor = FetchDescriptor<StoredTake>(
            predicate: #Predicate<StoredTake> { $0.takeID == idString }
        )
        return try context.fetch(descriptor).first
    }

    // MARK: - Run helpers

    private func run(_ block: @Sendable @escaping (ModelContext) throws -> Void) async throws {
        let container = self.container
        try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            try block(context)
        }.value
    }

    private func runReturning<T: Sendable>(_ block: @Sendable @escaping (ModelContext) throws -> T) async throws -> T {
        let container = self.container
        return try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            return try block(context)
        }.value
    }
}

extension TakePersistenceService {
    static func splitNamingBase(for displayTitle: String) -> (baseTitle: String, startingSuffix: Int) {
        let trimmedTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #/^(.*) \((\d+)\)$/#
        if let match = try? pattern.wholeMatch(in: trimmedTitle),
           let suffix = Int(match.output.2) {
            let base = String(match.output.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !base.isEmpty {
                return (base, suffix)
            }
        }
        return (trimmedTitle, 1)
    }

    static func nextSplitSuffixes(
        baseTitle: String,
        startingAt startingSuffix: Int,
        count: Int,
        in context: ModelContext
    ) throws -> [Int] {
        let all = try context.fetch(FetchDescriptor<StoredTake>())
        let pattern = #/^\Q\#(baseTitle)\E \((\d+)\)$/#
        var usedSuffixes = Set<Int>()
        for take in all {
            let candidates = [take.title, take.userTitle ?? ""]
            for candidate in candidates {
                if let match = try? pattern.wholeMatch(in: candidate),
                   let suffixNum = Int(match.output.1) {
                    usedSuffixes.insert(suffixNum)
                }
            }
        }
        var result: [Int] = []
        var candidateSuffix = max(1, startingSuffix)
        while result.count < count {
            if !usedSuffixes.contains(candidateSuffix) {
                result.append(candidateSuffix)
                usedSuffixes.insert(candidateSuffix)
            }
            candidateSuffix += 1
        }
        return result
    }

    func recordedTake(id takeID: UUID) async throws -> RecordedTake? {
        try await runReturning { context in
            try Self.fetchTake(id: takeID, in: context)?.recordedTake
        }
    }
}
