//
//  ContentView.swift
//  MIDI Scribe
//
//  Created by James Ranson on 3/21/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum SidebarItem: Hashable {
    case currentTake
    case organizing
    case editingTakes
    case starredTake(UUID)
    case recentTake(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var appState: AppState
    @Query(sort: \StoredTake.startedAt, order: .reverse) var storedRecentTakes: [StoredTake]
    @ObservedObject var settings: AppSettings
    @StateObject var viewModel: MIDILiveNoteViewModel
    @State var pendingDeleteTakeID: UUID?
    @State var exportDocument: MIDIFileDocument?
    @State var exportSuggestedName: String = "take"
    @State var isPresentingExporter = false
    @State var exportErrorMessage: String?
    @State var isPresentingMergeDialog = false
    @State var mergeSilenceMsText: String = "0"
    @State var renamingTakeID: UUID?
    @State var renameDraft: String = ""
    @State var isEditingList = false
    /// Anchor for shift-click range selection on macOS.
    @State var selectionAnchorID: UUID?
    /// Selection to restore when leaving Edit mode (unless a merge/delete
    /// requires a different final selection).
    @State var preEditSelection: SidebarItem?
    @State var isPresentingBulkDeleteConfirm = false
    @State var pianoRollZoomLevel: CGFloat = 0.0
#if os(iOS)
    /// When the split collapses to one column (typical iPhone landscape), this controls whether the
    /// sidebar or detail is on top. `.detail` matches standard push behavior after choosing a row.
    @State var preferredCompactColumn: NavigationSplitViewColumn = .detail
#endif

    init(settings: AppSettings) {
        self.settings = settings
        _viewModel = StateObject(wrappedValue: MIDILiveNoteViewModel(settings: settings))
    }

    var body: some View {
        configuredContent
    }

    private var configuredContent: some View {
        alertContent(exportContent(deleteDialogContent(observerContent(setupContent(baseContent)))))
    }

    private var baseContent: some View {
#if os(iOS)
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            sidebar
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: viewModel.selectedSidebarItem) { _, _ in
            phoneFocusDetailColumnAfterSidebarSelection()
        }
        .onAppear {
            phoneFocusDetailColumnAfterSidebarSelection()
            DispatchQueue.main.async {
                phoneFocusDetailColumnAfterSidebarSelection()
            }
        }
        .frame(minWidth: 0, minHeight: 320)
#else
        NavigationSplitView {
            sidebar
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
#endif
        } detail: {
            detailContent
        }
        .frame(minWidth: 520, minHeight: 320)
#endif
    }

#if os(iOS)
    private func phoneFocusDetailColumnAfterSidebarSelection() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        preferredCompactColumn = .detail
    }
#endif

    private func lifecycleContent(_ content: some View) -> some View {
        observerContent(setupContent(content))
    }

    private func setupContent(_ content: some View) -> some View {
        content
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onReceive(NotificationCenter.default.publisher(for: appWillTerminateNotification)) { _ in
            viewModel.appWillTerminate()
        }
        .onAppear {
            // One-time wiring that never needs to change.
            let container = modelContext.container
            if viewModel.persistenceService == nil {
                viewModel.persistenceService = TakePersistenceService(container: container)
            }
            viewModel.resolveFullTake = { id in
                let context = ModelContext(container)
                let takeID = id.uuidString
                let descriptor = FetchDescriptor<StoredTake>(
                    predicate: #Predicate<StoredTake> { $0.takeID == takeID }
                )
                return (try? context.fetch(descriptor))?.first?.recordedTake
            }
            viewModel.setRecentTakes(storedRecentTakes.map(\.listItem))
        }
    }

    private func observerContent(_ content: some View) -> some View {
        content
        // Rebuild our lightweight list whenever rows are added/removed/reordered.
        // We key on takeIDs only (O(n) string compare) instead of faulting
        // extra @Attribute properties on every body pass, which was causing
        // main-thread hangs on sidebar selection.
        .onChange(of: storedRecentTakes.map(\.takeID)) { _, _ in
            let items = storedRecentTakes.map(\.listItem)
            DispatchQueue.main.async {
                viewModel.setRecentTakes(items)
            }
        }
#if os(macOS)
        .onChange(of: viewModel.selectedSidebarItem) { oldValue, newValue in
            // Defer so we don't mutate @Published state (multiSelection) from
            // within a view update triggered by the selection change itself.
            DispatchQueue.main.async {
                handleSelectionChangeForModifiers(old: oldValue, new: newValue)
            }
        }
#endif
        .onChange(of: viewModel.lastCompletedTake?.id) { _, _ in
            persistLastCompletedTakeIfNeeded()
        }
        .onChange(of: appState.sampleTakeLoadRequestID) { _, _ in
            loadSampleTakes()
        }
        .onChange(of: appState.dataResetRequestID) { _, _ in
            resetAfterDataErase()
        }
        .onChange(of: appState.takeCommandRequest) { _, request in
            handleTakeCommandRequest(request)
        }
        .onReceive(viewModel.objectWillChange) { _ in
            DispatchQueue.main.async {
                updateTakeCommandState()
            }
        }
        .onReceive(viewModel.playbackEngine.objectWillChange) { _ in
            DispatchQueue.main.async {
                updateTakeCommandState()
            }
        }
        // When a bulk merge or delete completes, exit Edit mode automatically
        // and restore/update the selected sidebar item appropriately.
        .onChange(of: viewModel.lastBulkResult) { _, newValue in
            guard isEditingList, newValue != nil else { return }
            switch newValue {
            case .merged, .deleted:
                DispatchQueue.main.async { toggleEditMode() }
            case .starred, .none:
                break
            }
        }
    }

    private func dialogContent(_ content: some View) -> some View {
        alertContent(exportContent(deleteDialogContent(content)))
    }

    private func deleteDialogContent(_ content: some View) -> some View {
        content
        .confirmationDialog(
            "Delete Take?",
            isPresented: Binding(
                get: { pendingDeleteTakeID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteTakeID = nil
                    }
                }
            ),
            presenting: pendingDeleteTakeID
        ) { takeID in
            Button("Delete Take", role: .destructive) {
                deleteTake(id: takeID)
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteTakeID = nil
            }
        } message: { takeID in
            Text(viewModel.recentTake(id: takeID)?.displayTitle ?? "This take")
        }
    }

    private func exportContent(_ content: some View) -> some View {
        content
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument,
            contentType: .midi,
            defaultFilename: exportSuggestedName
        ) { result in
            switch result {
            case .success:
                exportErrorMessage = nil
            case .failure(let error):
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
            }
            exportDocument = nil
        }
    }

    private func alertContent(_ content: some View) -> some View {
        content
        .alert("Merge \(viewModel.multiSelection.count) Takes", isPresented: $isPresentingMergeDialog) {
            TextField("Silence between takes (ms)", text: $mergeSilenceMsText)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            Button("Merge") {
                let silenceMillis = Int(mergeSilenceMsText) ?? 0
                viewModel.mergeSelectedTakes(silenceBetweenMs: silenceMillis)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the number of milliseconds of silence to insert between consecutive takes (default 0).")
        }
        .alert("Rename Take", isPresented: Binding(
            get: { renamingTakeID != nil },
            set: { if !$0 { cancelRename() } }
        )) {
            TextField("Name", text: $renameDraft)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { cancelRename() }
        } message: {
            Text("Enter a new name for this take.")
        }
        .alert(bulkDeleteConfirmationTitle, isPresented: $isPresentingBulkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                viewModel.deleteSelectedTakes()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected takes. This action cannot be undone.")
        }
    }

    private var bulkDeleteConfirmationTitle: String { "Delete \(viewModel.multiSelection.count) Takes?" }
}
