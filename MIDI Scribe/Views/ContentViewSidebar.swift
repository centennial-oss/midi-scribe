//
//  ContentViewSidebar.swift
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
            if !shouldHideSidebarTopChromeDuringEdit {
                sidebarControls
                Divider()
                sidebarCurrentTakeRow
            }
            if !viewModel.starredTakes.isEmpty {
                SidebarList(
                    data: viewModel.starredTakes,
                    id: \.id,
                    selection: sidebarOptionalSelectionBinding,
                    header: SidebarListHeader(
                        title: "Starred Takes",
                        buttons: showsEditButtonInStarredHeader ? [sidebarEditButton] : []
                    ),
                    isMultiSelecting: isEditingList,
                    multiSelectedIDs: $starredBulkSelection,
                    disabledMultiSelectionIDs: recentBulkSelection
                ) { take in
                    sidebarTakeItem(take, item: .starredTake(take.id), asStarred: true)
                }
                .onMultiSelectionChange { selected in
                    starredBulkSelection = Set(selected.map(\.id))
                    syncBulkSelection()
                }
            }
            if !viewModel.recentTakes.isEmpty {
                SidebarList(
                    data: viewModel.recentTakes,
                    id: \.id,
                    selection: sidebarOptionalSelectionBinding,
                    header: SidebarListHeader(
                        title: "Recent Takes",
                        buttons: showsEditButtonInRecentHeader ? [sidebarEditButton] : []
                    ),
                    isMultiSelecting: isEditingList,
                    multiSelectedIDs: $recentBulkSelection,
                    disabledMultiSelectionIDs: starredBulkSelection
                ) { take in
                    sidebarTakeItem(take, item: .recentTake(take.id), asStarred: false)
                }
                .onMultiSelectionChange { selected in
                    recentBulkSelection = Set(selected.map(\.id))
                    syncBulkSelection()
                }
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
                .tint(.accentColor)
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
                .tint(.accentColor)
            }
            playbackOutputPicker
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
            allowsNestedInteractions: true,
            action: { selectSidebarItem(item) },
            content: {
                sidebarRow(for: take, asStarred: asStarred)
            }
        )
    }

    private func selectSidebarItem(_ item: ContentSidebarItem) {
        swipeRevealedSidebarItem = nil
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
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker("", selection: $viewModel.selectedPlaybackTarget) {
                Text("Speakers").tag(PlaybackOutputTarget.osSpeakers)
                ForEach(1...16, id: \.self) { channel in
                    Text("MIDI Channel \(channel)").tag(PlaybackOutputTarget.midiChannel(channel))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .tint(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(viewModel.isTakeActionInProgress)
    }

    @ViewBuilder
    func sidebarRow(for take: RecordedTakeListItem, asStarred: Bool) -> some View {
        let rowItem: ContentSidebarItem = asStarred ? .starredTake(take.id) : .recentTake(take.id)
        let isRowRevealed = swipeRevealedSidebarItem == rowItem
        let rowContent = HStack(spacing: 8) {
            Text(take.displayTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            if take.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            Spacer(minLength: 8)
            if swipeRevealedSidebarItem != rowItem {
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
        if isRowRevealed {
            revealedSidebarRow(rowContent, take: take)
        } else {
            swipeEnabledSidebarRow(rowContent, take: take, rowItem: rowItem)
        }
    }

    @ViewBuilder
    private func revealedSidebarRow<V: View>(_ rowContent: V, take: RecordedTakeListItem) -> some View {
        rowContent
            .contentShape(Rectangle())
            .contextMenu { sidebarRowContextMenu(for: take) }
        #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { sidebarRowSwipeActions(for: take) }
        #endif
    }

    @ViewBuilder
    private func swipeEnabledSidebarRow<V: View>(
        _ rowContent: V,
        take: RecordedTakeListItem,
        rowItem: ContentSidebarItem
    ) -> some View {
        rowContent
            .contentShape(Rectangle())
            .simultaneousGesture(sidebarRowSwipeGesture(for: rowItem))
            .onTrackpadSwipe(
                onSwipeLeft: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeRevealedSidebarItem = rowItem
                    }
                },
                onSwipeRight: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if swipeRevealedSidebarItem == rowItem {
                            swipeRevealedSidebarItem = nil
                        }
                    }
                }
            )
            .contextMenu { sidebarRowContextMenu(for: take) }
        #if os(iOS)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) { sidebarRowSwipeActions(for: take) }
        #endif
    }

    private func sidebarRowSwipeGesture(for rowItem: ContentSidebarItem) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                if value.translation.width < -40 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeRevealedSidebarItem = rowItem
                    }
                } else if value.translation.width > 40 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if swipeRevealedSidebarItem == rowItem {
                            swipeRevealedSidebarItem = nil
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
            swipeRevealedSidebarItem = nil
            beginDeleteTake(id: take.id)
        } label: {
            Image(systemName: "trash")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.red)
        }
        .disabled(actionsDisabled)
        .tint(.clear)
        Button {
            swipeRevealedSidebarItem = nil
            beginRename(take)
        } label: {
            Image(systemName: "pencil")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.blue)
        }
        .disabled(actionsDisabled)
        .tint(.clear)
        Button {
            swipeRevealedSidebarItem = nil
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

    private var showsEditButtonInStarredHeader: Bool {
        showsSidebarEditButton && !viewModel.starredTakes.isEmpty
    }

    private var showsEditButtonInRecentHeader: Bool {
        showsSidebarEditButton && viewModel.starredTakes.isEmpty
    }

    private var shouldHideSidebarTopChromeDuringEdit: Bool {
        BuildInfo.isPhone && isEditingList
    }

}
