//
//  ContentView+iOSToolbars.swift
//  MIDI Scribe
//

import SwiftUI

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

            if shouldShowAboutToolbarButton {
                Button {
                    beginAboutPresentation()
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About")
            }

            Button {
                beginHelpPresentation()
            } label: {
                Image(systemName: "lightbulb")
            }
            .help("Help")
            .accessibilityLabel("Help")
        }
    }

    private var shouldShowAboutToolbarButton: Bool {
        selectedSavedTakeID == nil
    }
}
#endif
