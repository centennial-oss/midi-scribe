//
//  PianoRollView+State.swift
//  MIDI Scribe
//

import SwiftUI

struct PianoRollTimelineTickContext {
    let rollWidth: CGFloat
    let layoutWidth: CGFloat
    let pixelsPerSecond: CGFloat
    let viewportFrameInGlobal: CGRect
    let playOffset: TimeInterval
}

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
        guard let playbackCenteringAnimationEndsAt else { return false }
        let shouldFollow = date >= playbackCenteringAnimationEndsAt
        #if DEBUG
        if !shouldFollow {
            NSLog(
                "[PianoRollCentering] defer-follow now=%.3f until=%.3f remaining=%.3f",
                date.timeIntervalSinceReferenceDate,
                playbackCenteringAnimationEndsAt.timeIntervalSinceReferenceDate,
                playbackCenteringAnimationEndsAt.timeIntervalSince(date)
            )
        }
        #endif
        return shouldFollow
    }

    func beginPlaybackCenteringAnimation(
        proxy: ScrollViewProxy,
        layoutWidth: CGFloat,
        pixelsPerSecond: CGFloat,
        viewportFrameInGlobal: CGRect,
        playheadGlobalX: CGFloat?
    ) {
        guard !isLive else { return }
        let decision = playbackCenteringDecision(
            viewportFrameInGlobal: viewportFrameInGlobal,
            playheadGlobalX: playheadGlobalX
        )
        let viewportMidX = viewportFrameInGlobal.midX
        let shouldDelayCentering = decision.shouldDelayCentering
        #if DEBUG
        NSLog(
            "[PianoRollCentering] begin isPlaying=%@ delayFlag=%@ contains=%@ playX=%.2f midX=%.2f " +
                "layoutWidth=%.2f pxPerSec=%.4f playOffset=%.4f",
            isTakePlaying ? "true" : "false",
            shouldDelayCentering ? "true" : "false",
            decision.viewportContainsPlayhead ? "true" : "false",
            playheadGlobalX ?? -1,
            viewportMidX,
            layoutWidth,
            pixelsPerSecond,
            currentPlaybackOffset
        )
        #endif
        if shouldDelayCentering, pixelsPerSecond > 0 {
            let centerDistancePixels = max(0, viewportMidX - (playheadGlobalX ?? viewportMidX))
            let secondsUntilCenter = TimeInterval(centerDistancePixels / pixelsPerSecond)
            playbackCenteringAnimationEndsAt = Date().addingTimeInterval(secondsUntilCenter)
            delayPlaybackCenteringUntilCenter = false
            #if DEBUG
            NSLog(
                "[PianoRollCentering] delayed-center centerDistancePx=%.2f secondsUntilCenter=%.3f",
                centerDistancePixels,
                secondsUntilCenter
            )
            #endif
            return
        }
        let duration: TimeInterval = 0.4
        playbackCenteringAnimationEndsAt = Date().addingTimeInterval(duration)
        #if DEBUG
        NSLog("[PianoRollCentering] immediate-center duration=%.3f", duration)
        NSLog("[PianoRollScrollTo] reason=play-start-immediate-center target=playhead anchor=center")
        #endif
        withAnimation(.easeOut(duration: duration)) {
            proxy.scrollTo("playhead", anchor: .center)
        }
    }

    private func playbackCenteringDecision(
        viewportFrameInGlobal: CGRect,
        playheadGlobalX: CGFloat?
    ) -> (shouldDelayCentering: Bool, viewportContainsPlayhead: Bool) {
        let viewportContainsPlayhead: Bool
        if let playheadGlobalX {
            viewportContainsPlayhead =
                playheadGlobalX >= viewportFrameInGlobal.minX && playheadGlobalX <= viewportFrameInGlobal.maxX
        } else {
            viewportContainsPlayhead = false
        }
        let shouldDelayCentering: Bool
        if let playheadGlobalX {
            shouldDelayCentering = viewportContainsPlayhead && playheadGlobalX < viewportFrameInGlobal.midX
        } else {
            shouldDelayCentering = delayPlaybackCenteringUntilCenter
        }
        return (shouldDelayCentering, viewportContainsPlayhead)
    }

    func handleTimelineTick(
        at date: Date,
        proxy: ScrollViewProxy,
        context: PianoRollTimelineTickContext
    ) {
        if shouldFollowPlayingPlayhead(at: date) || shouldCenterPausedPlayheadDuringZoom {
            #if DEBUG
            NSLog("[PianoRollScrollTo] reason=timeline-follow target=playhead anchor=center")
            #endif
            proxy.scrollTo("playhead", anchor: .center)
        } else if isLive && context.rollWidth > context.layoutWidth {
            #if DEBUG
            NSLog("[PianoRollScrollTo] reason=timeline-live-trailing target=playhead anchor=trailing")
            #endif
            proxy.scrollTo("playhead", anchor: .trailing)
        }
        if dragStartOffset != nil {
            continueScrubAutoScrollIfNeeded(
                proxy: proxy,
                pixelsPerSecond: context.pixelsPerSecond,
                autoScrollContext: ScrubDragAutoScrollContext(
                    rollWidth: context.rollWidth,
                    layoutWidth: context.layoutWidth,
                    viewportFrameInGlobal: context.viewportFrameInGlobal
                )
            )
        }
        logPlaybackModelDiagnosticsIfNeeded(at: context.playOffset)
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
