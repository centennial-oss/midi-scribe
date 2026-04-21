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
            .sheet(isPresented: $isPresentingWelcomeSheet) {
                WelcomeSheetView()
            }
    }

    func evaluateWelcomeSheetPresentationIfNeeded() {
        guard !hasEvaluatedWelcomeSheet else { return }
        hasEvaluatedWelcomeSheet = true

        guard !settings.hasWelcomeSheetShownValue else { return }

        settings.markWelcomeSheetShown()
        if storedRecentTakes.isEmpty {
            isPresentingWelcomeSheet = true
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
                Button("Get Started") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 520)
    }
}
