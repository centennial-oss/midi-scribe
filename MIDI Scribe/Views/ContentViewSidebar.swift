//
//  ContentView+Sidebar.swift
//  MIDI Scribe
//

import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ContentView {
    // MARK: - Sidebar

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarControls
            Divider()
            sidebarCurrentTakeRow

            if !viewModel.starredTakes.isEmpty {
                SidebarList(
                    data: viewModel.starredTakes,
                    id: \.id,
                    selection: sidebarOptionalSelectionBinding,
                    header: SidebarListHeader(title: "Starred Takes"),
                    isMultiSelecting: isEditingList
                ) { take in
                    sidebarTakeItem(take, item: .starredTake(take.id), asStarred: true)
                }
                .onMultiSelectionChange { selected in
                    viewModel.multiSelection = Set(selected.map(\.id))
                }
            }

            SidebarList(
                data: viewModel.recentTakes,
                id: \.id,
                selection: sidebarOptionalSelectionBinding,
                header: SidebarListHeader(
                    title: "Recent Takes",
                    buttons: showsSidebarEditButton ? [sidebarEditButton] : []
                ),
                isMultiSelecting: isEditingList
            ) { take in
                sidebarTakeItem(take, item: .recentTake(take.id), asStarred: false)
            }
            .onMultiSelectionChange { selected in
                viewModel.multiSelection = Set(selected.map(\.id))
            }

            if let pendingTakeOperation = viewModel.pendingOperation,
               pendingTakeOperation.shouldDisplayProgressNotice {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pendingTakeOperation.displayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

#if os(iOS)
            if showsNarrowiPhoneBulkEditActionRow {
                Color.clear
                    .frame(height: 84)
                    .accessibilityHidden(true)
            }
#endif
            Spacer(minLength: 0)
        }
        .onChange(of: viewModel.selectedSidebarItem) { _, newValue in
            if suppressNextSidebarAutoHide {
                suppressNextSidebarAutoHide = false
                return
            }
            if newValue != .editingTakes {
                isSidebarPresented = false
            }
        }
    }

    private var sidebarControls: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Scribing Enabled")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.isScribingEnabled },
                    set: { settings.disableScribing = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            HStack {
                Text("Mute Input")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { !settings.echoScribedToSpeakers },
                    set: { settings.echoScribedToSpeakers = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            playbackOutputPicker
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sidebarCurrentTakeRow: some View {
        SidebarItem(
            value: ContentSidebarItem.currentTake,
            isSelected: viewModel.selectedSidebarItem == .currentTake,
            action: { selectSidebarItem(.currentTake) },
            content: {
                HStack(spacing: 8) {
                    if !viewModel.isTakeInProgress {
                        Image(systemName: "movieclapper")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                    }
                    Text(viewModel.isTakeInProgress ? "Recording Take…" : "Start a New Take")
                    Spacer(minLength: 8)
                    if viewModel.isTakeInProgress {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption2)
                            .accessibilityLabel("Recording in progress")
                    }
                }
            }
        )
        .disabled(isEditingList)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .padding(.top, 12)
    }

    private var sidebarEditButton: SidebarButton {
        SidebarButton(
            context: SidebarButtonContext(
                action: { toggleEditMode() },
                accessibilityLabel: isEditingList ? "Done editing" : "Select multiple takes",
                systemImage: "checklist"
            ),
            isToggled: isEditingList
        )
    }

    private var sidebarOptionalSelectionBinding: Binding<ContentSidebarItem?> {
        Binding(
            get: { sidebarSelectionBinding.wrappedValue },
            set: { newValue in
                guard let newValue else { return }
                sidebarSelectionBinding.wrappedValue = newValue
            }
        )
    }

    private func sidebarTakeItem(
        _ take: RecordedTakeListItem,
        item: ContentSidebarItem,
        asStarred: Bool
    ) -> some View {
        SidebarItem(
            value: take.id,
            isSelected: !isEditingList && viewModel.selectedSidebarItem == item,
            action: { selectSidebarItem(item) },
            content: {
                sidebarRow(for: take, asStarred: asStarred)
            }
        )
    }

    private func selectSidebarItem(_ item: ContentSidebarItem) {
        swipeRevealedTakeID = nil
        prepareCompletedTakeDetailForSelection(item)
        sidebarSelectionBinding.wrappedValue = item
        if item != .editingTakes {
            isSidebarPresented = false
        }
    }

    private func prepareCompletedTakeDetailForSelection(_ item: ContentSidebarItem) {
        guard takeID(fromAny: item) != nil else { return }
        completedTakeReadyToRenderID = nil
        completedTakeRenderDelayRequestID += 1
    }

    @ViewBuilder
    private var playbackOutputPicker: some View {
        HStack(spacing: 12) {
            Text("Playback to")
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Picker("", selection: $viewModel.selectedPlaybackTarget) {
                Text("Speakers").tag(PlaybackOutputTarget.osSpeakers)
                ForEach(1...16, id: \.self) { channel in
                    Text("MIDI Channel \(channel)").tag(PlaybackOutputTarget.midiChannel(channel))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(viewModel.isTakeActionInProgress)
    }

    @ViewBuilder
    func sidebarRow(for take: RecordedTakeListItem, asStarred: Bool) -> some View {
        HStack(spacing: 8) {
            Text(take.displayTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            if take.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            Spacer(minLength: 8)
            if swipeRevealedTakeID != take.id {
                Text(viewModel.completedTakeDurationText(take))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                sidebarRowQuickActions(for: take)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(sidebarRowSwipeGesture(for: take.id))
        .onTrackpadSwipe(
            onSwipeLeft: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    swipeRevealedTakeID = take.id
                }
            },
            onSwipeRight: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if swipeRevealedTakeID == take.id {
                        swipeRevealedTakeID = nil
                    }
                }
            }
        )
        .contextMenu { sidebarRowContextMenu(for: take) }

#if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) { sidebarRowSwipeActions(for: take) }
#endif
    }

    private func sidebarRowSwipeGesture(for takeID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.width < -40 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeRevealedTakeID = takeID
                    }
                } else if value.translation.width > 40 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if swipeRevealedTakeID == takeID {
                            swipeRevealedTakeID = nil
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private func sidebarRowContextMenu(for take: RecordedTakeListItem) -> some View {
        Button(take.isStarred ? "Unstar" : "Star") {
            viewModel.toggleStar(takeID: take.id)
        }
        .disabled(viewModel.isTakeActionInProgress)
        Button("Rename…") {
            beginRename(take)
        }
        .disabled(viewModel.isTakeActionInProgress)
        Divider()
        Button("Delete", role: .destructive) {
            beginDeleteTake(id: take.id)
        }
        .disabled(viewModel.isTakeActionInProgress)
    }

#if os(iOS)
    @ViewBuilder
    private func sidebarRowSwipeActions(for take: RecordedTakeListItem) -> some View {
        let actionsDisabled = viewModel.isTakeActionInProgress || isEditingList

        Button {
            swipeRevealedTakeID = nil
            beginDeleteTake(id: take.id)
        } label: {
            Image(systemName: "trash")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red)
        }
        .disabled(actionsDisabled)
        .tint(.clear)

        Button {
            swipeRevealedTakeID = nil
            beginRename(take)
        } label: {
            Image(systemName: "pencil")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.blue)
        }
        .disabled(actionsDisabled)
        .tint(.clear)

        Button {
            swipeRevealedTakeID = nil
            viewModel.toggleStar(takeID: take.id)
        } label: {
            Image(systemName: "star")
                .symbolRenderingMode(.palette)
                .foregroundStyle(take.isStarred ? .yellow : Color(UIColor.systemBackground))
        }
        .disabled(actionsDisabled)
        .tint(.clear)
    }
#endif

    private var showsSidebarEditButton: Bool {
        true
    }

    func toggleMultiSelection(_ id: UUID) {
        if viewModel.multiSelection.contains(id) {
            viewModel.multiSelection.remove(id)
        } else {
            viewModel.multiSelection.insert(id)
        }
        selectionAnchorID = id
    }

#if os(macOS)
    /// When the user single-clicks a sidebar row on macOS with the command or
    /// shift modifier held, also update `multiSelection` accordingly. This
    /// lets power users range-select / toggle-select without entering the
    /// Edit mode, while still allowing the List's built-in single selection
    /// to drive the detail pane. This runs after the List has updated the
    /// primary selection, so we read `NSEvent.modifierFlags` synchronously.
    func handleSelectionChangeForModifiers(old: ContentSidebarItem, new: ContentSidebarItem) {
        guard let tappedID = takeID(from: new) else { return }
        let flags = NSEvent.modifierFlags
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        guard command || shift else {
            if !isEditingList {
                viewModel.multiSelection = []
            }
            selectionAnchorID = tappedID
            return
        }

        if command {
            if viewModel.multiSelection.contains(tappedID) {
                viewModel.multiSelection.remove(tappedID)
            } else {
                viewModel.multiSelection.insert(tappedID)
            }
            selectionAnchorID = tappedID
        } else if shift {
            let anchor = selectionAnchorID ?? takeID(from: old) ?? tappedID
            let allIDs = viewModel.recentTakes.map(\.id)
            if let anchorIndex = allIDs.firstIndex(of: anchor),
               let targetIndex = allIDs.firstIndex(of: tappedID) {
                let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                viewModel.multiSelection = Set(allIDs[range])
            } else {
                viewModel.multiSelection = [tappedID]
            }
        }
    }

    func takeID(from item: ContentSidebarItem) -> UUID? {
        switch item {
        case .recentTake(let id), .starredTake(let id): return id
        default: return nil
        }
    }
#endif
}
