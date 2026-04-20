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
        Group {
#if os(macOS)
            List(selection: sidebarSelectionBinding) {
                sidebarListRows
            }
#else
            List {
                sidebarListRows
            }
#endif
        }
    }

    /// Rows shared by macOS (`List(selection:)`) and iOS (plain `List` + tap targets).
    @ViewBuilder
    private var sidebarListRows: some View {
        // Use `Section` boundaries instead of a raw `Divider()` so UIKit List does not insert an extra
        // blank row between controls and "Current Take" (iPhone / iPad).
        Section {
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
        }

        Section {
            sidebarSelectableRow(item: .currentTake) {
                HStack(spacing: 8) {
                    Text("Current Take")
                    Spacer(minLength: 8)
                    if viewModel.isTakeInProgress {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption2)
                            .accessibilityLabel("Recording in progress")
                    }
                }
            }
        }

        if !viewModel.starredTakes.isEmpty {
            Section {
                ForEach(viewModel.starredTakes) { take in
                    sidebarSelectableRow(item: .starredTake(take.id)) {
                        sidebarRow(for: take, asStarred: true)
                    }
                }
            } header: {
                sectionHeader(title: "Starred")
            }
        }

        Section {
            ForEach(viewModel.recentTakes) { take in
                sidebarSelectableRow(item: .recentTake(take.id)) {
                    sidebarRow(for: take, asStarred: false)
                }
            }
        } header: {
            sectionHeader(title: "Recent Takes", showsEditButton: true)
        }

        if let pendingTakeOperation = viewModel.pendingOperation {
            Section {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pendingTakeOperation.displayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// `List(selection:content:)` exists on macOS; on iOS we drive the same `sidebarSelectionBinding`
    /// with buttons and a row background for the active row.
    @ViewBuilder
    private func sidebarSelectableRow<Content: View>(
        item: SidebarItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
#if os(macOS)
        content()
            .tag(item)
#else
        Button {
            let isReselectingSameRow = (viewModel.selectedSidebarItem == item)
            sidebarSelectionBinding.wrappedValue = item
#if os(iOS)
            // Re-selecting the active row does not change `onChange` / split state; `preferredCompactColumn`
            // may already be `.detail` while the sidebar is still visible. Bounce through `.sidebar` so
            // the split view always applies a transition back to the detail column.
            if !isEditingList {
                if isReselectingSameRow {
                    preferredCompactColumn = .sidebar
                    DispatchQueue.main.async {
                        preferredCompactColumn = .detail
                    }
                } else {
                    preferredCompactColumn = .detail
                }
            }
#endif
        } label: {
            content()
                // Plain `Button` only hit-tests the label’s intrinsic size; the row background spans the
                // full width, so taps on empty trailing space must still activate the row.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            (!isEditingList && viewModel.selectedSidebarItem == item)
                ? Color.accentColor.opacity(0.15)
                : Color.clear
        )
#endif
    }

    @ViewBuilder
    private var playbackOutputPicker: some View {
        Picker("Playback to", selection: $viewModel.selectedPlaybackTarget) {
            Text("Speakers").tag(PlaybackOutputTarget.osSpeakers)
            ForEach(1...16, id: \.self) { channel in
                Text("MIDI Channel \(channel)").tag(PlaybackOutputTarget.midiChannel(channel))
            }
        }
        .disabled(viewModel.isTakeActionInProgress)
    }

    @ViewBuilder
    func sidebarRow(for take: RecordedTakeListItem, asStarred: Bool) -> some View {
        HStack(spacing: 8) {
            if isEditingList {
                Button {
                    toggleMultiSelection(take.id)
                } label: {
                    RoundCheckbox(isOn: viewModel.multiSelection.contains(take.id)) {
                        EmptyView()
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isTakeActionInProgress)
                .help("Select for bulk merge")
            }

            Text(take.displayTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            if take.isStarred {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            Spacer(minLength: 8)
            Text(viewModel.completedTakeDurationText(take))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contextMenu {
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
    }

    @ViewBuilder
    func sectionHeader(title: String, showsEditButton: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            if showsEditButton {
                Button {
                    toggleEditMode()
                } label: {
                    Image(systemName: "pencil")
                        .font(.body)
                        .foregroundStyle(isEditingList ? Color.accentColor : Color.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isEditingList ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(isEditingList ? "Done editing" : "Select multiple takes")
                .padding(.trailing, 14)
            }
        }
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
    func handleSelectionChangeForModifiers(old: SidebarItem, new: SidebarItem) {
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

    func takeID(from item: SidebarItem) -> UUID? {
        switch item {
        case .recentTake(let id), .starredTake(let id): return id
        default: return nil
        }
    }
#endif
}
