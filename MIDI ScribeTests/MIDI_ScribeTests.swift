//
//  MIDI_ScribeTests.swift
//  MIDI ScribeTests
//
//  Created by James Ranson on 3/21/26.
//

import Foundation
import SwiftData
import Testing
@testable import MIDI_Scribe

struct MIDIScribeTests {

    @MainActor
    @Test func controlChangeTakeStartFiresOnReleaseAndTakeEndFiresOnPress() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.startTakeWithNoteEvents = false
        settings.takeStartControlChanges = [66]
        settings.takeEndControlChanges = [66]

        let pressed = controlChange(controller: 66, value: 127)
        let lightPress = controlChange(controller: 66, value: 12)
        let released = controlChange(controller: 66, value: 0)

        #expect(!settings.shouldStartTake(pressed))
        #expect(!settings.shouldStartTake(lightPress))
        #expect(settings.shouldEndTake(pressed))
        #expect(settings.shouldStartTake(released))
        #expect(!settings.shouldEndTake(released))
    }

    @MainActor
    @Test func takeStartControlChangesAreNotRecorded() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.echoScribedToSpeakers = false
        settings.startTakeWithNoteEvents = false
        settings.takeStartControlChanges = [66]

        let viewModel = MIDILiveNoteViewModel(settings: settings)
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(controlChange(controller: 66, value: 127))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(controlChange(controller: 66, value: 0))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(noteOn(noteNumber: 60, velocity: 80))
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.takeLifecycle.endCurrentTake()
        try await Task.sleep(nanoseconds: 100_000_000)

        let take = try #require(viewModel.lastCompletedTake.flatMap { viewModel.materializedTakes[$0.id] })
        #expect(take.events.map(\.kind) == [.noteOn])
        #expect(take.events.map(\.data1) == [60])
    }

    @MainActor
    @Test func endingTakeWithSharedControlChangeDoesNotRestartOnRelease() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.echoScribedToSpeakers = false
        settings.startTakeWithNoteEvents = false
        settings.takeStartControlChanges = [66]
        settings.takeEndControlChanges = [66]

        let viewModel = MIDILiveNoteViewModel(settings: settings)
        try await Task.sleep(nanoseconds: 10_000_000)

        viewModel.handleRecordedEvent(controlChange(controller: 66, value: 0))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(noteOn(noteNumber: 60, velocity: 80))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(controlChange(controller: 66, value: 127))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(controlChange(controller: 66, value: 0))
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(!viewModel.isTakeInProgress)
        #expect(viewModel.lastCompletedTake != nil)
        #expect(viewModel.currentTakeSnapshot.summary.eventCount == 0)
    }

    @MainActor
    @Test func presetSelectionEventsAreNotRecorded() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.echoScribedToSpeakers = false

        let viewModel = MIDILiveNoteViewModel(settings: settings)
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(noteOn(noteNumber: 60, velocity: 80))
        try await Task.sleep(nanoseconds: 10_000_000)
        viewModel.handleRecordedEvent(controlChange(controller: 0, value: 1))
        viewModel.handleRecordedEvent(controlChange(controller: 32, value: 2))
        viewModel.handleRecordedEvent(programChange(program: 0))
        try await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.takeLifecycle.endCurrentTake()
        try await Task.sleep(nanoseconds: 100_000_000)

        let take = try #require(viewModel.lastCompletedTake.flatMap { viewModel.materializedTakes[$0.id] })
        #expect(take.events.map(\.kind) == [.noteOn])
        #expect(take.events.map(\.data1) == [60])
    }

    @MainActor
    @Test func welcomeSheetShownFlagStartsUnsetAndPersistsWhenMarked() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(!settings.hasWelcomeSheetShownValue)

        settings.markWelcomeSheetShown()

        #expect(settings.hasWelcomeSheetShownValue)
    }

    @MainActor
    @Test func selectedPlaybackTargetDefaultsToSpeakersAndPersists() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.selectedPlaybackTarget == .osSpeakers)

        settings.selectedPlaybackTarget = .midiChannel(7)

        let reloadedSettings = AppSettings(userDefaults: defaults)
        #expect(reloadedSettings.selectedPlaybackTarget == .midiChannel(7))
    }

    @MainActor
    @Test func resetAllPreferencesClearsWelcomeSheetShownFlag() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.markWelcomeSheetShown()
        #expect(settings.hasWelcomeSheetShownValue)

        settings.resetAllPreferences()

        #expect(!settings.hasWelcomeSheetShownValue)
    }

    @MainActor
    @Test func welcomeSheetFlagCanBeMarkedSeenWithoutPresentingSheet() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(!settings.hasWelcomeSheetShownValue)

        settings.markWelcomeSheetShown()

        #expect(settings.hasWelcomeSheetShownValue)
    }

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

    private func controlChange(controller: UInt8, value: UInt8) -> RecordedMIDIEvent {
        RecordedMIDIEvent(
            receivedAt: Date(),
            offsetFromTakeStart: 0,
            kind: .controlChange,
            channel: 1,
            status: 0xB0,
            data1: controller,
            data2: value
        )
    }

    private func noteOn(noteNumber: UInt8, velocity: UInt8) -> RecordedMIDIEvent {
        RecordedMIDIEvent(
            receivedAt: Date(),
            offsetFromTakeStart: 0,
            kind: .noteOn,
            channel: 1,
            status: 0x90,
            data1: noteNumber,
            data2: velocity
        )
    }

    private func programChange(program: UInt8) -> RecordedMIDIEvent {
        RecordedMIDIEvent(
            receivedAt: Date(),
            offsetFromTakeStart: 0,
            kind: .programChange,
            channel: 1,
            status: 0xC0,
            data1: program
        )
    }
}
