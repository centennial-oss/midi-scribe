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
    static let defaultTicksPerQuarter: UInt16 = 480
    static let defaultTempoMicrosecondsPerQuarter: UInt32 = 500_000 // 120 BPM

    /// Encode the take as SMF Format 1 bytes.
    static func data(
        for take: RecordedTake,
        ticksPerQuarter: UInt16 = defaultTicksPerQuarter,
        tempoMicrosecondsPerQuarter: UInt32 = defaultTempoMicrosecondsPerQuarter
    ) -> Data {
        var output = Data()

        // Header chunk: "MThd" + length(6) + format(1) + ntrks(2) + division
        output.append(contentsOf: Array("MThd".utf8))
        output.append(uint32BE: 6)
        output.append(uint16BE: 1) // format 1
        output.append(uint16BE: 2) // two tracks (conductor + performance)
        output.append(uint16BE: ticksPerQuarter)

        output.append(
            trackChunk(for: conductorTrackEvents(
                title: take.displayTitle,
                tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter
            ))
        )

        output.append(
            trackChunk(for: performanceTrackEvents(
                take: take,
                ticksPerQuarter: ticksPerQuarter,
                tempoMicrosecondsPerQuarter: tempoMicrosecondsPerQuarter
            ))
        )

        return output
    }

    // MARK: - Track event construction

    private struct TrackEvent {
        let deltaTicks: UInt32
        let bytes: [UInt8]
    }

    private static func conductorTrackEvents(
        title: String,
        tempoMicrosecondsPerQuarter: UInt32
    ) -> [TrackEvent] {
        var events: [TrackEvent] = []

        // Track name meta event (FF 03 len text)
        let titleBytes = Array(title.utf8)
        events.append(TrackEvent(
            deltaTicks: 0,
            bytes: [0xFF, 0x03] + variableLengthQuantity(UInt32(titleBytes.count)) + titleBytes
        ))

        // Set tempo meta event (FF 51 03 tttttt)
        let tempo = tempoMicrosecondsPerQuarter
        events.append(TrackEvent(
            deltaTicks: 0,
            bytes: [
                0xFF, 0x51, 0x03,
                UInt8((tempo >> 16) & 0xFF),
                UInt8((tempo >> 8) & 0xFF),
                UInt8(tempo & 0xFF)
            ]
        ))

        // Time signature: 4/4, 24 clocks/metronome click, 8 32nds per beat
        events.append(TrackEvent(
            deltaTicks: 0,
            bytes: [0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]
        ))

        // End of track
        events.append(TrackEvent(deltaTicks: 0, bytes: [0xFF, 0x2F, 0x00]))
        return events
    }

    private static func performanceTrackEvents(
        take: RecordedTake,
        ticksPerQuarter: UInt16,
        tempoMicrosecondsPerQuarter: UInt32
    ) -> [TrackEvent] {
        var events: [TrackEvent] = []

        let secondsPerQuarter = Double(tempoMicrosecondsPerQuarter) / 1_000_000.0
        let ticksPerSecond = Double(ticksPerQuarter) / secondsPerQuarter

        // Events are already ordered by offsetFromTakeStart after persistence,
        // but be defensive: sort by absolute tick.
        let sortedEvents = take.events.sorted { $0.offsetFromTakeStart < $1.offsetFromTakeStart }

        var previousTick: UInt32 = 0
        for event in sortedEvents {
            let absoluteTick = UInt32(max(0, (event.offsetFromTakeStart * ticksPerSecond).rounded()))
            let delta = absoluteTick >= previousTick ? absoluteTick - previousTick : 0
            previousTick = absoluteTick

            events.append(TrackEvent(deltaTicks: delta, bytes: event.midiData))
        }

        events.append(TrackEvent(deltaTicks: 0, bytes: [0xFF, 0x2F, 0x00]))
        return events
    }

    private static func trackChunk(for events: [TrackEvent]) -> Data {
        var body = Data()
        for event in events {
            body.append(contentsOf: variableLengthQuantity(event.deltaTicks))
            body.append(contentsOf: event.bytes)
        }

        var chunk = Data()
        chunk.append(contentsOf: Array("MTrk".utf8))
        chunk.append(uint32BE: UInt32(body.count))
        chunk.append(body)
        return chunk
    }

    // MARK: - Variable-length quantity encoding per SMF spec

    private static func variableLengthQuantity(_ value: UInt32) -> [UInt8] {
        var buffer: UInt32 = value & 0x7F
        var shifted = value >> 7
        while shifted > 0 {
            buffer <<= 8
            buffer |= (shifted & 0x7F) | 0x80
            shifted >>= 7
        }

        var result: [UInt8] = []
        while true {
            result.append(UInt8(buffer & 0xFF))
            if buffer & 0x80 != 0 {
                buffer >>= 8
            } else {
                break
            }
        }
        return result
    }
}

private extension Data {
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
