//
//  ContentView+Actions.swift
//  MIDI Scribe
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ContentView {
    var appWillTerminateNotification: Notification.Name {
#if os(macOS)
        NSApplication.willTerminateNotification
#else
        UIApplication.willTerminateNotification
#endif
    }

    // MARK: - Rename flow

    func beginRename(_ take: RecordedTakeListItem) {
        viewModel.playbackEngine.pause()
        renamingTakeID = take.id
        renameDraft = take.userTitle ?? take.baseTitle
    }

    func commitRename() {
        guard let id = renamingTakeID else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.renameTake(id: id, to: trimmed.isEmpty ? nil : trimmed)
        renamingTakeID = nil
        renameDraft = ""
    }

    func cancelRename() {
        renamingTakeID = nil
        renameDraft = ""
    }

    func persistLastCompletedTakeIfNeeded() {
        guard let listItem = viewModel.lastCompletedTake else { return }
        guard let take = viewModel.fullTake(id: listItem.id) else { return }

        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            let takeID = take.id.uuidString
            let descriptor = FetchDescriptor<StoredTake>(
                predicate: #Predicate<StoredTake> { storedTake in
                    storedTake.takeID == takeID
                }
            )
            if let existing = try? context.fetch(descriptor), !existing.isEmpty {
                return
            }
            context.insert(StoredTake(recordedTake: take))
            try? context.save()
        }
    }

    func exportTake(id: UUID) {
        viewModel.playbackEngine.pause()
        exportErrorMessage = nil

        if let cached = viewModel.fullTake(id: id) {
            presentExporter(for: cached)
            return
        }

        let container = modelContext.container
        let takeID = id.uuidString
        Task {
            let take: RecordedTake? = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<StoredTake>(
                    predicate: #Predicate<StoredTake> { $0.takeID == takeID }
                )
                return (try? context.fetch(descriptor))?.first?.recordedTake
            }.value

            guard let take else {
                exportErrorMessage = "Unable to load take for export."
                return
            }
            presentExporter(for: take)
        }
    }

    func presentExporter(for take: RecordedTake) {
        let document = MIDIFileDocument(take: take)
        exportSuggestedName = document.suggestedFileName
        exportDocument = document
        isPresentingExporter = true
    }

    func beginDeleteTake(id: UUID) {
        viewModel.playbackEngine.pause()
        pendingDeleteTakeID = id
    }

    func beginBulkDeleteConfirmation() {
        viewModel.playbackEngine.pause()
        isPresentingBulkDeleteConfirm = true
    }

    func beginSettingsPresentation() {
        viewModel.playbackEngine.pause()
        appState.presentSettings()
    }

    func beginAboutPresentation() {
        viewModel.playbackEngine.pause()
        appState.presentAbout()
    }

    func handleModalPresentationRequest(_ request: AppModalPresentationRequest?) {
        guard let request else { return }
        defer { appState.modalPresentationRequest = nil }
        switch request {
        case .settings:
            beginSettingsPresentation()
        case .about:
            beginAboutPresentation()
        }
    }

    func deleteTake(id: UUID) {
        pendingDeleteTakeID = nil
        viewModel.playbackEngine.pause()
        viewModel.deleteTakeViaPersistence(id: id)

        if case .recentTake(let selectedID) = viewModel.selectedSidebarItem, selectedID == id {
            viewModel.selectedSidebarItem = .currentTake
        } else if case .starredTake(let selectedID) = viewModel.selectedSidebarItem, selectedID == id {
            viewModel.selectedSidebarItem = .currentTake
        }
    }

    func loadSampleTakes() {
        let container = modelContext.container
        if viewModel.persistenceService == nil {
            viewModel.persistenceService = TakePersistenceService(container: container)
        }
        Task {
            let result = await viewModel.loadSampleTakes()
            switch result {
            case .success(let count):
                appState.reportSampleTakeLoadResult(.success(count: count))
            case .failure(let error):
                appState.reportSampleTakeLoadResult(.failure(message: error.localizedDescription))
            }
        }
    }

    func resetAfterDataErase() {
        viewModel.playbackEngine.stopAndReset()
        viewModel.materializedTakes = [:]
        viewModel.recentTakes = []
        viewModel.lastCompletedTake = nil
        viewModel.selectedSidebarItem = .currentTake
        viewModel.multiSelection = []
        pendingDeleteTakeID = nil
        appState.takeCommandRequest = nil
        appState.takeCommandState = TakeCommandState()
    }

    func handleTakeCommandRequest(_ request: TakeCommandRequest?) {
        guard let request else { return }
        defer { appState.takeCommandRequest = nil }
        if let takeID = request.takeID {
            guard canPerformTakeCommand(takeID: takeID) else { return }
        } else {
            guard canPerformCurrentTakeCommand() else { return }
        }

        performTakeCommand(request)
    }

    func performTakeCommand(_ request: TakeCommandRequest) {
        if performCurrentTakeCommand(request) {
            return
        }

        performSavedTakeCommand(request)
    }

    func performCurrentTakeCommand(_ request: TakeCommandRequest) -> Bool {
        switch request {
        case .endCurrentTake:
            viewModel.endTake()
            return true
        case .cancelCurrentTake:
            viewModel.cancelTake()
            return true
        default:
            return false
        }
    }

    func performSavedTakeCommand(_ request: TakeCommandRequest) {
        if performPlaybackCommand(request) {
            return
        }

        switch request {
        case .endCurrentTake,
             .cancelCurrentTake,
             .togglePlayback,
             .rewindPlayback,
             .restartPlayback:
            break
        case .split(let takeID):
            guard viewModel.canSplit(takeID: takeID) else { return }
            viewModel.splitCurrentPausedTake()
        case .toggleStar(let takeID):
            viewModel.toggleStar(takeID: takeID)
        case .export(let takeID):
            exportTake(id: takeID)
        case .zoomIn:
            adjustPianoRollZoom(by: 0.1)
        case .zoomOut:
            adjustPianoRollZoom(by: -0.1)
        case .delete(let takeID):
            beginDeleteTake(id: takeID)
        }
    }

    func performPlaybackCommand(_ request: TakeCommandRequest) -> Bool {
        switch request {
        case .togglePlayback(let takeID):
            viewModel.togglePlayback(for: takeID)
        case .rewindPlayback(let takeID):
            rewindPlaybackToBeginning(for: takeID)
        case .restartPlayback(let takeID):
            viewModel.restartPlayback(for: takeID)
        default:
            return false
        }

        return true
    }

    func rewindPlaybackToBeginning(for takeID: UUID) {
        viewModel.rewindPlaybackToBeginning(for: takeID)
        pianoRollScrollToStartRequestID += 1
    }

    func adjustPianoRollZoom(by delta: CGFloat) {
        pianoRollZoomLevel = max(0.0, min(1.0, pianoRollZoomLevel + delta))
    }

    func updateTakeCommandState() {
        if viewModel.isTakeInProgress {
            appState.takeCommandState = TakeCommandState(
                isCurrentTakeInProgress: true,
                isActionInProgress: viewModel.isTakeActionInProgress
            )
            return
        }

        guard let takeID = selectedSavedTakeID,
              let take = viewModel.recentTake(id: takeID) else {
            appState.takeCommandState = TakeCommandState()
            return
        }

        appState.takeCommandState = TakeCommandState(
            takeID: takeID,
            isSavedTake: true,
            isPlaying: viewModel.isPlaying(takeID: takeID),
            isStarred: take.isStarred,
            canSplit: viewModel.canSplit(takeID: takeID),
            canZoom: take.summary.duration >= 5.0,
            isActionInProgress: viewModel.isTakeActionInProgress
        )
    }

    var selectedSavedTakeID: UUID? {
        switch viewModel.selectedSidebarItem {
        case .recentTake(let id), .starredTake(let id):
            return id
        case .currentTake, .organizing, .editingTakes:
            return nil
        }
    }

    func canPerformTakeCommand(takeID: UUID) -> Bool {
        selectedSavedTakeID == takeID && !viewModel.isTakeActionInProgress
    }

    func canPerformCurrentTakeCommand() -> Bool {
        viewModel.isTakeInProgress && !viewModel.isTakeActionInProgress
    }
}
