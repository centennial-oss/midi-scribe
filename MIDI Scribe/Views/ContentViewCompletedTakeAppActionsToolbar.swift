//
//  ContentView+CompletedTakeAppActionsToolbar.swift
//  MIDI Scribe
//

import SwiftUI

#if os(iOS)
extension ContentView {
    @ToolbarContentBuilder
    func completedTakeAppActionsToolbar() -> some ToolbarContent {
        if BuildInfo.isPhone {
            ToolbarItem(placement: completedTakeToolbarPlacement) {
                Menu {
                    Button {
                        beginSettingsPresentation()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }

                    if shouldShowAboutToolbarButton {
                        Button {
                            beginAboutPresentation()
                        } label: {
                            Label("About", systemImage: "info.circle")
                        }
                    }

                    Button {
                        beginHelpPresentation()
                    } label: {
                        Label("Help", systemImage: "questionmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("More")
                .help("More")
            }
        } else {
            iOSAppActionsToolbar()
        }
    }
}
#endif
