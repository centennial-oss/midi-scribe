//
//  MIDILiveNoteViewModel+Playback.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    func materializedTake(id: UUID) -> RecordedTake? {
        materializedTakes[id]
    }

    func materializeTakeForDisplay(id takeID: UUID) {
        guard materializedTakes[takeID] == nil else { return }
        guard !materializingTakeIDs.contains(takeID) else { return }
        materializingTakeIDs.insert(takeID)

        let service = persistenceService
        let resolver = resolveFullTake
        Task { [weak self] in
            let take: RecordedTake?
            if let service {
                take = try? await service.recordedTake(id: takeID)
            } else {
                take = await Task.detached(priority: .userInitiated) { [resolver] in
                    resolver?(takeID)
                }.value
            }

            guard let self else { return }
            self.materializingTakeIDs.remove(takeID)
            guard let take else { return }
            self.materializedTakes[takeID] = take
        }
    }

    func togglePlayback(for takeID: UUID) {
        if isPlaying(takeID: takeID) {
            playbackEngine.pause()
            return
        }
        loadFullTakeAndPlay(takeID: takeID, restart: false, target: selectedPlaybackTarget)
    }

    func restartPlayback(for takeID: UUID) {
        loadFullTakeAndPlay(takeID: takeID, restart: true, target: selectedPlaybackTarget)
    }

    func rewindPlaybackToBeginning(for takeID: UUID) {
        playbackEngine.rewindToBeginning(takeID: takeID)
    }

    func loadFullTakeAndPlay(
        takeID: UUID,
        restart: Bool,
        target: PlaybackOutputTarget,
        saveCurrentTakeFirst: Bool = true
    ) {
        if saveCurrentTakeFirst, isTakeInProgress {
            completedTakeSelectionMode = .preserveSelection(selectedSidebarItem)
            playbackRequestAfterCurrentTakeEnds = DeferredPlaybackRequest(
                takeID: takeID,
                restart: restart,
                target: target
            )
            Task {
                let completedTake = await takeLifecycle.endCurrentTake()
                if !completedTake {
                    await MainActor.run { [weak self] in
                        self?.completedTakeSelectionMode = .showCompleted
                        self?.performDeferredPlaybackRequestIfNeeded()
                    }
                }
            }
            return
        }

        if let cached = materializedTakes[takeID] {
            if restart {
                playbackEngine.restartPlayback(for: cached, target: target)
            } else {
                playbackEngine.togglePlayback(for: cached, target: target)
            }
            return
        }

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
