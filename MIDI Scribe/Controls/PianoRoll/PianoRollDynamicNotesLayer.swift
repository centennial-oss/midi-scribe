//
//  PianoRollDynamicNotesLayer.swift
//  MIDI Scribe
//

import SwiftUI

struct PianoRollDynamicRenderContext {
    let drawContext: PianoRollDrawContext
    let playOffset: TimeInterval
    let activeNotes: [PianoRollNote]
    let visibleXRange: ClosedRange<CGFloat>?
    let backgroundColor: Color
}

struct PianoRollActiveNoteIndex {
    private var sortedByStart: [PianoRollNote] = []
    private var maxDuration: TimeInterval = 0

    init(notes: [PianoRollNote] = []) {
        sortedByStart = notes.sorted { $0.startOffset < $1.startOffset }
        maxDuration = notes.map(\.duration).max() ?? 0
    }

    func activeNotes(at offset: TimeInterval) -> [PianoRollNote] {
        guard !sortedByStart.isEmpty else { return [] }
        let upperBound = firstStartIndex(after: offset)
        guard upperBound > 0 else { return [] }

        let earliestPossibleStart = offset - maxDuration
        var active: [PianoRollNote] = []
        var index = upperBound - 1
        while index >= 0 {
            let note = sortedByStart[index]
            if note.startOffset < earliestPossibleStart { break }
            if offset <= note.startOffset + note.duration {
                active.append(note)
            }
            if index == 0 { break }
            index -= 1
        }
        return active
    }

    func notes(
        intersecting visibleXRange: ClosedRange<CGFloat>?,
        drawContext: PianoRollDrawContext
    ) -> [PianoRollNote] {
        guard let visibleXRange else { return sortedByStart }
        guard drawContext.pixelsPerSecond > 0 else { return [] }

        let visibleStart = TimeInterval(
            max(0, (visibleXRange.lowerBound - drawContext.timelineLeadingInset) / drawContext.pixelsPerSecond)
        )
        let visibleEnd = TimeInterval(
            max(0, (visibleXRange.upperBound - drawContext.timelineLeadingInset) / drawContext.pixelsPerSecond)
        )
        let upperBound = firstStartIndex(after: visibleEnd)
        guard upperBound > 0 else { return [] }

        let earliestPossibleStart = visibleStart - maxDuration
        var visible: [PianoRollNote] = []
        var index = upperBound - 1
        while index >= 0 {
            let note = sortedByStart[index]
            if note.startOffset < earliestPossibleStart { break }
            if note.startOffset + note.duration >= visibleStart {
                visible.append(note)
            }
            if index == 0 { break }
            index -= 1
        }
        return visible
    }

    private func firstStartIndex(after offset: TimeInterval) -> Int {
        var low = 0
        var high = sortedByStart.count
        while low < high {
            let mid = (low + high) / 2
            if sortedByStart[mid].startOffset <= offset {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

struct PianoRollDynamicNotesLayer: View, Equatable {
    let notesToken: Int
    let playOffset: TimeInterval
    let activeNoteIndex: PianoRollActiveNoteIndex
    let drawContext: PianoRollDrawContext
    let visibleXRange: ClosedRange<CGFloat>?
    let rollWidth: CGFloat
    let viewHeight: CGFloat
    let backgroundColor: Color

    static func == (lhs: PianoRollDynamicNotesLayer, rhs: PianoRollDynamicNotesLayer) -> Bool {
        lhs.notesToken == rhs.notesToken
            && lhs.playOffset == rhs.playOffset
            && lhs.rollWidth == rhs.rollWidth
            && lhs.viewHeight == rhs.viewHeight
            && lhs.visibleXRange == rhs.visibleXRange
            && lhs.drawContext == rhs.drawContext
    }

    var body: some View {
        Canvas { context, _ in
            for note in activeNoteIndex.activeNotes(at: playOffset) {
                pianoRollEraseNote(
                    note, into: context, drawContext: drawContext,
                    backgroundColor: backgroundColor,
                    visibleXRange: visibleXRange
                )
                pianoRollDrawNote(
                    note,
                    playing: true,
                    into: context,
                    drawContext: drawContext,
                    visibleXRange: visibleXRange
                )
            }
        }
        .frame(width: rollWidth, height: viewHeight)
        .allowsHitTesting(false)
    }
}
