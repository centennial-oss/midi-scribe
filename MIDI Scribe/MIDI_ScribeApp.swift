//
//  MIDI_ScribeApp.swift
//  MIDI Scribe
//
//  Created by James Ranson on 3/21/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct MIDIScribeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var settings = AppSettings()

    /// The app's shared SwiftData container. Created up front so we can pass
    /// it into sheets (which don't always inherit `.modelContainer` via the
    /// environment).
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: StoredTake.self, StoredMIDIEvent.self)
        } catch {
            fatalError("Unable to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView(settings: settings)
                .environmentObject(appState)
                .environmentObject(settings)
                .onAppear {
#if os(macOS)
                    MenuPlacement.configureMainMenu()
#endif
                }
                .sheet(isPresented: $appState.isShowingSettings) {
                    SettingsView(settings: settings, onClose: {
                        appState.dismissSettings()
                    }, onLoadSampleTakes: {
                        appState.requestLoadSampleTakes()
                    })
                    .modelContainer(modelContainer)
                }
                .sheet(isPresented: $appState.isShowingAbout) {
                    AboutView()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandMenu("Take") {
                let state = appState.takeCommandState
                let takeID = state.takeID

                Button(state.isPlaying ? "Pause" : "Play") {
                    if let takeID {
                        appState.requestTakeCommand(.togglePlayback(takeID))
                    }
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(!state.canPerformTakeAction)

                Button(state.isPlaying ? "Pause and Rewind to Beginning" : "Rewind to Beginning") {
                    if let takeID {
                        appState.requestTakeCommand(.rewindPlayback(takeID))
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!state.canPerformTakeAction)

                Button("Restart") {
                    if let takeID {
                        appState.requestTakeCommand(.restartPlayback(takeID))
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!state.canPerformTakeAction)

                Divider()

                Button("Split Take Here") {
                    if let takeID {
                        appState.requestTakeCommand(.split(takeID))
                    }
                }
                .keyboardShortcut("/", modifiers: [])
                .disabled(!state.canPerformTakeAction || !state.canSplit)

                Divider()

                Button("Zoom In") {
                    if let takeID {
                        appState.requestTakeCommand(.zoomIn(takeID))
                    }
                }
                .keyboardShortcut("+", modifiers: [.command])
                .disabled(!state.canPerformTakeAction || !state.canZoom)

                Button("Zoom Out") {
                    if let takeID {
                        appState.requestTakeCommand(.zoomOut(takeID))
                    }
                }
                .keyboardShortcut("-", modifiers: [.command])
                .disabled(!state.canPerformTakeAction || !state.canZoom)

                Divider()

                Button(state.isStarred ? "Unstar" : "Star") {
                    if let takeID {
                        appState.requestTakeCommand(.toggleStar(takeID))
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!state.canPerformTakeAction)

                Button("Delete Take", role: .destructive) {
                    if let takeID {
                        appState.requestTakeCommand(.delete(takeID))
                    }
                }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(!state.canPerformTakeAction)
            }

            CommandGroup(replacing: .newItem) {
                let state = appState.takeCommandState
                let takeID = state.takeID

                Button("Export Take as .mid…") {
                    if let takeID {
                        appState.requestTakeCommand(.export(takeID))
                    }
                }
                .disabled(!state.canPerformTakeAction)

#if os(macOS)
                if appState.isLoadSampleTakesMenuModifierActive {
                    Divider()
                    Button("Load Sample Takes") {
                        appState.requestLoadSampleTakes()
                    }
                }
#else
                Divider()
                Button("Load Sample Takes") {
                    appState.requestLoadSampleTakes()
                }
#endif
            }

#if os(macOS)
            CommandGroup(replacing: .appSettings) {
                Button {
                    appState.presentSettings()
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About MIDI Scribe") {
                    appState.presentAbout()
                }
            }
#else
            /// iOS maps the stock “Settings” / gear affordance to the system Settings app. Use a
            /// plain Text title so this command only runs `presentSettings()` (in-app sheet).
            CommandGroup(replacing: .appSettings) {
                Button {
                    appState.presentSettings()
                } label: {
                    Text("Preferences…")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About MIDI Scribe") {
                    appState.presentAbout()
                }
            }
#endif
        }
    }
}

#if os(macOS)
private enum MenuPlacement {
    static func configureMainMenu() {
        DispatchQueue.main.async {
            moveTakeMenuAfterEdit()
            configureFileMenuClose()
        }
    }

    private static func moveTakeMenuAfterEdit() {
            guard let mainMenu = NSApp.mainMenu,
                  let takeIndex = mainMenu.items.firstIndex(where: { $0.title == "Take" }),
                  let editIndex = mainMenu.items.firstIndex(where: { $0.title == "Edit" }) else {
                return
            }

            let takeItem = mainMenu.items[takeIndex]
            mainMenu.removeItem(takeItem)
            let updatedEditIndex = mainMenu.items.firstIndex(where: { $0.title == "Edit" }) ?? editIndex
            mainMenu.insertItem(takeItem, at: min(updatedEditIndex + 1, mainMenu.items.count))
    }

    private static func configureFileMenuClose() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }

        if let closeItem = fileMenu.items.first(where: { $0.title == "Close" }) {
            closeItem.target = NSApp
            closeItem.action = #selector(NSApplication.terminate(_:))
        }
    }
}
#endif
