//
//  ContentViewCurrentTakeIdle.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    var currentTakeIdleContent: some View {
        VStack(spacing: 10) {
            if !viewModel.settings.isScribingEnabled {
                Text("Enable scribing in the sidebar to start a new Take.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            if viewModel.settings.isScribingEnabled {
                BasicButton(
                    context: BasicButtonContext(
                        action: viewModel.startTake,
                        label: "Start a New Take",
                        systemImage: "movieclapper",
                        size: .extraLarge
                    )
                )
                if !currentTakeStartMethods.isEmpty {
                    currentTakeStartMethodList
                }
                configureStartMethodsPrompt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var configureStartMethodsPrompt: some View {
        VStack(spacing: 8) {
            Text("Configure more ways to start a new Take in Settings")
                .font(currentTakeStartMethodFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
#if os(iOS)
            HStack(spacing: 6) {
                Text("Tap")
                Image(systemName: "square.and.arrow.down")
                Text("in the toolbar to import a Take from your files")
            }
            .font(currentTakeStartMethodFont)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 12)
#endif
        }
        .padding(.top, 12)
    }

    private var currentTakeStartMethodList: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Other ways to start a new Take:")
                    .font(currentTakeStartMethodFont)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
                ForEach(currentTakeStartMethods, id: \.self) { method in
                    Text("‣ \(method)")
                        .font(currentTakeStartMethodFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.95)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: true, vertical: false)
        }
        .multilineTextAlignment(.center)
    }

    private var currentTakeStartMethodFont: Font {
        .body
    }

    private var currentTakeStartMethods: [String] {
        var methods: [String] = []
        #if os(macOS)
        methods.append("Press the Space Bar")
        #endif
        methods.append(contentsOf: viewModel.currentTakeStartMethods)
        return methods
    }
}
