//
//  ContentView+DetailPane.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    @ViewBuilder
    var detailContent: some View {
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
            HStack(spacing: 20) {
                Button("Next Take") {
                    viewModel.nextTake()
                }
                .disabled(!viewModel.isTakeInProgress)

                Button("End Take") {
                    viewModel.endTake()
                }
                .disabled(!viewModel.isTakeInProgress)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Toggle("Echo Scribed Data To Speakers", isOn: $settings.echoScribedToSpeakers)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isTakeInProgress {
                currentTakeInProgressContent
            } else {
                currentTakeIdleContent
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
    }

    private var currentTakeIdleContent: some View {
        VStack(spacing: 20) {
            Text(viewModel.currentTakePromptText)
                .font(.title3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(viewModel.lastTakeSummaryText)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
