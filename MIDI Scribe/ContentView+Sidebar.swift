//
//  ContentView+Sidebar.swift
//  MIDI Scribe
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension ContentView {
    // MARK: - Sidebar

    var sidebar: some View {
        List(selection: sidebarSelectionBinding) {
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

            Divider()

            Text("Current Take")
                .tag(SidebarItem.currentTake)

            Text("Organizing")
                .tag(SidebarItem.organizing)

            if !viewModel.starredTakes.isEmpty {
                Section {
                    ForEach(viewModel.starredTakes) { take in
                        sidebarRow(for: take, asStarred: true)
                            .tag(SidebarItem.starredTake(take.id))
                    }
                } header: {
                    sectionHeader(title: "Starred")
                }
            }

            Section {
                ForEach(viewModel.recentTakes) { take in
                    sidebarRow(for: take, asStarred: false)
                        .tag(SidebarItem.recentTake(take.id))
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
    }

    @ViewBuilder
    func sidebarRow(for take: RecordedTakeListItem, asStarred: Bool) -> some View {
        HStack(spacing: 8) {
            if isEditingList {
                Button {
                    toggleMultiSelection(take.id)
                } label: {
                    Image(systemName: viewModel.multiSelection.contains(take.id)
                        ? "checkmark.circle.fill"
                        : "circle")
                        .font(.body)
                        .foregroundStyle(viewModel.multiSelection.contains(take.id)
                            ? Color.accentColor
                            : Color.secondary)
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
                pendingDeleteTakeID = take.id
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
                        .font(.caption)
                        .foregroundStyle(isEditingList ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isEditingList ? "Done editing" : "Select multiple takes")
                .padding(.trailing, 8)
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
