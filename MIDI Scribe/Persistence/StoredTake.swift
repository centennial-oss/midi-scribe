//
//  StoredTake.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Foundation
import SwiftData

@Model
final class StoredTake {
    @Attribute(.unique) var takeID: String
    var startedAt: Date
    var endedAt: Date
    var title: String

    /// Cached summary fields. Populated at save time so sidebar/list views
    /// can show counts without faulting in the (potentially huge) events
    /// relationship.
    var eventCount: Int = 0
    var noteOnCount: Int = 0
    var noteOffCount: Int = 0
    /// Bitmask of channels 1...16. Bit 0 == channel 1.
    var channelMask: Int = 0
    var lowestNote: Int? = nil
    var highestNote: Int? = nil

    @Relationship(deleteRule: .cascade, inverse: \StoredMIDIEvent.take) var events: [StoredMIDIEvent]

    init(takeID: String, startedAt: Date, endedAt: Date, title: String, events: [StoredMIDIEvent] = []) {
        self.takeID = takeID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.title = title
        self.events = events
    }

    convenience init(recordedTake: RecordedTake) {
        self.init(
            takeID: recordedTake.id.uuidString,
            startedAt: recordedTake.startedAt,
            endedAt: recordedTake.endedAt,
            title: recordedTake.displayTitle
        )
        events = recordedTake.events.map { StoredMIDIEvent(recordedEvent: $0, take: self) }

        let summary = recordedTake.summary
        eventCount = summary.eventCount
        noteOnCount = summary.noteOnCount
        noteOffCount = summary.noteOffCount
        channelMask = Self.channelMask(from: summary.uniqueChannels)
        lowestNote = summary.lowestNote.map(Int.init)
        highestNote = summary.highestNote.map(Int.init)
    }

    /// Summary built from the cached fields without touching `events`.
    var cachedSummary: RecordedTakeSummary {
        RecordedTakeSummary(
            eventCount: eventCount,
            noteOnCount: noteOnCount,
            noteOffCount: noteOffCount,
            uniqueChannels: Self.channels(from: channelMask),
            lowestNote: lowestNote.map { UInt8(clamping: $0) },
            highestNote: highestNote.map { UInt8(clamping: $0) },
            duration: max(endedAt.timeIntervalSince(startedAt), 0)
        )
    }

    /// Lightweight list item that does NOT touch the `events` relationship.
    /// Use this for the sidebar / menu bar / any list view.
    var listItem: RecordedTakeListItem {
        RecordedTakeListItem(
            id: UUID(uuidString: takeID) ?? UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            title: title,
            summary: cachedSummary
        )
    }

    /// Fully materialized take with events. Only call when you actually need
    /// to play back or inspect individual events.
    var recordedTake: RecordedTake {
        let sortedEvents = events
            .sorted { lhs, rhs in
                if lhs.offsetFromTakeStart == rhs.offsetFromTakeStart {
                    return lhs.receivedAt < rhs.receivedAt
                }
                return lhs.offsetFromTakeStart < rhs.offsetFromTakeStart
            }
            .map(\.recordedEvent)

        return RecordedTake(
            id: UUID(uuidString: takeID) ?? UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            events: sortedEvents,
            summary: cachedSummary
        )
    }

    private static func channelMask(from channels: [UInt8]) -> Int {
        var mask: Int = 0
        for channel in channels where channel >= 1 && channel <= 16 {
            mask |= (1 << (channel - 1))
        }
        return mask
    }

    private static func channels(from mask: Int) -> [UInt8] {
        var result: [UInt8] = []
        result.reserveCapacity(16)
        for bit in 0 ..< 16 where mask & (1 << bit) != 0 {
            result.append(UInt8(bit + 1))
        }
        return result
    }
}

/// Sidebar-friendly value that carries only summary info, never events.
struct RecordedTakeListItem: Identifiable, Sendable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let title: String
    let summary: RecordedTakeSummary

    var displayTitle: String { title }
    var duration: TimeInterval { max(endedAt.timeIntervalSince(startedAt), 0) }
}

@Model
final class StoredMIDIEvent {
    @Attribute(.unique) var eventID: String
    var receivedAt: Date
    var offsetFromTakeStart: TimeInterval
    var kindRawValue: String
    var channel: Int
    var status: Int
    var data1: Int
    var data2: Int?
    /// Optional so SwiftData can nullify the inverse during batch deletes.
    /// Also required for future CloudKit mirroring.
    var take: StoredTake?

    init(
        eventID: String,
        receivedAt: Date,
        offsetFromTakeStart: TimeInterval,
        kindRawValue: String,
        channel: Int,
        status: Int,
        data1: Int,
        data2: Int? = nil,
        take: StoredTake? = nil
    ) {
        self.eventID = eventID
        self.receivedAt = receivedAt
        self.offsetFromTakeStart = offsetFromTakeStart
        self.kindRawValue = kindRawValue
        self.channel = channel
        self.status = status
        self.data1 = data1
        self.data2 = data2
        self.take = take
    }

    convenience init(recordedEvent: RecordedMIDIEvent, take: StoredTake? = nil) {
        self.init(
            eventID: recordedEvent.id.uuidString,
            receivedAt: recordedEvent.receivedAt,
            offsetFromTakeStart: recordedEvent.offsetFromTakeStart,
            kindRawValue: recordedEvent.kind.rawValue,
            channel: Int(recordedEvent.channel),
            status: Int(recordedEvent.status),
            data1: Int(recordedEvent.data1),
            data2: recordedEvent.data2.map(Int.init),
            take: take
        )
    }

    var recordedEvent: RecordedMIDIEvent {
        RecordedMIDIEvent(
            id: UUID(uuidString: eventID) ?? UUID(),
            receivedAt: receivedAt,
            offsetFromTakeStart: offsetFromTakeStart,
            kind: MIDIChannelEventKind(rawValue: kindRawValue) ?? .controlChange,
            channel: UInt8(channel),
            status: UInt8(status),
            data1: UInt8(data1),
            data2: data2.map(UInt8.init)
        )
    }
}
