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

enum ContentSidebarItem: Hashable {
    case currentTake
    case organizing
    case editingTakes
    case starredTake(UUID)
    case recentTake(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.scenePhase) var scenePhase
    @EnvironmentObject var appState: AppState
#if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
#endif
    @Query(sort: \StoredTake.startedAt, order: .reverse) var storedRecentTakes: [StoredTake]
    @ObservedObject var settings: AppSettings
    @StateObject var viewModel: MIDILiveNoteViewModel
    @State var pendingDeleteTakeID: UUID?
    @State var pendingSplitTakeID: UUID?
    @State var isPresentingLiveTakeDeleteConfirm = false
    @State var exportDocument: MIDIFileDocument?
    @State var exportSuggestedName: String = "take"
    @State var isPresentingExporter = false
    @State var isPresentingImporter = false
    @State var exportErrorMessage: String?
    @State var importAlert: MIDIImportAlert?
    @State var pendingSharedImport: PendingSharedImport?
    @State var isPresentingMergeDialog = false
    @State var mergeSilenceMsText: String = "0"
    @State var renamingTakeID: UUID?
    @State var renameDraft: String = ""
    @State var isEditingList = false
    /// Anchor for shift-click range selection on macOS.
    @State var selectionAnchorID: UUID?
    /// Selection to restore when leaving Edit mode (unless a merge/delete
    /// requires a different final selection).
    @State var preEditSelection: ContentSidebarItem?
    @State var isSidebarPresented = false
    @State var suppressNextSidebarAutoHide = false
    @State var isPresentingBulkDeleteConfirm = false
    @State var pianoRollZoomLevel: CGFloat = 0.0
    @State var pianoRollScrollToStartRequestID = 0
    @State var completedTakeRenderDelayRequestID = 0
    @State var completedTakeReadyToRenderID: UUID?
    @State var swipeRevealedTakeID: UUID?
    @State var hasEvaluatedWelcomeSheet = false
    @State var isPresentingWelcomeSheet = false
    init(settings: AppSettings) {
        self.settings = settings
        _viewModel = StateObject(wrappedValue: MIDILiveNoteViewModel(settings: settings))
    }

    var body: some View {
        configuredContent
    }

    private var configuredContent: some View {
        bottomBulkEditActionRowContent(
            idleTimerContent(
            welcomeSheetContent(
                dialogContent(observerContent(setupContent(baseContent)))
            )
            )
        )
    }

    private var baseContent: some View {
        Sidebar(
            isPresented: $isSidebarPresented,
            excludesCustomSidebarToggleButtons: true,
            forceCustomSidebar: forceCustomSidebarOnCurrentDevice,
            sidebar: {
                sidebar
#if os(macOS)
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280)
#endif
            },
            detail: { sidebarDetailHost }
        )
#if os(iOS)
        .frame(minWidth: 0, minHeight: 320)
#else
        .frame(minWidth: 520, minHeight: 320)
#endif
    }

    private var forceCustomSidebarOnCurrentDevice: Bool? {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? true : nil
#else
        nil
#endif
    }

    @ViewBuilder
    private var sidebarDetailHost: some View {
#if os(iOS)
        NavigationStack {
            detailContent
        }
#else
        detailContent
#endif
    }

    private func lifecycleContent(_ content: some View) -> some View {
        observerContent(setupContent(content))
    }

    private func idleTimerContent(_ content: some View) -> some View {
#if os(iOS)
        content
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = viewModel.isTakeInProgress
            }
            .onChange(of: viewModel.isTakeInProgress) { _, isTakeInProgress in
                UIApplication.shared.isIdleTimerDisabled = isTakeInProgress
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
#else
        content
#endif
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
                importPendingSharedFilesIfAny()
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
            evaluateWelcomeSheetPresentationIfNeeded()
        }
    }

    private func observerContent(_ content: some View) -> some View {
        let observedContent = content
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

        return bulkResultObservationContent(commandObservationContent(observedContent))
    }

    private func commandObservationContent(_ content: some View) -> some View {
        content
            .onAppear {
                importPendingSharedFilesIfAny()
                handlePendingIncomingURL()
            }
            .onChange(of: viewModel.pendingOperation) { _, operation in
                guard operation == nil else { return }
                importPendingSharedFilesIfAny()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                importPendingSharedFilesIfAny()
            }
#if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                importPendingSharedFilesIfAny()
            }
#endif
            .onChange(of: appState.dataResetRequestID) { _, _ in
                resetAfterDataErase()
            }
            .onChange(of: appState.midiImportRequestID) { _, _ in
                beginMIDIImportPresentation()
            }
            .onChange(of: appState.takeCommandRequest) { _, request in
                handleTakeCommandRequest(request)
            }
            .onChange(of: appState.modalPresentationRequest) { _, request in
                handleModalPresentationRequest(request)
            }
            .onChange(of: appState.incomingURLRequestID) { _, _ in
                handlePendingIncomingURL()
            }
    }

    private func bulkResultObservationContent(_ content: some View) -> some View {
        content
        #if os(iOS)
        .onChange(of: isSidebarPresented) { _, isPresented in
            // If the user dismisses the sidebar while in Edit mode, treat it
            // the same as tapping Done in the sidebar: exit Edit mode and
            // restore the prior detail selection.
            guard !isPresented, isEditingList else { return }
            DispatchQueue.main.async {
                toggleEditMode()
            }
        }
        #endif
        // When a bulk merge, star, or delete completes, exit Edit mode automatically
        // and restore/update the selected sidebar item appropriately.
        .onChange(of: viewModel.lastBulkResult) { _, newValue in
            guard isEditingList, newValue != nil else { return }
            switch newValue {
            case .merged, .deleted, .starred:
                DispatchQueue.main.async { toggleEditMode() }
            case .none:
                break
            }
        }
    }

}

private extension ContentView {
    func handlePendingIncomingURL() {
        guard let url = appState.consumePendingIncomingURL() else { return }
        handleIncomingMIDIURL(url)
    }
}

struct PendingSharedImport: Identifiable, Equatable {
    let url: URL
    let fileName: String

    var id: String { url.absoluteString }
}

struct MIDIImportAlert: Identifiable, Equatable {
    let title: String
    let message: String

    var id: String { "\(title)\n\(message)" }
}

#if os(macOS)
struct DiscreteSettingsSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        if nsView.doubleValue != value {
            nsView.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        private var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc
        func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue.rounded()
        }
    }
}
#endif
