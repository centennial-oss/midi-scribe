//
//  StandardMIDIFileReader.swift
//  MIDI Scribe
//

import Foundation

enum StandardMIDIFileReader {
    nonisolated private static let headerChunkID: UInt32 = 0x4D546864 // "MThd"
    nonisolated private static let trackChunkID: UInt32 = 0x4D54726B // "MTrk"

    enum ReaderError: LocalizedError {
        case invalidHeader
        case unsupportedFormat(UInt16)
        case truncatedFile
        case invalidTrack
        case unsupportedTimeDivision

        var errorDescription: String? {
            switch self {
            case .invalidHeader: return "The MIDI file has an invalid header."
            case .unsupportedFormat(let format): return "MIDI format \(format) is not supported."
            case .truncatedFile: return "The MIDI file ended unexpectedly."
            case .invalidTrack: return "The MIDI file contains an invalid track."
            case .unsupportedTimeDivision: return "SMPTE MIDI time division is not supported."
            }
        }
    }

    nonisolated static func take(from data: Data, title: String) throws -> RecordedTake {
        var reader = ByteReader(data: data)
        guard try reader.readUInt32() == headerChunkID else { throw ReaderError.invalidHeader }
        let headerLength = try reader.readUInt32()
        guard headerLength >= 6 else { throw ReaderError.invalidHeader }
        let format = try reader.readUInt16()
        let trackCount = try reader.readUInt16()
        let division = try reader.readUInt16()
        if headerLength > 6 {
            try reader.skip(Int(headerLength - 6))
        }
        guard format == 0 || format == 1 else { throw ReaderError.unsupportedFormat(format) }
        guard division & 0x8000 == 0 else { throw ReaderError.unsupportedTimeDivision }

        var events: [RecordedMIDIEvent] = []
        for _ in 0 ..< trackCount {
            guard try reader.readUInt32() == trackChunkID else { throw ReaderError.invalidTrack }
            let trackLength = Int(try reader.readUInt32())
            var trackReader = try reader.readLimitedReader(count: trackLength)
            events.append(contentsOf: try readTrack(&trackReader, ticksPerQuarterNote: Int(division)))
        }

        events.sort {
            if $0.offsetFromTakeStart == $1.offsetFromTakeStart {
                return $0.status < $1.status
            }
            return $0.offsetFromTakeStart < $1.offsetFromTakeStart
        }

        let start = Date()
        let duration = events.last?.offsetFromTakeStart ?? 0
        return RecordedTake(
            id: UUID(),
            startedAt: start,
            endedAt: start.addingTimeInterval(duration),
            events: events,
            eventsAreSorted: true
        )
    }

    private nonisolated static func readTrack(
        _ reader: inout ByteReader,
        ticksPerQuarterNote: Int
    ) throws -> [RecordedMIDIEvent] {
        var tempoMicrosecondsPerQuarter = 500_000
        var absoluteSeconds: TimeInterval = 0
        var runningStatus: UInt8?
        var events: [RecordedMIDIEvent] = []

        while !reader.isAtEnd {
            let deltaTicks = try reader.readVariableLengthQuantity()
            absoluteSeconds += seconds(
                forTicks: deltaTicks,
                ticksPerQuarterNote: ticksPerQuarterNote,
                tempo: tempoMicrosecondsPerQuarter
            )

            var status = try reader.readUInt8()
            if status < 0x80 {
                guard let previousStatus = runningStatus else { throw ReaderError.invalidTrack }
                reader.unreadByte()
                status = previousStatus
            } else if status < 0xF0 {
                runningStatus = status
            }

            if status == 0xFF {
                if try readMetaEvent(&reader, tempoMicrosecondsPerQuarter: &tempoMicrosecondsPerQuarter) {
                    break
                }
                continue
            }

            if status == 0xF0 || status == 0xF7 {
                let length = try reader.readVariableLengthQuantity()
                try reader.skip(length)
                continue
            }

            events.append(try readChannelEvent(status: status, offset: absoluteSeconds, from: &reader))
        }

        return events
    }

    private nonisolated static func readChannelEvent(
        status: UInt8,
        offset: TimeInterval,
        from reader: inout ByteReader
    ) throws -> RecordedMIDIEvent {
        guard let kind = MIDIChannelEventKind(statusByte: status) else {
            throw ReaderError.invalidTrack
        }

        let data1 = try reader.readUInt8()
        let data2 = kind.hasSecondDataByte ? try reader.readUInt8() : nil
        let normalizedKind: MIDIChannelEventKind = kind == .noteOn && data2 == 0 ? .noteOff : kind
        return RecordedMIDIEvent(
            receivedAt: Date().addingTimeInterval(offset),
            offsetFromTakeStart: offset,
            kind: normalizedKind,
            channel: (status & 0x0F) + 1,
            status: status,
            data1: data1,
            data2: data2
        )
    }

    private nonisolated static func readMetaEvent(
        _ reader: inout ByteReader,
        tempoMicrosecondsPerQuarter: inout Int
    ) throws -> Bool {
        let metaType = try reader.readUInt8()
        let length = try reader.readVariableLengthQuantity()
        if metaType == 0x51, length == 3 {
            tempoMicrosecondsPerQuarter = try tempo(from: &reader)
        } else {
            try reader.skip(length)
        }
        return metaType == 0x2F
    }

    private nonisolated static func tempo(from reader: inout ByteReader) throws -> Int {
        let byte1 = try reader.readUInt8()
        let byte2 = try reader.readUInt8()
        let byte3 = try reader.readUInt8()
        return (Int(byte1) << 16) | (Int(byte2) << 8) | Int(byte3)
    }

    private nonisolated static func seconds(forTicks ticks: Int, ticksPerQuarterNote: Int, tempo: Int) -> TimeInterval {
        (Double(ticks) * Double(tempo)) / (Double(ticksPerQuarterNote) * 1_000_000)
    }
}

private extension MIDIChannelEventKind {
    nonisolated init?(statusByte: UInt8) {
        switch statusByte & 0xF0 {
        case 0x80: self = .noteOff
        case 0x90: self = .noteOn
        case 0xA0: self = .polyphonicKeyPressure
        case 0xB0: self = .controlChange
        case 0xC0: self = .programChange
        case 0xD0: self = .channelPressure
        case 0xE0: self = .pitchBend
        default: return nil
        }
    }

    nonisolated var hasSecondDataByte: Bool {
        switch self {
        case .programChange, .channelPressure:
            return false
        case .noteOff, .noteOn, .polyphonicKeyPressure, .controlChange, .pitchBend:
            return true
        }
    }
}

private struct ByteReader {
    private let data: Data
    private var offset: Int
    private let endOffset: Int

    nonisolated init(data: Data) {
        self.data = data
        self.offset = data.startIndex
        self.endOffset = data.endIndex
    }

    private nonisolated init(data: Data, range: Range<Int>) {
        self.data = data
        self.offset = range.lowerBound
        self.endOffset = range.upperBound
    }

    nonisolated var isAtEnd: Bool {
        offset >= endOffset
    }

    nonisolated mutating func unreadByte() {
        offset = max(offset - 1, 0)
    }

    nonisolated mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= endOffset else {
            throw StandardMIDIFileReader.ReaderError.truncatedFile
        }
        offset += count
    }

    nonisolated mutating func readLimitedReader(count: Int) throws -> ByteReader {
        guard count >= 0, offset + count <= endOffset else {
            throw StandardMIDIFileReader.ReaderError.truncatedFile
        }
        let range = offset ..< (offset + count)
        offset += count
        return ByteReader(data: data, range: range)
    }

    nonisolated mutating func readUInt8() throws -> UInt8 {
        guard offset < endOffset else { throw StandardMIDIFileReader.ReaderError.truncatedFile }
        let value = data[offset]
        offset += 1
        return value
    }

    nonisolated mutating func readUInt16() throws -> UInt16 {
        let high = UInt16(try readUInt8())
        let low = UInt16(try readUInt8())
        return (high << 8) | low
    }

    nonisolated mutating func readUInt32() throws -> UInt32 {
        let byte1 = UInt32(try readUInt8())
        let byte2 = UInt32(try readUInt8())
        let byte3 = UInt32(try readUInt8())
        let byte4 = UInt32(try readUInt8())
        return (byte1 << 24) | (byte2 << 16) | (byte3 << 8) | byte4
    }

    nonisolated mutating func readVariableLengthQuantity() throws -> Int {
        var value = 0
        for _ in 0 ..< 4 {
            let byte = try readUInt8()
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 {
                return value
            }
        }
        throw StandardMIDIFileReader.ReaderError.invalidTrack
    }
}
