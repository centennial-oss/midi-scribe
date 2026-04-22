//
//  PianoRollView+State.swift
//  MIDI Scribe
//

import SwiftUI

extension PianoRollView {
    func bottomScrollbarInset(for _: CGFloat) -> CGFloat {
        0
    }

    func makeDrawContext(
        keyHeight: CGFloat,
        pixelsPerSecond: CGFloat,
        playOffset: TimeInterval
    ) -> PianoRollDrawContext {
        PianoRollDrawContext(
            keyHeight: keyHeight,
            noteHeight: max(1, keyHeight - 1),
            ccLaneHeight: max(2, max(4, keyHeight) / 2),
            pixelsPerSecond: pixelsPerSecond,
            timelineLeadingInset: Self.timelineLeadingInset,
            playOffset: playOffset,
            idleNoteColor: noteBarIdleColor,
            playingNoteColor: noteBarPlayingColor
        )
    }

    var isTakePlaying: Bool {
        viewModel.isPlaying(takeID: take.id)
    }

    var shouldAnimatePianoRoll: Bool {
        isTakePlaying || dragStartOffset != nil || isLive || isZoomCentering
    }

    var shouldCenterPausedPlayheadDuringZoom: Bool {
        !isLive && !isTakePlaying && isZoomCentering
    }

    func shouldFollowPlayingPlayhead(at date: Date) -> Bool {
        guard isTakePlaying else { return false }
        guard let playbackCenteringAnimationEndsAt else { return true }
        return date >= playbackCenteringAnimationEndsAt
    }

    func beginPlaybackCenteringAnimation(proxy: ScrollViewProxy) {
        guard !isLive else { return }
        let duration: TimeInterval = 0.4
        playbackCenteringAnimationEndsAt = Date().addingTimeInterval(duration)
        withAnimation(.easeOut(duration: duration)) {
            proxy.scrollTo("playhead", anchor: .center)
        }
    }

    func resetScrubState() {
        dragStartOffset = nil
        dragIntersectedNotes.removeAll()
        lastScrubAuditionUptime = nil
        scrubAuditionDiagnostics = ScrubAuditionDiagnostics()
        lastPlaybackModelDiagnosticUptime = nil
        localScrubOffset = nil
        dragZoomStartLocation = nil
        dragZoomCurrentLocation = nil
        shouldCenterPlayheadAfterDragZoom = false
        shouldAnchorPlayheadLeadingAfterDragZoom = false
        viewModel.playbackEngine.stopScrubbingNotes()
        scrubEdgeAutoScrollDirection = 0
        scrubLastDragTranslationWidth = nil
        playbackCenteringAnimationEndsAt = nil
    }

    func beginPausedZoomCentering(debounce: Bool) {
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

    func primeInitialLayoutIfNeeded(size: CGSize) {
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
