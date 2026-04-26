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

    init() {
        AppIdentifier.logBundleIdentifier()
    }

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
                .onOpenURL { url in
                    appState.receiveIncomingURL(url)
                }
                .onAppear {
#if os(macOS)
                    MenuPlacement.configureMainMenu()
#endif
                }
                #if os(iOS)
                .modifier(
                    IOSSettingsPresentationModifier(
                        appState: appState,
                        settings: settings,
                        modelContainer: modelContainer
                    )
                )
                #else
                .sheet(isPresented: $appState.isShowingSettings) {
                    SettingsView(appState: appState, settings: settings, onClose: {
                        appState.dismissSettings()
                    }, onLoadSampleTakes: {
                        appState.requestLoadSampleTakes()
                    })
                    .modelContainer(modelContainer)
                }
                #endif
                .sheet(isPresented: $appState.isShowingAbout) {
                    AboutView {
                        appState.isShowingAbout = false
                    }
                    #if os(macOS)
                    .interactiveDismissDisabled()
                    #endif
                }
                #if os(iOS)
                .modifier(
                    IPadHelpPresentationModifier(
                        isShowingHelp: $appState.isShowingHelp
                    )
                )
                #else
                .sheet(isPresented: $appState.isShowingHelp) {
                    HelpView {
                        appState.isShowingHelp = false
                    }
                }
                #endif
        }
        .modelContainer(modelContainer)
        .commands {
            CommandMenu("Take") {
                let state = appState.takeCommandState
                let takeID = state.takeID

                Button(currentTakeSpaceCommandTitle(for: state)) {
                    if state.isCurrentTakeSelected {
                        appState.requestTakeCommand(state.isCurrentTakeInProgress ? .endCurrentTake : .startCurrentTake)
                    } else if let takeID {
                        appState.requestTakeCommand(.togglePlayback(takeID))
                    }
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(!state.canPerformCurrentTakeShortcut && !state.canPerformTakeAction)

                Button("Cancel Take", role: .destructive) {
                    appState.requestTakeCommand(.cancelCurrentTake)
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!state.canPerformCurrentTakeAction)

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

                Button("Reset Zoom") {
                    if let takeID {
                        appState.requestTakeCommand(.resetZoom(takeID))
                    }
                }
                .keyboardShortcut("0", modifiers: [.command])
                .disabled(!state.canPerformTakeAction || !state.canZoom)

                Divider()

                Button(state.isStarred ? "Unstar" : "Star") {
                    if let takeID {
                        appState.requestTakeCommand(.toggleStar(takeID))
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!state.canPerformTakeAction)

                Button("Duplicate Take") {
                    if let takeID {
                        appState.requestTakeCommand(.duplicate(takeID))
                    }
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(!state.canPerformTakeAction)

                Button("Rename Take") {
                    if let takeID {
                        appState.requestTakeCommand(.rename(takeID))
                    }
                }
                .keyboardShortcut("r", modifiers: [])
                .disabled(!state.canRenameTake)

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

                Button("Import Take from MIDI File…") {
                    appState.requestMIDIImport()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(state.isActionInProgress)

                Divider()

                Button("Export Take as .mid…") {
                    if let takeID {
                        appState.requestTakeCommand(.export(takeID))
                    }
                }
                .disabled(!state.canPerformTakeAction)
            }

#if os(macOS)
            CommandGroup(replacing: .help) {
                Button {
                    appState.requestModalPresentation(.help)
                } label: {
                    Label("\(AppIdentifier.name) Help", systemImage: "lightbulb")
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button {
                    appState.requestModalPresentation(.settings)
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About \(AppIdentifier.name)") {
                    appState.requestModalPresentation(.about)
                }
            }
#else
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppIdentifier.name)") {
                    appState.requestModalPresentation(.about)
                }
            }
#endif
        }
    }
}

#if os(iOS)
private struct IOSSettingsPresentationModifier: ViewModifier {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    let modelContainer: ModelContainer

    func body(content: Content) -> some View {
        if BuildInfo.isPhone {
            content
                .sheet(isPresented: $appState.isShowingSettings) {
                    settingsView
                }
        } else {
            content
                .fullScreenCover(isPresented: $appState.isShowingSettings) {
                    settingsView
                }
        }
    }

    private var settingsView: some View {
        SettingsView(appState: appState, settings: settings, onClose: {
            appState.dismissSettings()
        }, onLoadSampleTakes: {
            appState.requestLoadSampleTakes()
        })
        .modelContainer(modelContainer)
    }
}

private struct IPadHelpPresentationModifier: ViewModifier {
    @Binding var isShowingHelp: Bool

    func body(content: Content) -> some View {
        if BuildInfo.isPhone {
            content
                .sheet(isPresented: $isShowingHelp) {
                    HelpView {
                        isShowingHelp = false
                    }
                }
        } else {
            content
                .fullScreenCover(isPresented: $isShowingHelp) {
                    HelpView {
                        isShowingHelp = false
                    }
                }
        }
    }
}
#endif

private func currentTakeSpaceCommandTitle(for state: TakeCommandState) -> String {
    if state.isCurrentTakeSelected {
        return state.isCurrentTakeInProgress ? "End Take" : "Start Take"
    }
    return state.isPlaying ? "Pause" : "Play"
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
