//
//  WelcomeSheetView.swift
//  MIDI Scribe
//
//  Created by Codex on 4/20/26.
//

import SwiftUI

extension ContentView {
    func welcomeSheetContent(_ content: some View) -> some View {
        content
            .sheet(
                isPresented: $isPresentingWelcomeSheet,
                onDismiss: {
                    settings.markWelcomeSheetShown()
                },
                content: {
                    WelcomeSheetView()
                }
            )
    }

    func evaluateWelcomeSheetPresentationIfNeeded() {
        guard !hasEvaluatedWelcomeSheet else { return }
        hasEvaluatedWelcomeSheet = true

        guard !settings.hasWelcomeSheetShownValue else { return }
        if storedRecentTakes.isEmpty {
            #if DEBUG
            NSLog("MIDI Scribe welcome debug: welcome sheet needs to be shown")
            #endif
            DispatchQueue.main.async {
                guard !settings.hasWelcomeSheetShownValue,
                      storedRecentTakes.isEmpty else { return }
                isPresentingWelcomeSheet = true
            }
        } else {
            settings.markWelcomeSheetShown()
        }
    }
}

private struct WelcomeSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to MIDI Scribe")
                .font(.title)
                .fontWeight(.semibold)

            Text("Record MIDI takes, review your performances, and keep the ones you want to revisit later.")
                .foregroundStyle(.secondary)

            Text("This placeholder copy will be replaced before release.")
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                BasicButton(
                    context: BasicButtonContext(action: { dismiss() }, label: "Get Started")
                )
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 520)
    }
}
