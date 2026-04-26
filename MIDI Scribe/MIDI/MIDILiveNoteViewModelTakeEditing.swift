//
//  MIDILiveNoteViewModel+TakeEditing.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    // MARK: - Mutating actions (star/rename/split/merge)

    /// True if there is a paused playback position that is strictly inside
    /// the take (not at the very start or end), so "Split Take Here" is
    /// meaningful.
    func canSplit(takeID: UUID) -> Bool {
        guard let take = recentTake(id: takeID) else { return false }
        guard playbackEngine.currentTakeID == takeID, !playbackEngine.isPlaying else { return false }
        guard let offset = playbackEngine.pausedAtOffset else { return false }
        return offset > 0.01 && offset < take.duration - 0.01
    }

    var pausedPlaybackOffset: TimeInterval? {
        playbackEngine.pausedAtOffset
    }

    func toggleStar(takeID: UUID) {
        guard let take = recentTake(id: takeID) else { return }
        let newValue = !take.isStarred
        // Optimistic local update so the sidebar reflects the change
        // immediately; ContentView only rebuilds from SwiftData on add/remove.
        updateListItem(id: takeID) { current in
            RecordedTakeListItem(
                id: current.id,
                startedAt: current.startedAt,
                endedAt: current.endedAt,
                title: current.title,
                baseTitle: current.baseTitle,
                userTitle: current.userTitle,
                isStarred: newValue,
                summary: current.summary
            )
        }
        runPersistence(operation: .starring) { service in
            try await service.setStarred(newValue, takeID: takeID)
        }
    }

    func renameTake(id takeID: UUID, to newName: String?) {
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateListItem(id: takeID) { current in
            RecordedTakeListItem(
                id: current.id,
                startedAt: current.startedAt,
                endedAt: current.endedAt,
                title: resolved ?? current.baseTitle,
                baseTitle: current.baseTitle,
                userTitle: resolved,
                isStarred: current.isStarred,
                summary: current.summary
            )
        }
        runPersistence(operation: .renaming) { service in
            try await service.renameTake(id: takeID, to: newName)
        }
    }

    func updateListItem(id takeID: UUID, transform: (RecordedTakeListItem) -> RecordedTakeListItem) {
        if let index = recentTakes.firstIndex(where: { $0.id == takeID }) {
            recentTakes[index] = transform(recentTakes[index])
        }
        if lastCompletedTake?.id == takeID, let last = lastCompletedTake {
            lastCompletedTake = transform(last)
        }
    }

    func deleteTakeViaPersistence(id takeID: UUID) {
        materializedTakes.removeValue(forKey: takeID)
        runPersistence(operation: .deleting) { service in
            try await service.deleteTake(id: takeID)
        }
    }

    func importMIDIFile(from url: URL) async -> Result<TakePersistenceService.ImportedTakeResult, Error> {
        guard pendingOperation == nil else {
            return .failure(SampleTakeLoadError.operationInProgress)
        }
        guard let persistenceService else {
            let message = "Storage is not ready yet."
            actionErrorText = message
            return .failure(SampleTakeLoadError.storageUnavailable)
        }

        pendingOperation = .importing
        actionErrorText = nil

        do {
            let imported = try await persistenceService.importMIDIFile(from: url)
            pendingOperation = nil
            selectedSidebarItem = .recentTake(imported.id)
            return .success(imported)
        } catch {
            pendingOperation = nil
            let message = "Unable to import MIDI file: \(error.localizedDescription)"
            actionErrorText = message
            return .failure(error)
        }
    }

    func splitCurrentPausedTake() {
        guard let takeID = playbackEngine.currentTakeID,
              let offset = playbackEngine.pausedAtOffset,
              canSplit(takeID: takeID) else { return }
        // The take we're about to mutate is the same one the playback engine
        // thinks it's paused inside. Fully reset the engine so Play after the
        // split starts from offset 0 of the newly shortened first half
        // instead of the now-invalid pre-split offset.
        playbackEngine.stopAndReset()
        materializedTakes.removeValue(forKey: takeID)
        runPersistence(operation: .splitting) { service in
            _ = try await service.splitTake(id: takeID, at: offset)
        }
    }

    func duplicateSelectedTake() {
        guard multiSelection.count == 1, let takeID = multiSelection.first else { return }
        duplicateTakeViaPersistence(id: takeID)
    }

    func duplicateTakeViaPersistence(id takeID: UUID) {
        runPersistence(operation: .duplicating) { [weak self] service in
            let newID = try await service.duplicateTake(id: takeID)
            await MainActor.run { [weak self] in
                if let newID {
                    self?.recordDuplicatedBulkResult(newTakeID: newID)
                }
            }
        }
    }

    func mergeSelectedTakes(silenceBetweenMs: Int) {
        let ids = Array(multiSelection)
        guard ids.count >= 2 else { return }
        let removed = Set(ids)
        if let current = playbackEngine.currentTakeID, removed.contains(current) {
            playbackEngine.stopAndReset()
        }
        for id in ids { materializedTakes.removeValue(forKey: id) }
        multiSelection.removeAll()
        runPersistence(operation: .merging) { [weak self] service in
            let newID = try await service.mergeTakes(ids: ids, silenceBetweenMs: silenceBetweenMs)
            await MainActor.run { [weak self] in
                if let newID {
                    self?.recordMergedBulkResult(newTakeID: newID, removedIDs: removed)
                }
            }
        }
    }

    func deleteSelectedTakes() {
        let ids = Array(multiSelection)
        guard !ids.isEmpty else { return }
        let removed = Set(ids)
        if let current = playbackEngine.currentTakeID, removed.contains(current) {
            playbackEngine.stopAndReset()
        }
        for id in ids { materializedTakes.removeValue(forKey: id) }
        multiSelection.removeAll()
        runPersistence(operation: .deleting) { [weak self] service in
            for id in ids {
                try await service.deleteTake(id: id)
            }
            await MainActor.run { [weak self] in
                self?.recordDeletedBulkResult(removedIDs: removed)
            }
        }
    }

    /// Star all currently selected takes (no-op on ones already starred). If
    /// every selected take is already starred, unstar them instead. Matches
    /// the toggle semantics users expect.
    func toggleStarForSelectedTakes() {
        let ids = multiSelection
        guard !ids.isEmpty else { return }
        let takes = recentTakes.filter { ids.contains($0.id) }
        // If they're all starred, unstar; otherwise star everything missing it.
        let allStarred = takes.allSatisfy(\.isStarred)
        let newValue = !allStarred
        for take in takes where take.isStarred != newValue {
            updateListItem(id: take.id) { current in
                RecordedTakeListItem(
                    id: current.id,
                    startedAt: current.startedAt,
                    endedAt: current.endedAt,
                    title: current.title,
                    baseTitle: current.baseTitle,
                    userTitle: current.userTitle,
                    isStarred: newValue,
                    summary: current.summary
                )
            }
        }
        let idsToUpdate = takes.filter { $0.isStarred != newValue }.map(\.id)
        runPersistence(operation: .starring) { [weak self] service in
            for id in idsToUpdate {
                try await service.setStarred(newValue, takeID: id)
            }
            await MainActor.run { [weak self] in
                self?.recordStarredBulkResult(affectedIDs: Set(idsToUpdate))
            }
        }
    }

    /// Convenience for the detail pane: true if every selected take is
    /// starred (so the bulk-star button can show "Unstar" instead).
    var allSelectedAreStarred: Bool {
        let ids = multiSelection
        guard !ids.isEmpty else { return false }
        let selected = recentTakes.filter { ids.contains($0.id) }
        return !selected.isEmpty && selected.allSatisfy(\.isStarred)
    }

    func runPersistence(
        operation: TakeListPendingOperation,
        _ work: @escaping @Sendable (TakePersistenceService) async throws -> Void
    ) {
        guard let persistenceService else {
            actionErrorText = "Persistence service not available."
            return
        }
        guard pendingOperation == nil else {
            // Don't stack operations on top of each other.
            return
        }
        pendingOperation = operation
        actionErrorText = nil
        Task { [weak self] in
            do {
                try await work(persistenceService)
            } catch {
                await MainActor.run { [weak self] in
                    self?.actionErrorText = error.localizedDescription
                }
            }
            await MainActor.run { [weak self] in
                self?.pendingOperation = nil
            }
        }
    }
}
