//
//  WelcomeSheetView.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func welcomeSheetContent(_ content: some View) -> some View {
        #if os(iOS)
        content
            .modifier(
                IPadWelcomePresentationModifier(
                    isPresentingWelcomeSheet: $isPresentingWelcomeSheet,
                    onDismiss: {
                        settings.markWelcomeSheetShown()
                    }
                )
            )
        #else
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
        #endif
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

#if os(iOS)
private struct IPadWelcomePresentationModifier: ViewModifier {
    @Binding var isPresentingWelcomeSheet: Bool
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if BuildInfo.isPhone {
            content
                .sheet(
                    isPresented: $isPresentingWelcomeSheet,
                    onDismiss: onDismiss,
                    content: {
                        WelcomeSheetView()
                    }
                )
        } else {
            content
                .fullScreenCover(
                    isPresented: $isPresentingWelcomeSheet,
                    onDismiss: onDismiss,
                    content: {
                        WelcomeSheetView()
                    }
                )
        }
    }
}
#endif

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

private let onboardingPanes: [OnboardingPane] = [
    OnboardingPane(
        id: 0,
        content: .message(.welcome),
        isShownInHelp: false
    ),
    OnboardingPane(
        id: 1,
        title: "Live Capture",
        content: .screenshot(
            .liveTake,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-live-start",
                    sourceX: 520,
                    sourceY: 1080,
                    label: "Start a Take from here. When recording begins, this becomes the live capture view.",
                    caretPosition: .bottom
                ),
                OnboardingAnnotation(
                    id: "phone-live-roll",
                    sourceX: 1760,
                    sourceY: 420,
                    label: "The piano roll fills in as you play. Live capture is read-only.",
                    caretPosition: .top
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-live-start",
                    sourceX: 620,
                    sourceY: 1740,
                    label: "Start a Take here, from the Take menu, or with your configured shortcut.",
                    caretPosition: .bottom
                ),
                OnboardingAnnotation(
                    id: "regular-live-roll",
                    sourceX: 1850,
                    sourceY: 760,
                    label: "The piano roll fills in live as MIDI arrives.",
                    caretPosition: .top
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 2,
        title: "Ending a Take",
        content: .screenshot(
            .liveTake,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-live-stop",
                    sourceX: 1420,
                    sourceY: 1095,
                    label: "Stop saves the Take. Trash cancels the recording without keeping it.",
                    caretPosition: .bottom
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-live-stop",
                    sourceX: 1320,
                    sourceY: 1780,
                    label: "Stop ends and saves the Take. Trash cancels the recording.",
                    caretPosition: .bottom
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 3,
        title: "Playback Controls",
        content: .screenshot(
            .playback,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-playback-controls",
                    sourceX: 1360,
                    sourceY: 1080,
                    label: "Use rewind, play or pause, and restart to review a saved Take.",
                    caretPosition: .bottom
                ),
                OnboardingAnnotation(
                    id: "phone-playback-playhead",
                    sourceX: 1780,
                    sourceY: 350,
                    label: "Tap in the roll to move the playhead. Drag its handle to scrub while paused.",
                    caretPosition: .top
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-playback-controls",
                    sourceX: 1500,
                    sourceY: 1760,
                    label: "Playback controls let you rewind, play or pause, and restart.",
                    caretPosition: .bottom
                ),
                OnboardingAnnotation(
                    id: "regular-playback-playhead",
                    sourceX: 1900,
                    sourceY: 650,
                    label: "Click the roll to move the playhead. Drag the handle to scrub.",
                    caretPosition: .top
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 4,
        title: "Zooming the Piano Roll",
        content: .screenshot(
            .playback,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-playback-zoom",
                    sourceX: 2060,
                    sourceY: 575,
                    label: "Drag a rectangle across the piano roll to zoom into that region.",
                    caretPosition: .right
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-playback-zoom",
                    sourceX: 2100,
                    sourceY: 820,
                    label: "Drag across the piano roll to zoom into a selected region.",
                    caretPosition: .right
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 5,
        title: "Take Actions",
        content: .screenshot(
            .editing,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-edit-actions",
                    sourceX: 2360,
                    sourceY: 250,
                    label: "Rename, split at the playhead, star, or export the selected Take.",
                    caretPosition: .right
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-edit-actions",
                    sourceX: 480,
                    sourceY: 620,
                    label: "Per-Take actions include rename, split at the playhead, star, and export.",
                    caretPosition: .left
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 6,
        title: "Bulk Edit",
        content: .screenshot(
            .bulkEdit,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-bulk-actions",
                    sourceX: 1390,
                    sourceY: 1090,
                    label: "Bulk edit lets you select multiple Takes. Merge appears after two or more are selected.",
                    caretPosition: .bottom
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-bulk-actions",
                    sourceX: 560,
                    sourceY: 1640,
                    label: "Select multiple Takes to star, delete, or merge them together.",
                    caretPosition: .bottom
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 7,
        title: "Settings",
        content: .screenshot(
            .settings,
            OnboardingAnnotationSet(
            phone: [
                OnboardingAnnotation(
                    id: "phone-settings",
                    sourceX: 2230,
                    sourceY: 210,
                    label: "Settings controls recording triggers and app behavior.",
                    caretPosition: .top
                )
            ],
            regular: [
                OnboardingAnnotation(
                    id: "regular-settings",
                    sourceX: 2060,
                    sourceY: 420,
                    label: "Use Settings to tune recording triggers and MIDI Scribe behavior.",
                    caretPosition: .top
                )
            ]
        )
        )
    ),
    OnboardingPane(
        id: 8,
        content: .message(.happyScribing)
    )
]

struct WelcomeSheetFlow: View {
    let kind: OnboardingPresentationKind
    let onClose: () -> Void

    @State private var selection = 0

    var body: some View {
        let panes = activePanes
        #if os(iOS)
        if BuildInfo.isPhone {
            PhoneWelcomeSheet(
                kind: kind,
                panes: panes,
                selection: $selection,
                onClose: onClose
            )
        } else {
            IPadMacWelcomeSheet(
                kind: kind,
                panes: panes,
                selection: $selection,
                onClose: onClose
            )
        }
        #elseif os(macOS)
        Group {
            IPadMacWelcomeSheet(
                kind: kind,
                panes: panes,
                selection: $selection,
                onClose: onClose
            )
        }
        .onKeyPress(.escape) {
            guard kind == .help || selection == panes.count - 1 else {
                return .ignored
            }
            onClose()
            return .handled
        }
        #endif
    }

    private var activePanes: [OnboardingPane] {
        let visiblePanes = onboardingPanes.filter { !$0.isPaneHidden }
        switch kind {
        case .welcome:
            return visiblePanes
        case .help:
            return visiblePanes.filter(\.isShownInHelp)
        }
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
