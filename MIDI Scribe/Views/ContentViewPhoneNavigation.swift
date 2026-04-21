//
//  ContentView+PhoneNavigation.swift
//  MIDI Scribe
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
#if os(iOS)
    func phoneFocusDetailColumnAfterSidebarSelection() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        preferredCompactColumn = .detail
        phoneNavigationSplitColumnVisibility = .detailOnly
    }

    /// When the sidebar column is visible beside detail (typical wide iPhone landscape),
    /// the top bar is too narrow for every trailing icon group.
    /// Hide the rename/split/star/export/delete cluster to avoid overflow (`...`).
    var hideTakeActionsToolbarOnPhone: Bool {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if phoneNavigationSplitColumnVisibility == .doubleColumn
            || phoneNavigationSplitColumnVisibility == .all {
            return true
        }
        if phoneNavigationSplitColumnVisibility == .automatic,
           preferredCompactColumn == .sidebar {
            return true
        }
        return false
    }
#endif
}
