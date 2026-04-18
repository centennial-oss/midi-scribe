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
        Task.detached(priority: .utility) {
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
}
