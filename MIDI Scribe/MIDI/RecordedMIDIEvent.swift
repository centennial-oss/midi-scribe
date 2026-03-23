//
//  RecordedMIDIEvent.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Foundation

enum MIDIChannelEventKind: String, Sendable {
    case noteOff
    case noteOn
    case polyphonicKeyPressure
    case controlChange
    case programChange
    case channelPressure
    case pitchBend
}

struct RecordedMIDIEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    let receivedAt: Date
    let offsetFromTakeStart: TimeInterval
    let kind: MIDIChannelEventKind
    let channel: UInt8
    let status: UInt8
    let data1: UInt8
    let data2: UInt8?

    nonisolated init(
        id: UUID = UUID(),
        receivedAt: Date,
        offsetFromTakeStart: TimeInterval,
        kind: MIDIChannelEventKind,
        channel: UInt8,
        status: UInt8,
        data1: UInt8,
        data2: UInt8? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.offsetFromTakeStart = offsetFromTakeStart
        self.kind = kind
        self.channel = channel
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }

    nonisolated var noteNumber: UInt8? {
        switch kind {
        case .noteOn, .noteOff, .polyphonicKeyPressure:
            data1
        default:
            nil
        }
    }

    nonisolated var velocity: UInt8? {
        switch kind {
        case .noteOn, .noteOff:
            data2
        default:
            nil
        }
    }

    nonisolated var midiData: [UInt8] {
        if let data2 {
            return [status, data1, data2]
        }

        return [status, data1]
    }
}

struct RecordedTake: Identifiable, Sendable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let events: [RecordedMIDIEvent]

    nonisolated init(id: UUID = UUID(), startedAt: Date, endedAt: Date, events: [RecordedMIDIEvent]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
    }

    nonisolated var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
    }

    nonisolated var summary: RecordedTakeSummary {
        RecordedTakeSummary(events: events, duration: duration)
    }

    nonisolated var displayTitle: String {
        Self.displayFormatter.string(from: startedAt)
    }

    private nonisolated static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()
}

struct RecordedTakeSummary: Sendable, Equatable {
    let eventCount: Int
    let noteOnCount: Int
    let noteOffCount: Int
    let uniqueChannels: [UInt8]
    let lowestNote: UInt8?
    let highestNote: UInt8?
    let duration: TimeInterval

    nonisolated init(events: [RecordedMIDIEvent], duration: TimeInterval) {
        eventCount = events.count
        noteOnCount = events.filter { $0.kind == .noteOn }.count
        noteOffCount = events.filter { $0.kind == .noteOff }.count
        uniqueChannels = Array(Set(events.map(\.channel))).sorted()

        let noteNumbers = events.compactMap(\.noteNumber)
        lowestNote = noteNumbers.min()
        highestNote = noteNumbers.max()
        self.duration = duration
    }
}
