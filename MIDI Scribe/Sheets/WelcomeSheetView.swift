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
            NSLog("[WelcomeSheet] welcome sheet needs to be shown")
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

enum OnboardingPresentationKind {
    case welcome
    case help

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to MIDI Scribe"
        case .help:
            return "MIDI Scribe Help"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "A quick tour of recording, playback, editing, and export."
        case .help:
            return "A quick reference for recording, playback, editing, and export."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome:
            return "Get Started"
        case .help:
            return "Close"
        }
    }
}

struct OnboardingPane: Identifiable, Hashable {
    enum ScreenshotSlot: String {
        case liveTake
        case playback
        case editing
        case bulkEdit
        case settings
    }

    let id: Int
    let eyebrow: String
    let title: String
    let body: String
    let bullets: [String]
    let screenshotSlot: ScreenshotSlot
}

private let onboardingPanes: [OnboardingPane] = [
    OnboardingPane(
        id: 0,
        eyebrow: "Live Capture",
        title: "Start and end a new Take",
        body: """
            Use the large Start a New Take button, the Take menu, or your configured shortcuts to begin
            recording. While a Take is in progress, the stop button ends it and the trash button cancels it.
            """,
        bullets: [
            "The piano roll fills in live as you play. During live capture it is read-only.",
            "Show the Start button, Stop button, and Cancel Take button in the screenshot.",
            "If you have alternate start methods configured in Settings, they appear under the Start button."
        ],
        screenshotSlot: .liveTake
    ),
    OnboardingPane(
        id: 1,
        eyebrow: "Playback",
        title: "Review and navigate a saved Take",
        body: """
            Select a saved Take from the sidebar to open playback mode. Use rewind, play or pause, restart,
            and the piano roll to inspect the performance before making changes. You can also drag across
            the piano roll to zoom into a selected region.
            """,
        bullets: [
            "Show the saved Take playback toolbar controls: rewind, play or pause, and restart.",
            "Clicking or tapping in the piano roll moves the playhead to that location.",
            "If playback is paused, dragging the Handle at the top of the playhead scrubs across the roll.",
            "Call out the new click or tap-drag zoom gesture: drag a rectangle across the piano roll to " +
                "zoom into that selected area."
        ],
        screenshotSlot: .playback
    ),
    OnboardingPane(
        id: 2,
        eyebrow: "Per-Take Actions",
        title: "Rename, split, and export",
        body: """
            Once a saved Take is selected, you can rename it, split it at the current playhead position,
            or export it as a MIDI file. These actions apply to the current Take only.
            """,
        bullets: [
            "Split Take Here depends on where the playhead is parked, so this pane should visually follow " +
                "the playback pane.",
            "Show the Rename Take, Split Take Here, and Export .mid actions on a saved Take.",
            "If it fits cleanly, mention that star and unstar are also available per-Take."
        ],
        screenshotSlot: .editing
    ),
    OnboardingPane(
        id: 3,
        eyebrow: "Bulk Actions",
        title: "Bulk edit and merge",
        body: """
            Enter bulk edit mode from the sidebar to select multiple Takes. Star and Delete work on any
            selection, while Merge only appears after at least two Takes are selected.
            """,
        bullets: [
            "On iPhone, show the floating bottom action row that appears during bulk edit mode.",
            "Call out that Merge is hidden until bulk edit mode is active and two or more Takes are selected.",
            "Star and Delete work here too, but Merge is the bulk-only action that needs the strongest " +
                "callout."
        ],
        screenshotSlot: .bulkEdit
    ),
    OnboardingPane(
        id: 4,
        eyebrow: "Settings",
        title: "Adjust how MIDI Scribe behaves",
        body: """
            Settings lets you configure recording triggers and other app behavior. Most controls are
            self-explanatory once opened, so this pane only needs a light tour.
            """,
        bullets: [
            "Show the Settings button location for the platform.",
            "If you want one annotation here, point to recording start options because they affect the " +
                "first pane.",
            "Use this final pane as the natural end of the lesson."
        ],
        screenshotSlot: .settings
    )
]

struct WelcomeSheetFlow: View {
    let kind: OnboardingPresentationKind
    let onClose: () -> Void

    @State private var selection = 0

    var body: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                PhoneWelcomeSheet(
                    kind: kind,
                    panes: onboardingPanes,
                    selection: $selection,
                    onClose: onClose
                )
            } else {
                IPadMacWelcomeSheet(
                    kind: kind,
                    panes: onboardingPanes,
                    selection: $selection,
                    onClose: onClose
                )
            }
            #else
            IPadMacWelcomeSheet(
                kind: kind,
                panes: onboardingPanes,
                selection: $selection,
                onClose: onClose
            )
            #endif
        }
        #if os(macOS)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        #endif
    }
}

struct WelcomeSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        WelcomeSheetFlow(kind: .welcome) {
            dismiss()
        }
        .interactiveDismissDisabled()
    }
}

#Preview("Welcome") {
    WelcomeSheetView()
}
