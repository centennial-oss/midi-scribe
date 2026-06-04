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
    private static let pendingRebuildThreshold = 256

    private var sortedByStart: [PianoRollNote] = []
    private var intervalTree: IntervalNode?
    private var pendingNotes: [PianoRollNote] = []

    init(notes: [PianoRollNote] = []) {
        sortedByStart = notes.sorted { $0.startOffset < $1.startOffset }
        intervalTree = Self.makeTree(from: sortedByStart, range: 0 ..< sortedByStart.count)
    }

    mutating func insert(_ note: PianoRollNote) {
        let insertionIndex = insertionIndex(for: note.startOffset)
        sortedByStart.insert(note, at: insertionIndex)
        pendingNotes.append(note)
        if pendingNotes.count >= Self.pendingRebuildThreshold {
            rebuildTree()
        }
    }

    func activeNotes(at offset: TimeInterval) -> [PianoRollNote] {
        notes(overlapping: offset ... offset)
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
        return notes(overlapping: visibleStart ... visibleEnd)
    }

    private func notes(overlapping query: ClosedRange<TimeInterval>) -> [PianoRollNote] {
        var result: [PianoRollNote] = []
        intervalTree?.appendOverlapping(query, to: &result)
        for note in pendingNotes where Self.overlaps(note, query) {
            result.append(note)
        }
        return result
    }

    private func insertionIndex(for offset: TimeInterval) -> Int {
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

    private mutating func rebuildTree() {
        intervalTree = Self.makeTree(from: sortedByStart, range: 0 ..< sortedByStart.count)
        pendingNotes.removeAll(keepingCapacity: true)
    }

    private static func makeTree(
        from notes: [PianoRollNote],
        range: Range<Int>
    ) -> IntervalNode? {
        guard !range.isEmpty else { return nil }
        let mid = range.lowerBound + ((range.upperBound - range.lowerBound) / 2)
        return IntervalNode(
            note: notes[mid],
            left: makeTree(from: notes, range: range.lowerBound ..< mid),
            right: makeTree(from: notes, range: (mid + 1) ..< range.upperBound)
        )
    }

    private static func overlaps(_ note: PianoRollNote, _ query: ClosedRange<TimeInterval>) -> Bool {
        note.startOffset <= query.upperBound && note.endOffset >= query.lowerBound
    }

    private final class IntervalNode {
        let note: PianoRollNote
        let left: IntervalNode?
        let right: IntervalNode?
        let maxEndOffset: TimeInterval

        init(note: PianoRollNote, left: IntervalNode?, right: IntervalNode?) {
            self.note = note
            self.left = left
            self.right = right
            maxEndOffset = max(
                note.endOffset,
                left?.maxEndOffset ?? -.infinity,
                right?.maxEndOffset ?? -.infinity
            )
        }

        func appendOverlapping(_ query: ClosedRange<TimeInterval>, to result: inout [PianoRollNote]) {
            if let left, left.maxEndOffset >= query.lowerBound {
                left.appendOverlapping(query, to: &result)
            }
            if PianoRollActiveNoteIndex.overlaps(note, query) {
                result.append(note)
            }
            if note.startOffset <= query.upperBound {
                right?.appendOverlapping(query, to: &result)
            }
        }
    }
}

private extension PianoRollNote {
    var endOffset: TimeInterval {
        startOffset + duration
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
