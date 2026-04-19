//
//  ContentView+DetailPane.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    @ViewBuilder
    var detailContent: some View {
        Group {
            switch viewModel.selectedSidebarItem {
            case .currentTake:
                currentTakeDetail
            case .recentTake(let takeID), .starredTake(let takeID):
                completedTakeDetail(for: takeID)
            case .organizing:
                placeholderDetail("Organizing tools will appear here.")
            case .editingTakes:
                editingTakesDetail
            }
        }
#if os(iOS)
        .navigationBarBackButtonHidden(true)
#endif
    }

    var editingTakesDetail: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Edit Takes")
                .font(.title2)

            if viewModel.multiSelection.isEmpty {
                editingTakesEmptySelectionHint
            } else if viewModel.multiSelection.count == 1 {
                editingTakesSingleSelectionHint
            } else {
                editingTakesMultiSelectionContent
            }

            if let pendingTakeOperation = viewModel.pendingOperation {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pendingTakeOperation.displayText)
                        .foregroundStyle(.secondary)
                }
            }

            if let actionErrorText = viewModel.actionErrorText {
                Text(actionErrorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button("Done") {
                toggleEditMode()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var editingTakesEmptySelectionHint: some View {
        Text(
            "Tap the circles next to takes in the sidebar to select them. "
                + "Once you've selected two or more, you can merge, star, or delete them in bulk."
        )
        .foregroundStyle(.secondary)
    }

    private var editingTakesSingleSelectionHint: some View {
        Group {
            Text("Select at least one more take to enable bulk actions.")
                .foregroundStyle(.secondary)
            Text("Currently selected: 1 take")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var editingTakesMultiSelectionContent: some View {
        Group {
            Text("\(viewModel.multiSelection.count) takes selected.")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button {
                    mergeSilenceMsText = "0"
                    isPresentingMergeDialog = true
                } label: {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                }
                .disabled(viewModel.isTakeActionInProgress)

                Button {
                    viewModel.toggleStarForSelectedTakes()
                } label: {
                    Label(viewModel.allSelectedAreStarred ? "Unstar" : "Star",
                          systemImage: viewModel.allSelectedAreStarred ? "star.slash" : "star")
                }
                .disabled(viewModel.isTakeActionInProgress)

                Button(role: .destructive) {
                    isPresentingBulkDeleteConfirm = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.isTakeActionInProgress)
            }
        }
    }

    /// While Edit mode is active, lock the sidebar selection to
    /// `.editingTakes` so an accidental click on a take row doesn't navigate
    /// away from the bulk-actions detail pane. The user can still interact
    /// with the per-row checkboxes and the Done / pencil button to exit.
    var sidebarSelectionBinding: Binding<SidebarItem> {
        Binding(
            get: { viewModel.selectedSidebarItem },
            set: { newValue in
                if isEditingList {
                    // In edit mode, tapping a row acts like tapping its
                    // checkbox: toggle membership in the bulk selection and
                    // keep the detail pane on the edit instructions.
                    // Defer to the next runloop tick so we don't mutate
                    // @Published state from within a view update.
                    let toggleID = takeID(fromAny: newValue)
                    DispatchQueue.main.async {
                        if let id = toggleID {
                            toggleMultiSelection(id)
                        }
                        if viewModel.selectedSidebarItem != .editingTakes {
                            viewModel.selectedSidebarItem = .editingTakes
                        }
                    }
                } else {
                    // Match edit-mode handling: List updates run inside SwiftUI's view
                    // update; mutating @Published here triggers "Publishing changes
                    // from within view updates is not allowed."
                    DispatchQueue.main.async {
                        viewModel.selectedSidebarItem = newValue
                    }
                }
            }
        )
    }

    func toggleEditMode() {
        if isEditingList {
            // Exiting edit mode. Decide where to return focus based on what
            // just happened (if anything).
            let restore = resolvedSelectionAfterEdit()
            isEditingList = false
            viewModel.multiSelection.removeAll()
            selectionAnchorID = nil
            viewModel.clearLastBulkResult()
            viewModel.selectedSidebarItem = restore
            preEditSelection = nil
        } else {
            preEditSelection = viewModel.selectedSidebarItem
            viewModel.multiSelection.removeAll()
            viewModel.clearLastBulkResult()
            isEditingList = true
            viewModel.selectedSidebarItem = .editingTakes
        }
    }

    func resolvedSelectionAfterEdit() -> SidebarItem {
        switch viewModel.lastBulkResult {
        case .merged(let newID, _):
            return .recentTake(newID)
        case .deleted(let removed):
            if let pre = preEditSelection, let preID = takeID(fromAny: pre), removed.contains(preID) {
                return .currentTake
            }
            return preEditSelection ?? .currentTake
        case .starred, .none:
            return preEditSelection ?? .currentTake
        }
    }

    func takeID(fromAny item: SidebarItem) -> UUID? {
        switch item {
        case .recentTake(let id), .starredTake(let id): return id
        default: return nil
        }
    }

    var currentTakeDetail: some View {
        VStack(spacing: 32) {
            if viewModel.isTakeInProgress {
                currentTakeInProgressContent
            } else {
                currentTakeIdleContent
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if viewModel.isTakeInProgress {
                currentTakeActionsToolbar()
            }
            #if os(iOS)
            if viewModel.isTakeInProgress {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            iOSAppActionsToolbar()
            #endif
        }
    }

    @ToolbarContentBuilder
    private func currentTakeActionsToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: currentTakeToolbarPlacement) {
            Button {
                viewModel.endTake()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!viewModel.isTakeInProgress)
            .help("End Take")
            .accessibilityLabel("End Take")

            Button(role: .destructive) {
                viewModel.cancelTake()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(!viewModel.isTakeInProgress)
            .help("Cancel Take")
            .accessibilityLabel("Cancel Take")
        }
    }

    private var currentTakeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    private var currentTakeInProgressContent: some View {
        VStack(spacing: 48) {
            VStack(spacing: 12) {
                Text("Current Take Duration")
                    .font(.headline)

                Text(viewModel.currentTakeDurationText)
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }

            VStack(spacing: 16) {
                Text("Current MIDI Note(s)")
                    .font(.headline)

                Text(viewModel.currentNoteText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 60)

                if let errorText = viewModel.errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: 16) {
                Text("Current MIDI Channel(s)")
                    .font(.headline)

                Text(viewModel.currentChannelText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                Text("Recorded Take Summary")
                    .font(.headline)

                Text(viewModel.currentTakeSummaryText)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if viewModel.shouldShowIdleTimeoutText {
                    Text(viewModel.idleTimeoutText)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
 
            livePianoRoll
        }
    }

    @ViewBuilder
    private var livePianoRoll: some View {
        if let liveTake = currentLiveTake {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom != .phone {
                livePianoRollZoomSliderChrome
            }
#else
            livePianoRollZoomSliderChrome
#endif

            PianoRollView(
                take: liveTake,
                viewModel: viewModel,
                zoomLevel: $pianoRollZoomLevel,
                isLive: true
            )
            .layoutPriority(1)
        }
    }

    private var livePianoRollZoomSliderChrome: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $pianoRollZoomLevel, in: 0...1)
                .frame(width: 150)
            Image(systemName: "plus.magnifyingglass")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var currentLiveTake: RecordedTake? {
        guard let startedAt = viewModel.liveTakeStartedAt else { return nil }
        let events = viewModel.liveTakeEvents
        let endedAt = events.last?.receivedAt ?? startedAt
        return RecordedTake(
            id: viewModel.liveTakeID,
            startedAt: startedAt,
            endedAt: endedAt,
            events: events,
            summary: RecordedTakeSummary.empty
        )
    }

    private var currentTakeIdleContent: some View {
        VStack(spacing: 20) {
            Text(viewModel.currentTakePromptText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(iOS)
extension ContentView {
    @ToolbarContentBuilder
    func iOSAppActionsToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                appState.presentSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Preferences")

            Button {
                appState.presentAbout()
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About")
        }
    }
}
#endif
