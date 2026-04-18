//
//  MIDILiveNoteViewModel+Playback.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    func togglePlayback(for takeID: UUID) {
        if isPlaying(takeID: takeID) {
            playbackEngine.pause()
            return
        }
        loadFullTakeAndPlay(takeID: takeID, restart: false)
    }

    func restartPlayback(for takeID: UUID) {
        loadFullTakeAndPlay(takeID: takeID, restart: true)
    }

    private func loadFullTakeAndPlay(takeID: UUID, restart: Bool) {
        if let cached = materializedTakes[takeID] {
            if restart {
                playbackEngine.restartPlayback(for: cached, target: selectedPlaybackTarget)
            } else {
                playbackEngine.togglePlayback(for: cached, target: selectedPlaybackTarget)
            }
            return
        }

        let target = selectedPlaybackTarget
        let resolver = resolveFullTake
        Task { [weak self] in
            let take: RecordedTake? = await Task.detached(priority: .userInitiated) { [resolver] in
                resolver?(takeID)
            }.value

            guard let self, let take else { return }
            self.materializedTakes[takeID] = take
            if restart {
                self.playbackEngine.restartPlayback(for: take, target: target)
            } else {
                self.playbackEngine.togglePlayback(for: take, target: target)
            }
        }
    }

    func isPlaying(takeID: UUID) -> Bool {
        let sameTake = playbackEngine.currentTakeID == takeID
        let playing = playbackEngine.isPlaying
        let sameTarget = playbackEngine.currentTarget == selectedPlaybackTarget
        return sameTake && playing && sameTarget
    }

    func deleteTake(id: UUID) {
        recentTakes.removeAll { $0.id == id }
        materializedTakes.removeValue(forKey: id)

        if lastCompletedTake?.id == id {
            lastCompletedTake = recentTakes.first
        }

        if case .recentTake(let selectedID) = selectedSidebarItem, selectedID == id {
            selectedSidebarItem = .currentTake
        }
    }
}
