//
//  ContentViewZoomReset.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func adjustPianoRollZoom(by delta: CGFloat) {
        pianoRollZoomLevel = max(0.0, min(1.0, pianoRollZoomLevel + delta))
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
}
