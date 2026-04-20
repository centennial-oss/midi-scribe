//
//  MIDI_ScribeTests.swift
//  MIDI ScribeTests
//
//  Created by James Ranson on 3/21/26.
//

import Foundation
import Testing
@testable import MIDI_Scribe

struct MIDIScribeTests {

    @MainActor
    @Test func controlChangeTakeTriggersOnlyFireOnPressedValues() async throws {
        let suiteName = "MIDIScribeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(userDefaults: defaults)
        settings.startTakeWithNoteEvents = false
        settings.takeStartControlChanges = [66]
        settings.takeEndControlChanges = [66]

        let pressed = controlChange(controller: 66, value: 127)
        let released = controlChange(controller: 66, value: 0)

        #expect(settings.shouldStartTake(pressed))
        #expect(settings.shouldEndTake(pressed))
        #expect(!settings.shouldStartTake(released))
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
