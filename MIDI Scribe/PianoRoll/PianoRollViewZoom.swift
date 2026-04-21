//
//  PianoRollViewZoom.swift
//  MIDI Scribe
//

import SwiftUI

extension PianoRollView {
    func handlePinchZoomChanged(_ value: CGFloat) {
        guard !isLive else { return }
        if !isPinchZooming {
            isPinchZooming = true
            pinchStartZoomLevel = zoomLevel
            beginPausedZoomCentering(debounce: false)
        }
        let baseZoomLevel = pinchStartZoomLevel ?? zoomLevel
        let delta = (value - 1.0) * 0.5
        zoomLevel = max(0.0, min(1.0, baseZoomLevel + delta))
        currentMagnification = 1.0
    }

    func handlePinchZoomEnded(_: CGFloat) {
        guard !isLive else { return }
        currentMagnification = 1.0
        pinchStartZoomLevel = nil
        isPinchZooming = false
        beginPausedZoomCentering(debounce: true)
    }
}
