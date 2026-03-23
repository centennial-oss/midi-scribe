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
    }

    var recordedTake: RecordedTake {
        RecordedTake(
            id: UUID(uuidString: takeID) ?? UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            events: events
                .sorted { lhs, rhs in
                    if lhs.offsetFromTakeStart == rhs.offsetFromTakeStart {
                        return lhs.receivedAt < rhs.receivedAt
                    }
                    return lhs.offsetFromTakeStart < rhs.offsetFromTakeStart
                }
                .map(\.recordedEvent)
        )
    }
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
