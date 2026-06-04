//
//  PianoRollViewZoomState.swift
//  MIDI Scribe
//

import SwiftUI

extension PianoRollView {
    func beginPausedZoomCentering(
        debounce: Bool,
        viewportFrameInGlobal: CGRect,
        playheadGlobalX: CGFloat?
    ) {
        beginPausedZoomCentering(
            debounce: debounce,
            anchorX: pausedZoomAnchorX(
                viewportFrameInGlobal: viewportFrameInGlobal,
                playheadGlobalX: playheadGlobalX
            )
        )
    }

    private func beginPausedZoomCentering(
        debounce: Bool,
        anchorX: CGFloat?
    ) {
        guard !isLive, !isTakePlaying else { return }
        let resolvedAnchorX = anchorX ?? lastPausedZoomPlayheadAnchorX
        if !isZoomCentering {
            isZoomCentering = true
            pausedZoomPlayheadAnchorX = resolvedAnchorX
        }
        guard debounce else { return }

        zoomCenteringTask?.cancel()
        zoomCenteringTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                clearPausedZoomCentering()
            }
        }
    }

    func finishPausedZoomCenteringAfterDelay() {
        guard !isLive, !isTakePlaying else { return }
        zoomCenteringTask?.cancel()
        zoomCenteringTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                clearPausedZoomCentering()
            }
        }
    }

    private func clearPausedZoomCentering() {
        isZoomCentering = false
        pausedZoomPlayheadAnchorX = nil
        zoomCenteringTask = nil
    }

    func updatePausedZoomAnchorCache(
        playheadGlobalX: CGFloat?,
        viewportFrameInGlobal: CGRect
    ) {
        guard !isLive, !isTakePlaying, !isZoomCentering else { return }
        if let cachedZoomLevel = lastPausedZoomPlayheadAnchorZoomLevel,
           abs(cachedZoomLevel - zoomLevel) > 0.0001 {
            return
        }
        guard let anchorX = pausedZoomAnchorX(
            viewportFrameInGlobal: viewportFrameInGlobal,
            playheadGlobalX: playheadGlobalX
        ) else { return }
        lastPausedZoomPlayheadAnchorX = anchorX
        lastPausedZoomPlayheadAnchorZoomLevel = zoomLevel
    }

    func handleZoomLevelChange(
        proxy: ScrollViewProxy,
        playOffset: TimeInterval,
        pixelsPerSecond: CGFloat,
        layoutWidth: CGFloat,
        viewportFrameInGlobal: CGRect
    ) {
        if isTakePlaying {
            playbackFollowSuppressedUntil = Date().addingTimeInterval(0.12)
        }
        logScrollbarZoomEvent()
        logZoomChangeDiagnostics(
            playOffset: playOffset,
            pixelsPerSecond: pixelsPerSecond,
            layoutWidth: layoutWidth
        )
        if shouldAnchorDragZoomSelectionStart {
            anchorDragZoomSelectionStart(proxy: proxy)
        } else if shouldCenterPlayheadAfterDragZoom {
            proxy.scrollTo("playhead", anchor: .center)
            shouldCenterPlayheadAfterDragZoom = false
            delayPlaybackCenteringUntilCenter = false
        } else if skipNextPausedZoomCentering {
            skipNextPausedZoomCentering = false
        } else {
            handlePausedZoomLevelChange(
                proxy: proxy,
                playOffset: playOffset,
                pixelsPerSecond: pixelsPerSecond,
                viewportFrameInGlobal: viewportFrameInGlobal
            )
        }
    }

    private func anchorDragZoomSelectionStart(proxy: ScrollViewProxy) {
        proxy.scrollTo("dragZoomSelectionStart", anchor: .leading)
        shouldAnchorDragZoomSelectionStart = false
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("dragZoomSelectionStart", anchor: .leading)
        }
    }

    private func handlePausedZoomLevelChange(
        proxy: ScrollViewProxy,
        playOffset: TimeInterval,
        pixelsPerSecond: CGFloat,
        viewportFrameInGlobal: CGRect
    ) {
        if isTakePlaying {
            scrollPlayheadToZoomAnchor(.center, proxy: proxy)
            return
        }

        let anchorX = pausedZoomPlayheadAnchorX
            ?? pausedZoomAnchorX(
                viewportFrameInGlobal: viewportFrameInGlobal,
                playheadGlobalX: playheadGlobalXForZoomAnchor(
                    knownPlayheadGlobalX: playheadGlobalX,
                    playOffset: playOffset,
                    pixelsPerSecond: pixelsPerSecond,
                    viewportFrameInGlobal: viewportFrameInGlobal
                )
            )
            ?? lastPausedZoomPlayheadAnchorX
        guard let anchorX else {
            beginPausedZoomCentering(debounce: true, anchorX: nil)
            return
        }

        lastPausedZoomPlayheadAnchorX = anchorX
        lastPausedZoomPlayheadAnchorZoomLevel = zoomLevel
        let zoomAnchor = UnitPoint(x: anchorX, y: 0.5)
        beginPausedZoomCentering(debounce: !isExternalZoomInteractionActive, anchorX: anchorX)
        scrollPlayheadToZoomAnchor(zoomAnchor, proxy: proxy)
    }

    private func scrollPlayheadToZoomAnchor(_ zoomAnchor: UnitPoint, proxy: ScrollViewProxy) {
        proxy.scrollTo("playhead", anchor: zoomAnchor)
        Task { @MainActor in
            await Task.yield()
            proxy.scrollTo("playhead", anchor: zoomAnchor)
        }
    }

    private func playheadGlobalXForZoomAnchor(
        knownPlayheadGlobalX: CGFloat?,
        playOffset: TimeInterval,
        pixelsPerSecond: CGFloat,
        viewportFrameInGlobal: CGRect
    ) -> CGFloat? {
        if let knownPlayheadGlobalX,
           knownPlayheadGlobalX >= viewportFrameInGlobal.minX,
           knownPlayheadGlobalX <= viewportFrameInGlobal.maxX {
            return knownPlayheadGlobalX
        }
        let headX = Self.timelineLeadingInset + (playOffset * pixelsPerSecond)
        let fallback = viewportFrameInGlobal.minX + headX
        guard fallback >= viewportFrameInGlobal.minX,
              fallback <= viewportFrameInGlobal.maxX else { return nil }
        return fallback
    }

    private func pausedZoomAnchorX(
        viewportFrameInGlobal: CGRect,
        playheadGlobalX: CGFloat?
    ) -> CGFloat? {
        guard let playheadGlobalX else { return nil }
        guard playheadGlobalX >= viewportFrameInGlobal.minX, playheadGlobalX <= viewportFrameInGlobal.maxX else {
            return nil
        }
        let viewportWidth = viewportFrameInGlobal.width
        guard viewportWidth > 0 else { return nil }
        let normalizedX = (playheadGlobalX - viewportFrameInGlobal.minX) / viewportWidth
        return min(max(0, normalizedX), 1)
    }
}
