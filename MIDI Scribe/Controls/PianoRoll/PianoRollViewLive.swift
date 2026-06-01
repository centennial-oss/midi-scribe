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
    /// for dev purposes, set to true to show all CC lanes for color checks
    private var shouldRenderDebugFullLengthCCLanes: Bool {
        false
    }

    private var hiddenPianoRollControlChanges: Set<UInt8> {
        [19, 88]
    }

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
                appendNote(prior)
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
            appendNote(active)
            liveActiveNotes[pitch] = nil
        }
    }

    /// Appends a closed note and keeps `notesByID` in sync.
    private func appendNote(_ note: PianoRollNote) {
        notes.append(note)
        notesByID[note.id] = note
        notesRenderToken &+= 1
    }

    /// Rebuilds `notesByID` from the current `notes` array. Called after a
    /// full recompute (`computeNotes`).
    func rebuildNotesByID() {
        var map: [UUID: PianoRollNote] = [:]
        map.reserveCapacity(notes.count)
        for note in notes {
            map[note.id] = note
        }
        notesByID = map
    }

    private func ingestLiveCCEvent(_ event: RecordedMIDIEvent) {
        let ccNumber = event.data1
        guard !hiddenPianoRollControlChanges.contains(ccNumber) else { return }
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
            notesRenderToken &+= 1
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
    /// Builds the note and CC models. `take.events` is sorted and validated
    /// once here and the result shared between both builders, rather than each
    /// model independently sorting (and re-validating) the same array.
    func computeNotes() {
        let renderableEvents = take.events
            .sorted { $0.offsetFromTakeStart < $1.offsetFromTakeStart }
            .filter { isRenderableMIDIEvent($0) }

        notes = buildNotes(from: renderableEvents)
        rebuildNotesByID()
        ccEvents = buildCCs(from: renderableEvents)
        auditionTracker.reset(with: notes)
        notesRenderToken &+= 1
    }

    private func buildNotes(from sortedEvents: [RecordedMIDIEvent]) -> [PianoRollNote] {
        var activeNotes: [UInt8: PianoRollNote] = [:]
        var result: [PianoRollNote] = []

        for event in sortedEvents {
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
        return result
    }

    private func buildCCs(from sortedEvents: [RecordedMIDIEvent]) -> [PianoRollCC] {
        if shouldRenderDebugFullLengthCCLanes {
            return PianoRollCCKind.allCases.map { kind in
                PianoRollCC(kind: kind, startOffset: 0, duration: max(0.01, take.duration))
            }
        }

        var activeCCs: [UInt8: PianoRollCC] = [:]
        var result: [PianoRollCC] = []

        for event in sortedEvents where event.kind == .controlChange {
            let ccNumber = event.data1
            guard !hiddenPianoRollControlChanges.contains(ccNumber) else { continue }
            let isOn = (event.data2 ?? 0) >= 64
            if isOn {
                if activeCCs[ccNumber] == nil {
                    activeCCs[ccNumber] = PianoRollCC(
                        kind: ccKind(for: ccNumber),
                        startOffset: event.offsetFromTakeStart,
                        duration: 0
                    )
                }
            } else if var active = activeCCs[ccNumber] {
                active.duration = max(0.01, event.offsetFromTakeStart - active.startOffset)
                result.append(active)
                activeCCs[ccNumber] = nil
            }
        }

        for (_, var active) in activeCCs {
            active.duration = max(0.01, take.duration - active.startOffset)
            result.append(active)
        }
        return result
    }
}

/// Precomputed drawing parameters shared by the static and dynamic Canvas
/// layers. Deliberately excludes the playhead offset so the static layer's
/// `Equatable` comparison stays stable across animation frames (only the
/// dynamic layer cares about which notes are under the playhead).
struct PianoRollDrawContext: Equatable {
    let keyHeight: CGFloat
    let noteHeight: CGFloat
    let ccLaneHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let timelineLeadingInset: CGFloat
    let idleNoteColor: Color
    let playingNoteColor: Color
}

extension PianoRollView {
    func drawDynamicNotesAndCCs(
        into context: GraphicsContext,
        drawContext: PianoRollDrawContext,
        playOffset: TimeInterval,
        visibleXRange: ClosedRange<CGFloat>?,
        backgroundColor: Color
    ) {
        for note in notes where pianoRollIsNotePlaying(note, currentOffset: playOffset) {
            pianoRollEraseNote(
                note, into: context, drawContext: drawContext,
                backgroundColor: backgroundColor, visibleXRange: visibleXRange
            )
            pianoRollDrawNote(
                note, playing: true, into: context,
                drawContext: drawContext, visibleXRange: visibleXRange
            )
        }

        let tail = take.duration
        for (_, open) in liveActiveNotes {
            var note = open
            note.duration = max(0.01, tail - note.startOffset)
            let playing = pianoRollIsNotePlaying(note, currentOffset: playOffset)
            pianoRollDrawNote(
                note, playing: playing, into: context,
                drawContext: drawContext, visibleXRange: visibleXRange
            )
        }
        for (_, open) in liveActiveCCs {
            var ccEvent = open
            ccEvent.duration = max(0.01, tail - ccEvent.startOffset)
            pianoRollDrawCC(ccEvent, into: context, drawContext: drawContext, visibleXRange: visibleXRange)
        }
    }
}

struct PianoRollStaticNotesLayer: View, Equatable {
    let notesToken: Int
    let notes: [PianoRollNote]
    let ccEvents: [PianoRollCC]
    let drawContext: PianoRollDrawContext
    let visibleXRange: ClosedRange<CGFloat>?
    let rollWidth: CGFloat
    let viewHeight: CGFloat

    static func == (lhs: PianoRollStaticNotesLayer, rhs: PianoRollStaticNotesLayer) -> Bool {
        lhs.notesToken == rhs.notesToken
            && lhs.rollWidth == rhs.rollWidth
            && lhs.viewHeight == rhs.viewHeight
            && lhs.visibleXRange == rhs.visibleXRange
            && lhs.drawContext == rhs.drawContext
    }

    var body: some View {
        Canvas { context, _ in
            for note in notes {
                pianoRollDrawNote(
                    note, playing: false, into: context,
                    drawContext: drawContext, visibleXRange: visibleXRange
                )
            }
            for ccEvent in ccEvents {
                pianoRollDrawCC(ccEvent, into: context, drawContext: drawContext, visibleXRange: visibleXRange)
            }
        }
        .frame(width: rollWidth, height: viewHeight)
        .allowsHitTesting(false)
    }
}

// MARK: - Shared free-function draw primitives (used by both layers)

private func pianoRollNoteRect(_ note: PianoRollNote, drawContext: PianoRollDrawContext) -> CGRect {
    let startX = drawContext.timelineLeadingInset + (note.startOffset * drawContext.pixelsPerSecond)
    let width = max(2, note.duration * drawContext.pixelsPerSecond)
    let topY = pianoRollPitchToY(pitch: note.pitch, keyHeight: drawContext.keyHeight)
        + PianoRollView.contentTopInset
    return CGRect(x: startX, y: topY, width: width, height: drawContext.noteHeight)
}

private func pianoRollRectIsVisible(_ rect: CGRect, in visibleXRange: ClosedRange<CGFloat>?) -> Bool {
    guard let visibleXRange else { return true }
    return rect.maxX >= visibleXRange.lowerBound && rect.minX <= visibleXRange.upperBound
}

func pianoRollDrawNote(
    _ note: PianoRollNote,
    playing: Bool,
    into context: GraphicsContext,
    drawContext: PianoRollDrawContext,
    visibleXRange: ClosedRange<CGFloat>?
) {
    let rect = pianoRollNoteRect(note, drawContext: drawContext)
    guard pianoRollRectIsVisible(rect, in: visibleXRange) else { return }
    let path = Path(roundedRect: rect, cornerRadius: 1)
    let baseColor = playing ? drawContext.playingNoteColor : drawContext.idleNoteColor
    context.fill(path, with: .color(baseColor.opacity(pianoRollNoteOpacity(forVelocity: note.velocity))))
}

func pianoRollEraseNote(
    _ note: PianoRollNote,
    into context: GraphicsContext,
    drawContext: PianoRollDrawContext,
    backgroundColor: Color,
    visibleXRange: ClosedRange<CGFloat>?
) {
    let rect = pianoRollNoteRect(note, drawContext: drawContext).insetBy(dx: -0.5, dy: -0.5)
    guard pianoRollRectIsVisible(rect, in: visibleXRange) else { return }
    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(backgroundColor))
}

func pianoRollDrawCC(
    _ ccEvent: PianoRollCC,
    into context: GraphicsContext,
    drawContext: PianoRollDrawContext,
    visibleXRange: ClosedRange<CGFloat>?
) {
    let startX = drawContext.timelineLeadingInset + (ccEvent.startOffset * drawContext.pixelsPerSecond)
    let width = max(2, ccEvent.duration * drawContext.pixelsPerSecond)
    let laneY = PianoRollView.contentTopInset + (CGFloat(ccEvent.kind.laneIndex) * drawContext.ccLaneHeight)
    let rect = CGRect(x: startX, y: laneY, width: width, height: drawContext.ccLaneHeight)
    guard pianoRollRectIsVisible(rect, in: visibleXRange) else { return }
    context.fill(Path(rect), with: .color(ccEvent.kind.color))
}

private func pianoRollNoteOpacity(forVelocity velocity: UInt8) -> Double {
    let normalized = min(Double(velocity), 100) / 100
    return 0.05 + (normalized * 0.95)
}

private func pianoRollPitchToY(pitch: UInt8, keyHeight: CGFloat) -> CGFloat {
    let safePitch = max(21, min(108, pitch))
    let inverted = 108 - safePitch
    return CGFloat(inverted) * keyHeight
}

func pianoRollIsNotePlaying(_ note: PianoRollNote, currentOffset: TimeInterval) -> Bool {
    currentOffset >= note.startOffset && currentOffset <= (note.startOffset + note.duration)
}
