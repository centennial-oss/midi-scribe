//
//  ContentViewZoomReset.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func adjustPianoRollZoom(by delta: CGFloat) {
        let currentSliderValue = sliderValue(forPianoRollZoomLevel: pianoRollZoomLevel)
        let nextSliderValue = max(0.0, min(1.0, currentSliderValue + delta))
        pianoRollZoomLevel = pianoRollZoomLevel(forSliderValue: nextSliderValue)
    }

    func resetPianoRollZoom() {
        pianoRollZoomLevel = 0.0
    }

    func handleTakeInProgressChangeForZoomReset(wasInProgress: Bool, isInProgress: Bool) {
        guard wasInProgress, !isInProgress else { return }
        awaitingCompletedTakeZoomReset = true
        DispatchQueue.main.async {
            guard awaitingCompletedTakeZoomReset else { return }
            if viewModel.selectedSidebarItem == .currentTake {
                awaitingCompletedTakeZoomReset = false
            }
        }
    }

    func applyCompletedTakeZoomResetIfNeeded() {
        guard awaitingCompletedTakeZoomReset,
              let completedID = viewModel.lastCompletedTake?.id else { return }
        switch viewModel.selectedSidebarItem {
        case .recentTake(completedID), .starredTake(completedID):
            awaitingCompletedTakeZoomReset = false
            resetPianoRollZoom()
        default:
            break
        }
    }

    private func sliderValue(forPianoRollZoomLevel zoomLevel: CGFloat) -> CGFloat {
        let clampedZoom = max(0.0, min(1.0, zoomLevel))
        let base = pianoRollZoomSliderCurveBase
        return log(1.0 + (base - 1.0) * clampedZoom) / log(base)
    }

    private func pianoRollZoomLevel(forSliderValue sliderValue: CGFloat) -> CGFloat {
        let clampedSliderValue = max(0.0, min(1.0, sliderValue))
        let base = pianoRollZoomSliderCurveBase
        return (pow(base, clampedSliderValue) - 1.0) / (base - 1.0)
    }

    private var pianoRollZoomSliderCurveBase: CGFloat { 9.0 }
}
