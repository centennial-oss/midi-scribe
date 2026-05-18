//
//  MIDI_ScribeSplitTests.swift
//  MIDI ScribeTests
//

import Foundation
import SwiftData
import Testing
@testable import MIDI_Scribe

struct MIDIScribeSplitTests {

    @MainActor
    @Test func splitUsesRenamedTakeTitleAsSplitBase() async throws {
        let container = try makeInMemoryModelContainer()
        let service = TakePersistenceService(container: container)
        let context = ModelContext(container)
        let takeID = try makeRenamedSplitFixture(in: context)

        let splitIDs = try #require(await service.splitTake(id: takeID, at: 1.0))

        let descriptor = FetchDescriptor<StoredTake>()
        let storedTakes = try context.fetch(descriptor)
        let firstHalf = try #require(storedTakes.first(where: { $0.takeID == splitIDs.firstID.uuidString }))
        let secondHalf = try #require(storedTakes.first(where: { $0.takeID == splitIDs.secondID.uuidString }))

        #expect(firstHalf.displayTitle == "Renamed Take (1)")
        #expect(secondHalf.displayTitle == "Renamed Take (2)")
        #expect(firstHalf.title == "Renamed Take")
        #expect(secondHalf.title == "Renamed Take")
    }

    @MainActor
    @Test func splitPreservesExistingNumericSuffixAsStartingPoint() async throws {
        let container = try makeInMemoryModelContainer()
        let service = TakePersistenceService(container: container)
        let context = ModelContext(container)
        let takeID = try makeRenamedSplitFixture(in: context, displayTitle: "My Asset (2)")

        let splitIDs = try #require(await service.splitTake(id: takeID, at: 1.0))

        let storedTakes = try context.fetch(FetchDescriptor<StoredTake>())
        let firstHalf = try #require(storedTakes.first(where: { $0.takeID == splitIDs.firstID.uuidString }))
        let secondHalf = try #require(storedTakes.first(where: { $0.takeID == splitIDs.secondID.uuidString }))

        #expect(firstHalf.displayTitle == "My Asset (2)")
        #expect(secondHalf.displayTitle == "My Asset (3)")
        #expect(firstHalf.title == "My Asset")
        #expect(secondHalf.title == "My Asset")
    }

    @MainActor
    private func makeInMemoryModelContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: StoredTake.self,
            StoredMIDIEvent.self,
            configurations: config
        )
    }

    private func makeRenamedSplitFixture(
        in context: ModelContext,
        displayTitle: String = "Renamed Take"
    ) throws -> UUID {
        let takeID = UUID()
        let take = StoredTake(
            takeID: takeID.uuidString,
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 2),
            title: "Original Name"
        )
        take.userTitle = displayTitle

        take.events = [
            StoredMIDIEvent(
                eventID: UUID().uuidString,
                receivedAt: Date(timeIntervalSince1970: 0),
                offsetFromTakeStart: 0.25,
                kindRawValue: MIDIChannelEventKind.noteOn.rawValue,
                channel: 1,
                status: 0x90,
                data1: 60,
                data2: 100,
                take: take
            ),
            StoredMIDIEvent(
                eventID: UUID().uuidString,
                receivedAt: Date(timeIntervalSince1970: 1),
                offsetFromTakeStart: 1.25,
                kindRawValue: MIDIChannelEventKind.noteOff.rawValue,
                channel: 1,
                status: 0x80,
                data1: 60,
                data2: 0,
                take: take
            )
        ]
        take.eventCount = 2
        take.noteOnCount = 1
        take.noteOffCount = 1
        take.channelMask = 1
        take.lowestNote = 60
        take.highestNote = 60
        context.insert(take)
        try context.save()
        return takeID
    }
}
