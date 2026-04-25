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
        let takeID = take.id
        let initialDraft = take.userTitle ?? take.baseTitle
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard viewModel.recentTake(id: takeID) != nil else { return }
            renameDraft = initialDraft
            renamingTakeID = takeID
        }
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
        let cachedTake = viewModel.materializedTake(id: listItem.id)
        let service = viewModel.persistenceService

        let container = modelContext.container
        Task.detached(priority: .userInitiated) {
            let take: RecordedTake?
            if let cachedTake {
                take = cachedTake
            } else if let service {
                take = try? await service.recordedTake(id: listItem.id)
            } else {
                take = nil
            }
            guard let take else { return }

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
        let preferredDisplayName = viewModel.recentTake(id: id)?.displayTitle
        if let cached = viewModel.materializedTake(id: id) {
            presentExporter(for: cached, preferredDisplayName: preferredDisplayName)
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
                exportErrorMessage = "Unable to load Take for export."
                return
            }
            presentExporter(for: take, preferredDisplayName: preferredDisplayName)
        }
    }

    func presentExporter(for take: RecordedTake, preferredDisplayName: String? = nil) {
        let document = MIDIFileDocument(take: take, suggestedName: preferredDisplayName)
        exportSuggestedName = suggestedExportFilename(from: document.suggestedFileName)
        exportDocument = document
        isPresentingExporter = true
    }

    func beginDeleteTake(id: UUID) {
        viewModel.playbackEngine.pause()
        pendingDeleteTakeID = id
    }

    func beginLiveTakeDelete() {
        guard viewModel.isTakeInProgress else {
            viewModel.cancelTake()
            return
        }
        if viewModel.currentTakeSnapshot.duration < 10.0 {
            viewModel.cancelTake()
            return
        }
        isPresentingLiveTakeDeleteConfirm = true
    }

    func confirmLiveTakeDelete() {
        isPresentingLiveTakeDeleteConfirm = false
        guard viewModel.isTakeInProgress else { return }
        viewModel.cancelTake()
    }

    func beginSplitTakeConfirmation(id: UUID) {
        viewModel.playbackEngine.pause()
        guard viewModel.canSplit(takeID: id) else { return }
        pendingSplitTakeID = id
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

    func beginHelpPresentation() {
        viewModel.playbackEngine.pause()
        appState.presentHelp()
    }

    func handleModalPresentationRequest(_ request: AppModalPresentationRequest?) {
        guard let request else { return }
        defer { appState.modalPresentationRequest = nil }
        switch request {
        case .settings:
            beginSettingsPresentation()
        case .about:
            beginAboutPresentation()
        case .help:
            beginHelpPresentation()
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

    func splitTake(id: UUID) {
        pendingSplitTakeID = nil
        viewModel.playbackEngine.pause()
        guard viewModel.canSplit(takeID: id) else { return }
        viewModel.splitCurrentPausedTake()
    }

    func splitConfirmationMessage(for takeID: UUID) -> String {
        let takeTitle = viewModel.recentTake(id: takeID)?.displayTitle ?? "This take"
        let offsetText = formatOffset(viewModel.pausedPlaybackOffset ?? 0)
        return "\(takeTitle) will be split into two saved takes at \(offsetText). This cannot be undone."
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
        clearBulkSelection()
        pendingDeleteTakeID = nil
        pendingSplitTakeID = nil
        isPresentingLiveTakeDeleteConfirm = false
        appState.takeCommandRequest = nil
        appState.takeCommandState = TakeCommandState()
        hasEvaluatedWelcomeSheet = false
        isPresentingWelcomeSheet = false
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
        case .startCurrentTake:
            viewModel.startTake()
            return true
        case .endCurrentTake:
            viewModel.endTake()
            return true
        case .cancelCurrentTake:
            beginLiveTakeDelete()
            return true
        default:
            return false
        }
    }

    func performSavedTakeCommand(_ request: TakeCommandRequest) {
        if performPlaybackCommand(request) {
            return
        }

        if performZoomCommand(request) {
            return
        }

        switch request {
        case .split(let takeID):
            guard viewModel.canSplit(takeID: takeID) else { return }
            beginSplitTakeConfirmation(id: takeID)
        case .toggleStar(let takeID):
            viewModel.toggleStar(takeID: takeID)
        case .rename(let takeID):
            guard !viewModel.isPlaying(takeID: takeID),
                  let take = viewModel.recentTake(id: takeID) else { return }
            beginRename(take)
        case .export(let takeID):
            exportTake(id: takeID)
        case .delete(let takeID):
            beginDeleteTake(id: takeID)
        default:
            break
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

    func performZoomCommand(_ request: TakeCommandRequest) -> Bool {
        switch request {
        case .zoomIn:
            adjustPianoRollZoom(by: 0.1)
        case .zoomOut:
            adjustPianoRollZoom(by: -0.1)
        case .resetZoom:
            resetPianoRollZoom()
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

    func resetPianoRollZoom() {
        pianoRollZoomLevel = 0.0
    }

    func updateTakeCommandState() {
        if viewModel.selectedSidebarItem == .currentTake {
            updateTakeCommandStateIfChanged(TakeCommandState(
                isCurrentTakeSelected: true,
                isCurrentTakeInProgress: viewModel.isTakeInProgress,
                isActionInProgress: viewModel.isTakeActionInProgress
            ))
            return
        }

        if viewModel.isTakeInProgress {
            updateTakeCommandStateIfChanged(TakeCommandState(
                isCurrentTakeSelected: false,
                isCurrentTakeInProgress: true,
                isActionInProgress: viewModel.isTakeActionInProgress
            ))
            return
        }

        guard let takeID = selectedSavedTakeID,
              let take = viewModel.recentTake(id: takeID) else {
            updateTakeCommandStateIfChanged(TakeCommandState())
            return
        }

        updateTakeCommandStateIfChanged(TakeCommandState(
            takeID: takeID,
            isSavedTake: true,
            isPlaying: viewModel.isPlaying(takeID: takeID),
            isStarred: take.isStarred,
            canSplit: viewModel.canSplit(takeID: takeID),
            canZoom: take.summary.duration >= 5.0,
            isActionInProgress: viewModel.isTakeActionInProgress
        ))
    }

    func updateTakeCommandStateIfChanged(_ state: TakeCommandState) {
        guard appState.takeCommandState != state else { return }
        appState.takeCommandState = state
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
        viewModel.selectedSidebarItem == .currentTake && !viewModel.isTakeActionInProgress
    }
}
