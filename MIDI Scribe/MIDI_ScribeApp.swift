//
//  MIDI_ScribeApp.swift
//  MIDI Scribe
//
//  Created by James Ranson on 3/21/26.
//

import SwiftUI
import SwiftData

@main
struct MIDI_ScribeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .environmentObject(appState)
                .environmentObject(settings)
                .sheet(isPresented: $appState.isShowingSettings) {
                    SettingsView(settings: settings) {
                        appState.dismissSettings()
                    }
                }
        }
        .modelContainer(for: [StoredTake.self, StoredMIDIEvent.self])
#if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Divider()
                Button {
                    appState.presentSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
#endif
    }
}
