//
//  TakePersistenceServiceNaming.swift
//  MIDI Scribe
//

import Foundation
import SwiftData

extension TakePersistenceService {
    /// Duplicate a take and assign the duplicate a display title with an
    /// incremented numeric suffix (`<name> (N)`).
    func duplicateTake(id takeID: UUID) async throws -> UUID? {
        try await runReturning { context -> UUID? in
            guard let original = try Self.fetchTake(id: takeID, in: context) else { return nil }

            let naming = Self.suffixedNameBase(for: original.displayTitle)
            let nextSuffix = try Self.nextNameSuffixes(
                baseTitle: naming.baseTitle,
                startingAt: naming.startingSuffix,
                count: 1,
                in: context
            )[0]

            let duplicate = StoredTake(
                takeID: UUID().uuidString,
                startedAt: original.startedAt,
                endedAt: original.endedAt,
                title: original.title
            )
            duplicate.userTitle = "\(naming.baseTitle) (\(nextSuffix))"
            duplicate.isStarred = original.isStarred
            duplicate.eventCount = original.eventCount
            duplicate.noteOnCount = original.noteOnCount
            duplicate.noteOffCount = original.noteOffCount
            duplicate.channelMask = original.channelMask
            duplicate.lowestNote = original.lowestNote
            duplicate.highestNote = original.highestNote
            context.insert(duplicate)

            for sourceEvent in original.events {
                let duplicateEvent = StoredMIDIEvent(
                    eventID: UUID().uuidString,
                    receivedAt: sourceEvent.receivedAt,
                    offsetFromTakeStart: sourceEvent.offsetFromTakeStart,
                    kindRawValue: sourceEvent.kindRawValue,
                    channel: sourceEvent.channel,
                    status: sourceEvent.status,
                    data1: sourceEvent.data1,
                    data2: sourceEvent.data2,
                    take: duplicate
                )
                duplicate.events.append(duplicateEvent)
            }

            try context.save()
            return UUID(uuidString: duplicate.takeID)
        }
    }

    static func suffixedNameBase(for displayTitle: String) -> (baseTitle: String, startingSuffix: Int) {
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

    static func nextNameSuffixes(
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
