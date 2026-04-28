//
//  ContentView+iOSToolbars.swift
//  MIDI Scribe
//

import SwiftUI

#if os(iOS)
extension ContentView {
    @ToolbarContentBuilder
    func iPhoneSidebarToggleToolbar() -> some ToolbarContent {
        if BuildInfo.isPhone {
            ToolbarItem(placement: .topBarLeading) {
                toolbarIconButton("Show Takes Sidebar", systemImage: "sidebar.left", disabled: false) {
                    isSidebarPresented = true
                }
            }
        }
    }

    @ToolbarContentBuilder
    func iOSImportToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            toolbarIconButton(
                "Import MIDI File",
                systemImage: "square.and.arrow.down",
                disabled: viewModel.isTakeActionInProgress
            ) {
                beginMIDIImportPresentation()
            }
        }
    }

    @ToolbarContentBuilder
    func iOSAppActionsToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            toolbarIconButton("Preferences", systemImage: "gearshape", disabled: false) {
                beginSettingsPresentation()
            }

            if shouldShowAboutToolbarButton {
                toolbarIconButton("About", systemImage: "info.circle", disabled: false) {
                    beginAboutPresentation()
                }
            }

            toolbarIconButton("Help", systemImage: "questionmark.circle", disabled: false) {
                beginHelpPresentation()
            }
        }
    }

    var shouldShowAboutToolbarButton: Bool {
        selectedSavedTakeID == nil
    }
}
#endif
