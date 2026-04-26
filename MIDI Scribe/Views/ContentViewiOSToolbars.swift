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
                Button {
                    isSidebarPresented = true
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .accessibilityLabel("Show Takes Sidebar")
                .help("Show Takes Sidebar")
            }
        }
    }

    @ToolbarContentBuilder
    func iOSImportToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                beginMIDIImportPresentation()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Import MIDI File")
            .help("Import MIDI File")
            .disabled(viewModel.isTakeActionInProgress)
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
                Image(systemName: "questionmark.circle")
            }
            .help("Help")
            .accessibilityLabel("Help")
        }
    }

    var shouldShowAboutToolbarButton: Bool {
        selectedSavedTakeID == nil
    }
}
#endif
