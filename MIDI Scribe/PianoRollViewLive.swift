//
//  PianoRollView+Live.swift
//  MIDI Scribe
//
//  Incremental (append-only) piano-roll updates used while a take is
//  being actively recorded. Keeping this logic out of the main
//  PianoRollView file both shortens that file and isolates the O(1)
//  per-event ingestion that replaced an O(n)-per-event rebuild.
//

import Foundation
import SwiftUI

extension PianoRollView {
    /// MIDI channel-voice data bytes are 7-bit (0...127). We defensively
    /// skip malformed legacy/corrupt events when building the piano roll.
    private func isRenderableMIDIEvent(_ event: RecordedMIDIEvent) -> Bool {
        guard event.channel >= 1 && event.channel <= 16 else {
            ignoredMalformedEventIDs.insert(event.id)
            return false
        }
        guard event.data1 <= 127 else {
            ignoredMalformedEventIDs.insert(event.id)
            return false
        }
        if let data2 = event.data2, data2 > 127 {
            ignoredMalformedEventIDs.insert(event.id)
            return false
        }
        return true
    }

    /// Called when `take.events.count` changes in live mode. Processes
    /// only the events that arrived since the last call.
    func ingestNewLiveEvents(upTo newCount: Int) {
        let events = take.events
        if newCount < liveEventsProcessedCount {
            // Events array shrank; a new take started. Rebuild from scratch.
            resetLiveCursors()
            computeNotes()
            liveEventsProcessedCount = events.count
            return
        }
        guard newCount > liveEventsProcessedCount, newCount <= events.count else { return }

        for index in liveEventsProcessedCount ..< newCount {
            ingestLiveEvent(events[index])
        }
        liveEventsProcessedCount = newCount
    }

    private func ingestLiveEvent(_ event: RecordedMIDIEvent) {
        guard isRenderableMIDIEvent(event) else { return }
        switch event.kind {
        case .noteOn, .noteOff:
            ingestLiveNoteEvent(event)
        case .controlChange:
            ingestLiveCCEvent(event)
        default:
            return
        }
    }

    private func ingestLiveNoteEvent(_ event: RecordedMIDIEvent) {
        guard let pitch = event.noteNumber else { return }
        let isNoteOn = event.kind == .noteOn && (event.velocity ?? 0) > 0
        if isNoteOn {
            if var prior = liveActiveNotes[pitch] {
                prior.duration = max(0.01, event.offsetFromTakeStart - prior.startOffset)
                notes.append(prior)
            }
            liveActiveNotes[pitch] = PianoRollNote(
                pitch: pitch,
                channel: event.channel,
                velocity: event.velocity ?? 80,
                startOffset: event.offsetFromTakeStart,
                duration: 0
            )
        } else if var active = liveActiveNotes[pitch] {
            active.duration = max(0.01, event.offsetFromTakeStart - active.startOffset)
            notes.append(active)
            liveActiveNotes[pitch] = nil
        }
    }

    private func ingestLiveCCEvent(_ event: RecordedMIDIEvent) {
        let ccNumber = event.data1
        let isOn = (event.data2 ?? 0) >= 64
        if isOn {
            if liveActiveCCs[ccNumber] == nil {
                liveActiveCCs[ccNumber] = PianoRollCC(
                    kind: ccKind(for: ccNumber),
                    startOffset: event.offsetFromTakeStart,
                    duration: 0
                )
            }
        } else if var active = liveActiveCCs[ccNumber] {
            active.duration = max(0.01, event.offsetFromTakeStart - active.startOffset)
            ccEvents.append(active)
            liveActiveCCs[ccNumber] = nil
        }
    }

    private func ccKind(for ccNumber: UInt8) -> PianoRollCCKind {
        switch ccNumber {
        case 64: return .sustain
        case 66: return .sostenuto
        case 67: return .soft
        default: return .other
        }
    }
}

extension PianoRollView {
    func computeNoteEvents() {
        var activeNotes: [UInt8: PianoRollNote] = [:]
        var result: [PianoRollNote] = []
        let sortedEvents = take.events.sorted { $0.offsetFromTakeStart < $1.offsetFromTakeStart }

        for event in sortedEvents {
            guard isRenderableMIDIEvent(event) else { continue }
            guard let pitch = event.noteNumber else { continue }
            if event.kind == .noteOn && (event.velocity ?? 0) > 0 {
                if var active = activeNotes[pitch] {
                    active.duration = event.offsetFromTakeStart - active.startOffset
                    result.append(active)
                }
                activeNotes[pitch] = PianoRollNote(
                    pitch: pitch,
                    channel: event.channel,
                    velocity: event.velocity ?? 80,
                    startOffset: event.offsetFromTakeStart,
                    duration: 0
                )
            } else if event.kind == .noteOff || (event.kind == .noteOn && event.velocity == 0) {
                if var active = activeNotes[pitch] {
                    active.duration = max(0.01, event.offsetFromTakeStart - active.startOffset)
                    result.append(active)
                    activeNotes[pitch] = nil
                }
            }
        }

        for (_, var active) in activeNotes {
            active.duration = max(0.01, take.duration - active.startOffset)
            result.append(active)
        }
        notes = result
    }

    func computeCCs() {
        var activeCCs: [UInt8: PianoRollCC] = [:]
        var resultCCs: [PianoRollCC] = []
        let sortedEvents = take.events.sorted { $0.offsetFromTakeStart < $1.offsetFromTakeStart }

        for event in sortedEvents where event.kind == .controlChange {
            guard isRenderableMIDIEvent(event) else { continue }
            let ccNumber = event.data1
            let isOn = (event.data2 ?? 0) >= 64

            if isOn {
                if activeCCs[ccNumber] == nil {
                    activeCCs[ccNumber] = PianoRollCC(
                        kind: ccKindFor(ccNumber),
                        startOffset: event.offsetFromTakeStart,
                        duration: 0
                    )
                }
            } else if var active = activeCCs[ccNumber] {
                active.duration = max(0.01, event.offsetFromTakeStart - active.startOffset)
                resultCCs.append(active)
                activeCCs[ccNumber] = nil
            }
        }

        for (_, var active) in activeCCs {
            active.duration = max(0.01, take.duration - active.startOffset)
            resultCCs.append(active)
        }
        ccEvents = resultCCs
    }

    private func ccKindFor(_ ccNumber: UInt8) -> PianoRollCCKind {
        switch ccNumber {
        case 64: return .sustain
        case 66: return .sostenuto
        case 67: return .soft
        default: return .other
        }
    }
}

/// Precomputed drawing parameters for a single Canvas pass over all notes
/// and CCs. Bundled into a struct to keep per-note draw helpers under the
/// linter's parameter-count limit.
struct PianoRollDrawContext {
    let keyHeight: CGFloat
    let noteHeight: CGFloat
    let ccHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let playOffset: TimeInterval
    let idleNoteColor: Color
    let playingNoteColor: Color
}

extension PianoRollView {
    func drawNotesAndCCs(
        into context: GraphicsContext,
        keyHeight: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) {
        let drawContext = PianoRollDrawContext(
            keyHeight: keyHeight,
            noteHeight: max(1, keyHeight - 1),
            ccHeight: max(4, keyHeight),
            pixelsPerSecond: pixelsPerSecond,
            playOffset: playOffset,
            idleNoteColor: Color(red: 0.6, green: 1.0, blue: 0.2),
            playingNoteColor: Color(red: 1.0, green: 0.2, blue: 0.8)
        )
        let tail = take.duration

        for note in notes {
            drawNote(note, into: context, drawContext: drawContext)
        }
        for (_, open) in liveActiveNotes {
            var note = open
            note.duration = max(0.01, tail - note.startOffset)
            drawNote(note, into: context, drawContext: drawContext)
        }
        for ccEvent in ccEvents {
            drawCC(ccEvent, into: context, drawContext: drawContext)
        }
        for (_, open) in liveActiveCCs {
            var ccEvent = open
            ccEvent.duration = max(0.01, tail - ccEvent.startOffset)
            drawCC(ccEvent, into: context, drawContext: drawContext)
        }
    }

    private func drawNote(
        _ note: PianoRollNote,
        into context: GraphicsContext,
        drawContext: PianoRollDrawContext
    ) {
        let startX = note.startOffset * drawContext.pixelsPerSecond
        let width = max(2, note.duration * drawContext.pixelsPerSecond)
        let topY = pitchToY(pitch: note.pitch, keyHeight: drawContext.keyHeight) + 12
        let rect = CGRect(x: startX, y: topY, width: width, height: drawContext.noteHeight)
        let path = Path(roundedRect: rect, cornerRadius: 1)
        let playing = isNotePlaying(note, currentOffset: drawContext.playOffset)
        let baseColor = playing ? drawContext.playingNoteColor : drawContext.idleNoteColor
        context.fill(path, with: .color(baseColor.opacity(opacity(forVelocity: note.velocity))))
    }

    private func opacity(forVelocity velocity: UInt8) -> Double {
        let normalized = min(Double(velocity), 100) / 100
        return 0.05 + (normalized * 0.95)
    }

    private func drawCC(
        _ ccEvent: PianoRollCC,
        into context: GraphicsContext,
        drawContext: PianoRollDrawContext
    ) {
        let startX = ccEvent.startOffset * drawContext.pixelsPerSecond
        let width = max(2, ccEvent.duration * drawContext.pixelsPerSecond)
        let rect = CGRect(x: startX, y: 12, width: width, height: drawContext.ccHeight)
        context.fill(Path(rect), with: .color(ccEvent.kind.color))
    }

    private func pitchToY(pitch: UInt8, keyHeight: CGFloat) -> CGFloat {
        let safePitch = max(21, min(108, pitch))
        let inverted = 108 - safePitch
        return CGFloat(inverted) * keyHeight
    }

    private func isNotePlaying(_ note: PianoRollNote, currentOffset: TimeInterval) -> Bool {
        currentOffset >= note.startOffset && currentOffset <= (note.startOffset + note.duration)
    }
}
