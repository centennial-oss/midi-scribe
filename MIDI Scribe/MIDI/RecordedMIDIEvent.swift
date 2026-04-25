//
//  RecordedMIDIEvent.swift
//  MIDI Scribe
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

    nonisolated var isPresetSelectionEvent: Bool {
        kind == .programChange || (kind == .controlChange && (data1 == 0 || data1 == 32))
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
    /// Precomputed summary. Cached so a sidebar / detail view can display
    /// counts without re-scanning the (potentially very large) events array.
    let summary: RecordedTakeSummary

    nonisolated init(id: UUID = UUID(), startedAt: Date, endedAt: Date, events: [RecordedMIDIEvent]) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.summary = RecordedTakeSummary(
            events: events,
            duration: max(endedAt.timeIntervalSince(startedAt), 0)
        )
    }

    nonisolated init(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        events: [RecordedMIDIEvent],
        summary: RecordedTakeSummary
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.events = events
        self.summary = summary
    }

    nonisolated var duration: TimeInterval {
        max(endedAt.timeIntervalSince(startedAt), 0)
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

    nonisolated init(
        eventCount: Int,
        noteOnCount: Int,
        noteOffCount: Int,
        uniqueChannels: [UInt8],
        lowestNote: UInt8?,
        highestNote: UInt8?,
        duration: TimeInterval
    ) {
        self.eventCount = eventCount
        self.noteOnCount = noteOnCount
        self.noteOffCount = noteOffCount
        self.uniqueChannels = uniqueChannels
        self.lowestNote = lowestNote
        self.highestNote = highestNote
        self.duration = duration
    }

    nonisolated init(events: [RecordedMIDIEvent], duration: TimeInterval) {
        var builder = RecordedTakeSummaryBuilder()
        for event in events {
            builder.add(event)
        }
        self = builder.build(duration: duration)
    }

    static let empty = RecordedTakeSummary(
        eventCount: 0,
        noteOnCount: 0,
        noteOffCount: 0,
        uniqueChannels: [],
        lowestNote: nil,
        highestNote: nil,
        duration: 0
    )
}

/// Accumulates a summary in O(1) per event so the live UI never has to
/// re-scan the events array to know counts, channels, or note range.
struct RecordedTakeSummaryBuilder: Sendable {
    private var eventCount = 0
    private var noteOnCount = 0
    private var noteOffCount = 0
    private var channelMask: UInt32 = 0
    private var lowestNote: UInt8?
    private var highestNote: UInt8?

    nonisolated init() {}

    nonisolated mutating func add(_ event: RecordedMIDIEvent) {
        eventCount += 1

        switch event.kind {
        case .noteOn:
            noteOnCount += 1
        case .noteOff:
            noteOffCount += 1
        default:
            break
        }

        if event.channel >= 1 && event.channel <= 16 {
            channelMask |= (1 << (event.channel - 1))
        }

        if let note = event.noteNumber {
            if let current = lowestNote { lowestNote = min(current, note) } else { lowestNote = note }
            if let current = highestNote { highestNote = max(current, note) } else { highestNote = note }
        }
    }

    nonisolated func build(duration: TimeInterval) -> RecordedTakeSummary {
        var channels: [UInt8] = []
        channels.reserveCapacity(16)
        for bit in 0 ..< 16 where channelMask & (1 << bit) != 0 {
            channels.append(UInt8(bit + 1))
        }
        return RecordedTakeSummary(
            eventCount: eventCount,
            noteOnCount: noteOnCount,
            noteOffCount: noteOffCount,
            uniqueChannels: channels,
            lowestNote: lowestNote,
            highestNote: highestNote,
            duration: duration
        )
    }
}
