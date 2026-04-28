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
                    toolbarIconButton("Settings", systemImage: "gearshape", disabled: false, showTextLabel: true) {
                        beginSettingsPresentation()
                    }

                    if shouldShowAboutToolbarButton {
                        toolbarIconButton("About", systemImage: "info.circle", disabled: false, showTextLabel: true) {
                            beginAboutPresentation()
                        }
                    }

                    toolbarIconButton("Help", systemImage: "questionmark.circle", disabled: false, showTextLabel: true) {
                        beginHelpPresentation()
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Color.primary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
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
