//
//  ContentViewBulkSelection.swift
//  MIDI Scribe
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension ContentView {
    func toggleMultiSelection(_ id: UUID) {
        if starredBulkSelection.contains(id) {
            starredBulkSelection.remove(id)
        } else if recentBulkSelection.contains(id) {
            recentBulkSelection.remove(id)
        } else {
            recentBulkSelection.insert(id)
        }
        syncBulkSelection()
        selectionAnchorID = id
    }

    func clearBulkSelection() {
        starredBulkSelection.removeAll()
        recentBulkSelection.removeAll()
        viewModel.multiSelection.removeAll()
    }

    func syncBulkSelection() {
        viewModel.multiSelection = starredBulkSelection.union(recentBulkSelection)
    }
}

#if os(macOS)
extension ContentView {
    func handleSelectionChangeForModifiers(old: ContentSidebarItem, new: ContentSidebarItem) {
        guard let tappedID = takeID(from: new) else { return }
        let flags = NSEvent.modifierFlags
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        guard command || shift else {
            if !isEditingList {
                clearBulkSelection()
            }
            selectionAnchorID = tappedID
            return
        }
        if command {
            toggleMultiSelection(tappedID)
        } else if shift {
            let anchor = selectionAnchorID ?? takeID(from: old) ?? tappedID
            let allIDs = viewModel.recentTakes.map(\.id)
            if let anchorIndex = allIDs.firstIndex(of: anchor),
               let targetIndex = allIDs.firstIndex(of: tappedID) {
                let range = min(anchorIndex, targetIndex) ... max(anchorIndex, targetIndex)
                recentBulkSelection = Set(allIDs[range]).subtracting(starredBulkSelection)
            } else {
                recentBulkSelection = starredBulkSelection.contains(tappedID) ? [] : [tappedID]
            }
            syncBulkSelection()
        }
    }

    func takeID(from item: ContentSidebarItem) -> UUID? {
        switch item {
        case .recentTake(let id), .starredTake(let id): return id
        default: return nil
        }
    }
}
#endif
