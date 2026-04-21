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
                    beginBulkDeleteConfirmation()
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
        VStack(spacing: viewModel.isTakeInProgress ? 6 : 32) {
            if viewModel.isTakeInProgress {
                currentTakeInProgressContent
                    #if os(macOS)
                    .padding(.top, 8)
                    #endif
            } else {
                currentTakeIdleContent
            }
        }
        .padding(.horizontal, viewModel.isTakeInProgress ? 24 : 32)
        .padding(.top, viewModel.isTakeInProgress ? 0 : 32)
        .padding(.bottom, viewModel.isTakeInProgress ? 12 : 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            #if os(iOS)
            iPhoneSidebarToggleToolbar()
            #endif
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
        VStack(spacing: 6) {
            currentTakeMetadata
                .frame(maxWidth: .infinity, alignment: .leading)

            livePianoRoll
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var currentTakeMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(viewModel.currentTakeDurationText)
                .font(.takeMetadataValue)
                .foregroundStyle(.secondary)

            currentTakeInlineLabeledValue("Notes", currentTakeNotesCountText)
            currentTakeInlineLabeledValue("Range", currentTakeRangeText)
            currentTakeInlineLabeledValue("Channels", currentTakeChannelsText)

            Spacer(minLength: 24)

            if viewModel.shouldShowCurrentNoteText {
                currentTakeInlineLabeledValue("Now", viewModel.currentNoteText)
            }

            if viewModel.shouldShowIdleTimeoutText {
                Text(viewModel.idleTimeoutText)
                    .font(.takeMetadataValue)
                    .foregroundStyle(.secondary)
            }

            if let errorText = viewModel.errorText {
                Text("/")
                    .font(.takeMetadataValue)
                    .foregroundStyle(.secondary)
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    private var currentTakeNotesCountText: String {
        let summary = viewModel.currentTakeSnapshot.summary
        return "\(max(summary.noteOnCount, summary.noteOffCount))"
    }

    private var currentTakeRangeText: String {
        let summary = viewModel.currentTakeSnapshot.summary
        return viewModel.formatNoteRange(lowest: summary.lowestNote, highest: summary.highestNote)
    }

    private var currentTakeChannelsText: String {
        let channels = viewModel.currentTakeSnapshot.summary.uniqueChannels.map(String.init).joined(separator: ", ")
        return channels.isEmpty ? "None" : channels
    }

    private func currentTakeInlineLabeledValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.takeMetadataLabel)
            Text(value)
                .font(.takeMetadataValue)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var livePianoRoll: some View {
        if let liveTake = currentLiveTake {
            PianoRollView(
                take: liveTake,
                viewModel: viewModel,
                zoomLevel: .constant(0.0),
                isLive: true
            )
            .layoutPriority(1)
        }
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

}

#if os(iOS)
extension ContentView {
    @ToolbarContentBuilder
    func iPhoneSidebarToggleToolbar() -> some ToolbarContent {
        if UIDevice.current.userInterfaceIdiom == .phone,
           horizontalSizeClass == .compact {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    phoneNavigationSplitColumnVisibility = .doubleColumn
                    preferredCompactColumn = .sidebar
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Show Takes Sidebar")
                .help("Show Takes Sidebar")
            }
        }
    }

    @ToolbarContentBuilder
    func iOSAppActionsToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                beginSettingsPresentation()
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Preferences")

            Button {
                beginAboutPresentation()
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About")
        }
    }
}
#endif
