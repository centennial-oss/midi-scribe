//
//  PianoRollView.swift
//  MIDI Scribe
//

import SwiftUI

struct PianoRollView: View {
    private static let rollCornerRadius: CGFloat = 8
    static let maxConcurrentScrubAuditionNotes = 24
    static let timelineLeadingInset: CGFloat = 12
    /// Nudges the paused scrub knob down so the rounded clip does not crop its top.
    static let playheadKnobVerticalOffset: CGFloat = 10

    @Environment(\.colorScheme) private var colorScheme

    /// Dark charcoal in light mode so lime note bars pop; solid black in dark mode.
    private var rollBackground: Color {
        colorScheme == .dark ? Color.black : Color(white: 0.975)
    }

    /// Playhead line + scrub handle: light on dark roll in both modes.
    private var playheadChrome: Color {
        colorScheme == .dark ? Color.white : Color(white: 0.3)
    }

    /// Lime note bars on the roll when not under the playhead.
    private var noteBarIdleColor: Color {
        colorScheme == .dark ? Color(red: 0.6, green: 1.0, blue: 0.2) : Color(red: 0.1, green: 0.5, blue: 0.05)
    }

    /// Pink / fuchsia note bars while the playhead is over the note.
    private var noteBarPlayingColor: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.2, blue: 0.8) : Color(red: 0.9, green: 0.1, blue: 0.7)
    }

    /// Stroke around the clipped roll (`rollCornerRadius`).
    private var rollBorderColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 0.3, green: 0.3, blue: 0.3)
    }

    let take: RecordedTake
    @ObservedObject var viewModel: MIDILiveNoteViewModel
    @Binding var zoomLevel: CGFloat
    var scrollToStartRequestID = 0
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
    /// Event IDs skipped due to invalid MIDI bounds. Used as a stable,
    /// deduplicated counter so repeated redraws do not inflate the value.
    @State var ignoredMalformedEventIDs: Set<UUID> = []

    @State var dragStartOffset: TimeInterval?
    @State var dragIntersectedNotes: Set<UUID> = []
    @State var lastScrubAuditionUptime: TimeInterval?
    @State var scrubAuditionDiagnostics = ScrubAuditionDiagnostics()
    @State var lastPlaybackModelDiagnosticUptime: TimeInterval?
    @State var scrubEdgeAutoScrollDirection: CGFloat = 0
    @State var scrubLastDragTranslationWidth: CGFloat?
    /// Local scrub offset used when the playback engine has no active take
    /// for this piano roll (e.g. before the user has ever pressed Play).
    /// Without this, the engine's `currentPlaybackTime` would stay at 0
    /// during a drag because `currentTakeID` hasn't been assigned yet.
    @State var localScrubOffset: TimeInterval?; @State var isScrubHandleHovered = false

    /// To smoothly zoom on iOS:
    @State private var currentMagnification: CGFloat = 1.0
    @State private var isZoomCentering = false
    @State private var isPinchZooming = false
    @State private var zoomCenteringTask: Task<Void, Never>?
    /// iOS can deliver an initial 0x0 layout pass for this view. Prime once
    /// when we observe a usable size to force a deterministic first render.
    @State private var didPrimeInitialLayout = false
    @State private var layoutPrimeID = 0

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
                let timelineLayoutWidth = max(layoutWidth - Self.timelineLeadingInset, 1)
                let minPxPerSec = timelineLayoutWidth / secondsLength
                let maxPxPerSec = timelineLayoutWidth / 5.0

                let calculatedPxPerSec = minPxPerSec + zoomInterpolation * (maxPxPerSec - minPxPerSec)
                let pixelsPerSecond = secondsLength < 5.0 ? minPxPerSec : max(minPxPerSec, calculatedPxPerSec)

                let rollWidth = max(layoutWidth, Self.timelineLeadingInset + (secondsLength * pixelsPerSecond))

                let playOffset = currentPlaybackOffset
                let playheadColor = (dragStartOffset != nil || isScrubHandleHovered)
                    ? Color.accentColor
                    : playheadChrome

                ScrollView(.horizontal) {
                    ScrollViewReader { proxy in
                        ZStack(alignment: .topLeading) {
                            rollBackground
                            Color.clear
                                .frame(width: 1, height: viewHeight)
                                .id("playheadStart")

                            // Render all notes + CCs in a single Canvas to
                            // avoid SwiftUI diffing thousands of Rectangle
                            // views on every new event (which caused
                            // live-recording lag after ~1500 notes).
                            Canvas { context, _ in
                                drawNotesAndCCs(
                                    into: context,
                                    keyHeight: keyHeight,
                                    pixelsPerSecond: pixelsPerSecond,
                                    playOffset: playOffset,
                                    idleNoteColor: noteBarIdleColor,
                                    playingNoteColor: noteBarPlayingColor
                                )
                            }
                            .frame(width: rollWidth, height: viewHeight)
                            .allowsHitTesting(false)

                            let headX = Self.timelineLeadingInset + (playOffset * pixelsPerSecond)

                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                    .frame(width: headX)
                                Color.clear
                                    .frame(width: 1, height: viewHeight)
                                    .id("playhead")
                                Spacer(minLength: 0)
                            }

                            Rectangle()
                                .fill(playheadColor)
                                .frame(width: 2, height: rollHeight)
                                .padding(.top, 12)
                                .offset(x: headX)

                            if !isTakePlaying && !isLive {
                                Circle()
                                    .fill(playheadColor)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Circle())
                                    .offset(x: headX - 11, y: Self.playheadKnobVerticalOffset)
                                    .onHover { isHovering in
                                        isScrubHandleHovered = isHovering
                                    }
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                            .onChanged { value in
                                                handleScrubDrag(
                                                    value: value,
                                                    pixelsPerSecond: pixelsPerSecond,
                                                    proxy: proxy,
                                                    autoScrollContext: ScrubDragAutoScrollContext(
                                                        rollWidth: rollWidth,
                                                        layoutWidth: layoutWidth,
                                                        viewportFrameInGlobal: geo.frame(in: .global)
                                                    )
                                                )
                                            }
                                            .onEnded { _ in
                                                handleScrubEnd()
                                            }
                                    )
                            }
                        }
                        .frame(width: rollWidth, height: viewHeight, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .transaction { $0.animation = nil }
                        .onChange(of: context.date) { _, _ in
                            if isTakePlaying || shouldCenterPausedPlayheadDuringZoom {
                                proxy.scrollTo("playhead", anchor: .center)
                            } else if isLive && rollWidth > layoutWidth {
                                proxy.scrollTo("playhead", anchor: .trailing)
                            }
                            if dragStartOffset != nil {
                                continueScrubAutoScrollIfNeeded(
                                    proxy: proxy,
                                    pixelsPerSecond: pixelsPerSecond,
                                    autoScrollContext: ScrubDragAutoScrollContext(
                                        rollWidth: rollWidth,
                                        layoutWidth: layoutWidth,
                                        viewportFrameInGlobal: geo.frame(in: .global)
                                    )
                                )
                            }
                            logPlaybackModelDiagnosticsIfNeeded(at: playOffset)
                        }
                        .onChange(of: zoomLevel) { _, _ in
                            beginPausedZoomCentering(debounce: true)
                        }
                        .onChange(of: scrollToStartRequestID) { _, _ in
                            guard !isLive else { return }
                            proxy.scrollTo("playheadStart", anchor: .leading)
                        }
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    guard !isLive else { return }
                                    if !isPinchZooming {
                                        isPinchZooming = true
                                        beginPausedZoomCentering(debounce: false)
                                    }
                                    currentMagnification = value
                                }
                                .onEnded { value in
                                    guard !isLive else { return }
                                    let delta = (value - 1.0) * 0.5
                                    zoomLevel = max(0.0, min(1.0, zoomLevel + delta))
                                    currentMagnification = 1.0
                                    isPinchZooming = false
                                    beginPausedZoomCentering(debounce: true)
                                }
                        )
                        .simultaneousGesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    handleRollTap(
                                        at: value.location,
                                        rollWidth: rollWidth,
                                        pixelsPerSecond: pixelsPerSecond,
                                        viewHeight: viewHeight,
                                        playOffset: playOffset
                                    )
                                },
                            including: isLive ? .subviews : .all
                        )
                    }
                }
                .id(layoutPrimeID)
                .frame(height: viewHeight)
                .clipShape(RoundedRectangle(cornerRadius: Self.rollCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.rollCornerRadius, style: .continuous)
                        .stroke(rollBorderColor, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if !ignoredMalformedEventIDs.isEmpty {
                        Text("Ignored malformed MIDI events: \(ignoredMalformedEventIDs.count)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 8)
                            .padding(.leading, 8)
                    }
                }
                .onAppear {
                    ignoredMalformedEventIDs.removeAll(keepingCapacity: true)
                    primeInitialLayoutIfNeeded(size: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    primeInitialLayoutIfNeeded(size: newSize)
                }

                // Tooltips layer intentionally omitted: previously a
                // per-note hover .help() was rendered here, but the
                // resulting ForEach over thousands of notes was a
                // significant diffing cost during live recording and
                // hover tooltips aren't usable at that density anyway.
            }
        }
        .overlay {
            if !isLive {
                PianoRollScrollWheelZoom(zoomLevel: $zoomLevel)
            }
        }
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
            ignoredMalformedEventIDs.removeAll(keepingCapacity: true)
            computeNotes()
            liveEventsProcessedCount = take.events.count
        }
        .onChange(of: take.events.count) { _, newCount in
            if isLive {
                ingestNewLiveEvents(upTo: newCount)
            }
        }
    }

}

extension PianoRollView {
    var isTakePlaying: Bool {
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
        lastScrubAuditionUptime = nil
        scrubAuditionDiagnostics = ScrubAuditionDiagnostics()
        lastPlaybackModelDiagnosticUptime = nil
        localScrubOffset = nil
        viewModel.playbackEngine.stopScrubbingNotes()
        scrubEdgeAutoScrollDirection = 0
        scrubLastDragTranslationWidth = nil
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

    private func primeInitialLayoutIfNeeded(size: CGSize) {
        guard !didPrimeInitialLayout else { return }
        guard size.width > 1, size.height > 1 else { return }
        didPrimeInitialLayout = true
        layoutPrimeID += 1
    }

    var currentPlaybackOffset: TimeInterval {
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
