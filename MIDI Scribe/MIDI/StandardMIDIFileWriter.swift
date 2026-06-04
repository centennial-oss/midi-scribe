//
//  StandardMIDIFileWriter.swift
//  MIDI Scribe
//
//  Encodes a `RecordedTake` as a Standard MIDI File (SMF), Format 1.
//
//  Spec reference: https://midi.org/standard-midi-files
//
//  Design notes:
//  - We emit two tracks. Track 1 is the conductor track (tempo + meta). Track 2
//    holds the recorded channel events. Format 1 allows players to show the
//    tempo/time-signature separately from performance data.
//  - Tempo is fixed at 120 BPM (500_000 microseconds/quarter). Recorded events
//    are scheduled by absolute wall-clock offset, so we convert to ticks using
//    a PPQ (pulses-per-quarter-note) resolution.
//  - Default PPQ of 480 gives ~1ms resolution at 120 BPM, which is plenty for
//    human performance fidelity.
//

import Foundation

enum StandardMIDIFileWriter {
    private static let headerChunkID: UInt32 = 0x4D546864 // "MThd"
    private static let trackChunkID: UInt32 = 0x4D54726B // "MTrk"
    static let defaultTicksPerQuarter: UInt16 = 480
    static let defaultTempoMicrosecondsPerQuarter: UInt32 = 500_000 // 120 BPM

    /// Encode the take as SMF Format 1 bytes.
    static func data(
        for take: RecordedTake,
        ticksPerQuarter: UInt16 = defaultTicksPerQuarter,
        tempoMicrosecondsPerQuarter: UInt32 = defaultTempoMicrosecondsPerQuarter
    ) -> Data {
        var output = Data()
        output.reserveCapacity(estimatedOutputSize(for: take))

        // Header chunk: "MThd" + length(6) + format(1) + ntrks(2) + division
        output.append(uint32BE: headerChunkID)
        output.append(uint32BE: 6)
        output.append(uint16BE: 1) // format 1
        output.append(uint16BE: 2) // two tracks (conductor + performance)
        output.append(uint16BE: ticksPerQuarter)

        appendTrackChunk(to: &output) { body in
            appendConductorTrack(
                to: &body,
                title: take.displayTitle,
                tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter
            )
        }

        appendTrackChunk(to: &output) { body in
            appendPerformanceTrack(
                to: &body,
                take: take,
                ticksPerQuarter: ticksPerQuarter,
                tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter
            )
        }

        return output
    }

    private static func estimatedOutputSize(for take: RecordedTake) -> Int {
        // Header + two track headers + conductor events + a conservative
        // performance estimate: up to four VLQ bytes plus three MIDI bytes.
        14 + take.displayTitle.utf8.count + 24 + (take.events.count * 7)
    }

    private static func appendTrackChunk(to output: inout Data, bodyWriter: (inout Data) -> Void) {
        output.append(uint32BE: trackChunkID)
        let lengthOffset = output.count
        output.append(uint32BE: 0)
        let bodyStart = output.count
        bodyWriter(&output)
        let bodyLength = UInt32(output.count - bodyStart)
        output.replaceUInt32BE(at: lengthOffset, with: bodyLength)
    }

    private static func appendConductorTrack(
        to output: inout Data,
        title: String,
        tempoMicrosecondsPerQuarter: UInt32
    ) {
        // Track name meta event (FF 03 len text)
        output.appendVariableLengthQuantity(0)
        output.append(0xFF)
        output.append(0x03)
        output.appendVariableLengthQuantity(UInt32(title.utf8.count))
        output.append(contentsOf: title.utf8)

        // Set tempo meta event (FF 51 03 tttttt)
        output.appendVariableLengthQuantity(0)
        output.append(contentsOf: [
            0xFF, 0x51, 0x03,
            UInt8((tempoMicrosecondsPerQuarter >> 16) & 0xFF),
            UInt8((tempoMicrosecondsPerQuarter >> 8) & 0xFF),
            UInt8(tempoMicrosecondsPerQuarter & 0xFF)
        ])

        // Time signature: 4/4, 24 clocks/metronome click, 8 32nds per beat
        output.appendVariableLengthQuantity(0)
        output.append(contentsOf: [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08])

        appendEndOfTrack(to: &output)
    }

    private static func appendPerformanceTrack(
        to output: inout Data,
        take: RecordedTake,
        ticksPerQuarter: UInt16,
        tempoMicrosecondsPerQuarter: UInt32
    ) {
        let secondsPerQuarter = Double(tempoMicrosecondsPerQuarter) / 1_000_000.0
        let ticksPerSecond = Double(ticksPerQuarter) / secondsPerQuarter

        var previousTick: UInt32 = 0
        for event in take.events {
            let absoluteTick = UInt32(max(0, (event.offsetFromTakeStart * ticksPerSecond).rounded()))
            let delta = absoluteTick >= previousTick ? absoluteTick - previousTick : 0
            previousTick = absoluteTick

            output.appendVariableLengthQuantity(delta)
            output.appendMIDIEvent(event)
        }

        appendEndOfTrack(to: &output)
    }

    private static func appendEndOfTrack(to output: inout Data) {
        output.appendVariableLengthQuantity(0)
        output.append(contentsOf: [0xFF, 0x2F, 0x00])
    }
}

private extension Data {
    mutating func appendVariableLengthQuantity(_ value: UInt32) {
        var buffer: UInt32 = value & 0x7F
        var shifted = value >> 7
        while shifted > 0 {
            buffer <<= 8
            buffer |= (shifted & 0x7F) | 0x80
            shifted >>= 7
        }

        while true {
            append(UInt8(buffer & 0xFF))
            if buffer & 0x80 != 0 {
                buffer >>= 8
            } else {
                break
            }
        }
    }

    mutating func appendMIDIEvent(_ event: RecordedMIDIEvent) {
        append(event.status)
        append(event.data1)
        if let data2 = event.data2 {
            append(data2)
        }
    }

    mutating func replaceUInt32BE(at offset: Int, with value: UInt32) {
        replaceSubrange(
            offset ..< offset + 4,
            with: [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        )
    }

    mutating func append(uint16BE value: UInt16) {
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func append(uint32BE value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }
}
