//
//  ContentView+CompletedTakeSupport.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func splitTakeLabel(for take: RecordedTakeListItem) -> String {
        let canSplit = viewModel.canSplit(takeID: take.id)
        let offsetText = formatOffset(viewModel.pausedPlaybackOffset ?? 0)
        return canSplit ? "Split Take Here (\(offsetText))" : "Split Take Here"
    }

#if os(iOS)
    var completedTakePhoneBleedInsets: EdgeInsets {
        UIDevice.current.userInterfaceIdiom == .phone
            ? EdgeInsets(
                top: 0,
                leading: hideTakeActionsToolbarOnPhone ? -10 : -30,
                bottom: 0,
                trailing: -20
            )
            : EdgeInsets()
    }
#endif
}

struct CompletedTakeSplitDialogModifier: ViewModifier {
    let parent: ContentView

    func body(content: Content) -> some View {
        parent.splitDialogContent(content)
    }
}
