//
//  PianoRollView.swift
//  MIDI Scribe
//

import SwiftUI

struct PianoRollView: View {
    private static let rollCornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme

    /// Dark charcoal in light mode so lime note bars pop; solid black in dark mode.
    private var rollBackground: Color {
        switch colorScheme {
        case .light:
            return Color(red: 0.14, green: 0.14, blue: 0.15)
        case .dark:
            return .black
        @unknown default:
            return Color(red: 0.14, green: 0.14, blue: 0.15)
        }
    }

    /// Playhead line + scrub handle: light on dark roll in both modes.
    private var playheadChrome: Color {
        colorScheme == .dark ? Color.white : Color(white: 0.92)
    }

    let take: RecordedTake
    @ObservedObject var viewModel: MIDILiveNoteViewModel
    @Binding var zoomLevel: CGFloat
    /// When true, the piano roll is rendering a take that is actively being
    /// recorded. In this mode the playhead tracks the live tail of the
    /// take, the scrub circle is hidden, and the scroll view auto-follows
    /// the tail when the user has zoomed in past the fit-to-width minimum.
    var isLive: Bool = false

    @State var notes: [PianoRollNote] = []
    @State var ccEvents: [PianoRollCC] = []
    /// Cursor into `take.events` used for incremental updates in live
    /// mode so we don't re-scan the full events array on every new note
    /// (which was O(n) per event → O(n²) over the take and caused
    /// speaker echo lag that got worse as the take got longer).
    @State var liveEventsProcessedCount: Int = 0
    /// In-flight notes keyed by pitch; appended to `notes` once closed.
    @State var liveActiveNotes: [UInt8: PianoRollNote] = [:]
    /// In-flight CC regions keyed by cc number; appended to `ccEvents` once closed.
    @State var liveActiveCCs: [UInt8: PianoRollCC] = [:]

    @State private var dragStartOffset: TimeInterval?
    @State private var dragIntersectedNotes: Set<UUID> = []
    /// Local scrub offset used when the playback engine has no active take
    /// for this piano roll (e.g. before the user has ever pressed Play).
    /// Without this, the engine's `currentPlaybackTime` would stay at 0
    /// during a drag because `currentTakeID` hasn't been assigned yet.
    @State private var localScrubOffset: TimeInterval?

    /// To smoothly zoom on iOS:
    @State private var currentMagnification: CGFloat = 1.0
    @State private var lastScrollUpdate: TimeInterval = -1
    @State private var isZoomCentering = false
    @State private var isPinchZooming = false
    @State private var zoomCenteringTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.animation(paused: !shouldAnimatePianoRoll)) { context in
            GeometryReader { geo in
                // iPadOS often reports 0×0 on the first layout pass; using that for scale yields 0px-wide
                // content so the Canvas stays blank until something (e.g. zoom) forces a relayout.
                let layoutWidth = max(geo.size.width, 1)
                let layoutHeight = max(geo.size.height, 1)
                let availableHeight = layoutHeight - 12 // Leave 12px for the scrubber head at the top
                let keyHeight = max(3.15, availableHeight / 88.0)
                let rollHeight = keyHeight * 88.0
                let viewHeight = rollHeight + 12

                let secondsLength = max(0.01, take.duration)
                let zoomInterpolation = max(0, min(1, zoomLevel + (currentMagnification - 1.0) * 0.5))
                let minPxPerSec = layoutWidth / secondsLength
                let maxPxPerSec = layoutWidth / 5.0

                let calculatedPxPerSec = minPxPerSec + zoomInterpolation * (maxPxPerSec - minPxPerSec)
                let pixelsPerSecond = secondsLength < 5.0 ? minPxPerSec : max(minPxPerSec, calculatedPxPerSec)

                let rollWidth = max(layoutWidth, secondsLength * pixelsPerSecond)

                let playOffset = currentPlaybackOffset

                ScrollView(.horizontal) {
                    ScrollViewReader { proxy in
                        ZStack(alignment: .topLeading) {
                            rollBackground

                            // Render all notes + CCs in a single Canvas to
                            // avoid SwiftUI diffing thousands of Rectangle
                            // views on every new event (which caused
                            // live-recording lag after ~1500 notes).
                            Canvas { context, _ in
                                drawNotesAndCCs(
                                    into: context,
                                    keyHeight: keyHeight,
                                    pixelsPerSecond: pixelsPerSecond,
                                    playOffset: playOffset
                                )
                            }
                            .frame(width: rollWidth, height: viewHeight)
                            .allowsHitTesting(false)

                            let headX = playOffset * pixelsPerSecond

                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                    .frame(width: headX)
                                Color.clear
                                    .frame(width: 1, height: viewHeight)
                                    .id("playhead")
                                Spacer(minLength: 0)
                            }

                            Rectangle()
                                .fill(playheadChrome)
                                .frame(width: 2, height: rollHeight)
                                .padding(.top, 12)
                                .offset(x: headX)

                            if !isTakePlaying && !isLive {
                                Circle()
                                    .fill(playheadChrome)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                                    .offset(x: headX - 11)
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                            .onChanged { value in
                                                handleScrubDrag(
                                                    value: value,
                                                    pixelsPerSecond: pixelsPerSecond,
                                                    proxy: proxy
                                                )
                                            }
                                            .onEnded { _ in
                                                handleScrubEnd()
                                            }
                                    )
                            }
                        }
                        .frame(width: rollWidth, height: viewHeight, alignment: .topLeading)
                        .transaction { $0.animation = nil }
                        .onChange(of: context.date) { _, _ in
                            if isTakePlaying || shouldCenterPausedPlayheadDuringZoom {
                                proxy.scrollTo("playhead", anchor: .center)
                            } else if isLive && rollWidth > layoutWidth {
                                proxy.scrollTo("playhead", anchor: .trailing)
                            }
                        }
                        .onChange(of: zoomLevel) { _, _ in
                            beginPausedZoomCentering(debounce: true)
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    if !isPinchZooming {
                                        isPinchZooming = true
                                        beginPausedZoomCentering(debounce: false)
                                    }
                                    currentMagnification = value
                                }
                                .onEnded { value in
                                    let delta = (value - 1.0) * 0.5
                                    zoomLevel = max(0.0, min(1.0, zoomLevel + delta))
                                    currentMagnification = 1.0
                                    isPinchZooming = false
                                    beginPausedZoomCentering(debounce: true)
                                }
                        )
                    }
                }
                .frame(height: viewHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.rollCornerRadius, style: .continuous))

                // Tooltips layer intentionally omitted: previously a
                // per-note hover .help() was rendered here, but the
                // resulting ForEach over thousands of notes was a
                // significant diffing cost during live recording and
                // hover tooltips aren't usable at that density anyway.
            }
        }
        .overlay(PianoRollScrollWheelZoom(zoomLevel: $zoomLevel))
        .onAppear {
            computeNotes()
            liveEventsProcessedCount = take.events.count
        }
        /// Completed takes: first frame can lay out before `GeometryReader` has a stable size; yield once
        /// so `computeNotes()`/Canvas see non-zero scale (matches “zoom fixes it” without user action).
        .task(id: take.id) {
            guard !isLive else { return }
            await Task.yield()
            computeNotes()
        }
        .onChange(of: take.id) { _, _ in
            resetScrubState()
            resetLiveCursors()
            computeNotes()
            liveEventsProcessedCount = take.events.count
        }
        .onChange(of: take.events.count) { _, newCount in
            if isLive {
                ingestNewLiveEvents(upTo: newCount)
            }
        }
    }

    private var isTakePlaying: Bool {
        viewModel.isPlaying(takeID: take.id)
    }

    private var shouldAnimatePianoRoll: Bool {
        isTakePlaying || dragStartOffset != nil || isLive || isZoomCentering
    }

    private var shouldCenterPausedPlayheadDuringZoom: Bool {
        !isLive && !isTakePlaying && isZoomCentering
    }

    private func resetScrubState() {
        dragStartOffset = nil
        dragIntersectedNotes.removeAll()
        localScrubOffset = nil
        viewModel.playbackEngine.stopScrubbingNotes()
    }

    private func beginPausedZoomCentering(debounce: Bool) {
        guard !isLive, !isTakePlaying else { return }
        if !isZoomCentering {
            isZoomCentering = true
        }
        guard debounce else { return }

        zoomCenteringTask?.cancel()
        zoomCenteringTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !isPinchZooming else { return }
                isZoomCentering = false
                zoomCenteringTask = nil
            }
        }
    }
}

extension PianoRollView {
    private var currentPlaybackOffset: TimeInterval {
        if isLive {
            return take.duration
        }
        if viewModel.playbackEngine.currentTakeID == take.id {
            return viewModel.playbackEngine.currentPlaybackTime
        }
        return localScrubOffset ?? 0
    }

    private func isNotePlaying(_ note: PianoRollNote, currentOffset: TimeInterval) -> Bool {
        return currentOffset >= note.startOffset && currentOffset <= (note.startOffset + note.duration)
    }

    private func pitchToY(pitch: UInt8, keyHeight: CGFloat) -> CGFloat {
        // 88 keys: A0 is pitch 21, C8 is pitch 108.
        let safePitch = max(21, min(108, pitch))
        let inverted = 108 - safePitch
        return CGFloat(inverted) * keyHeight
    }

    private func pitchToName(pitch: UInt8) -> String {
        let notes = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "G♯", "A", "B♭", "B"]
        let octave = Int(pitch) / 12 - 1
        let noteIndex = Int(pitch) % 12
        return "\(notes[noteIndex])\(octave)"
    }

    private func handleScrubDrag(value: DragGesture.Value, pixelsPerSecond: CGFloat, proxy: ScrollViewProxy) {
        if dragStartOffset == nil {
            dragStartOffset = currentPlaybackOffset
        }
        guard let start = dragStartOffset else { return }

        let deltaOffset = TimeInterval(value.translation.width / pixelsPerSecond)
        let newOffset = max(0, start + deltaOffset)

        viewModel.playbackEngine.updatePausedOffset(to: newOffset, takeID: take.id)
        if viewModel.playbackEngine.currentTakeID != take.id {
            localScrubOffset = newOffset
        }
        // Auto-scroll handled by onChange of playhead

        var currentlyIntersected: Set<UUID> = []
        for note in notes {
            if newOffset >= note.startOffset && newOffset <= (note.startOffset + note.duration) {
                currentlyIntersected.insert(note.id)
            }
        }

        let newlyEntered = currentlyIntersected.subtracting(dragIntersectedNotes)
        let newlyExited = dragIntersectedNotes.subtracting(currentlyIntersected)

        for noteID in newlyEntered {
            if let note = notes.first(where: { $0.id == noteID }) {
                let status = UInt8(0x90 | ((note.channel - 1) & 0x0F))
                let event = RecordedMIDIEvent(
                    receivedAt: Date(),
                    offsetFromTakeStart: 0,
                    kind: .noteOn,
                    channel: note.channel,
                    status: status,
                    data1: note.pitch,
                    data2: note.velocity
                )
                viewModel.playbackEngine.playScrubEvent(event, target: viewModel.selectedPlaybackTarget)
            }
        }

        for noteID in newlyExited {
            if let note = notes.first(where: { $0.id == noteID }) {
                let status = UInt8(0x80 | ((note.channel - 1) & 0x0F))
                let event = RecordedMIDIEvent(
                    receivedAt: Date(),
                    offsetFromTakeStart: 0,
                    kind: .noteOff,
                    channel: note.channel,
                    status: status,
                    data1: note.pitch,
                    data2: 0
                )
                viewModel.playbackEngine.playScrubEvent(event, target: viewModel.selectedPlaybackTarget)
            }
        }

        dragIntersectedNotes = currentlyIntersected
    }

    private func handleScrubEnd() {
        dragStartOffset = nil
        for noteID in dragIntersectedNotes {
            if let note = notes.first(where: { $0.id == noteID }) {
                let status = UInt8(0x80 | ((note.channel - 1) & 0x0F))
                let event = RecordedMIDIEvent(
                    receivedAt: Date(),
                    offsetFromTakeStart: 0,
                    kind: .noteOff,
                    channel: note.channel,
                    status: status,
                    data1: note.pitch,
                    data2: 0
                )
                viewModel.playbackEngine.playScrubEvent(event, target: viewModel.selectedPlaybackTarget)
            }
        }
        dragIntersectedNotes.removeAll()
    }

    func computeNotes() {
        computeNoteEvents()
        computeCCs()
    }

    func resetLiveCursors() {
        liveEventsProcessedCount = 0
        liveActiveNotes.removeAll(keepingCapacity: true)
        liveActiveCCs.removeAll(keepingCapacity: true)
    }
}
