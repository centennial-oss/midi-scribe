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
}
