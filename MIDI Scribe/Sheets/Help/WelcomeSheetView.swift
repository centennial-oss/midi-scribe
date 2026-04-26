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

struct WelcomeSheetFlow: View {
    let kind: OnboardingPresentationKind
    let onClose: () -> Void

    @State private var selection = 0

    var body: some View {
        let panes = activePanes
        #if os(iOS)
        if BuildInfo.isPhone {
            PhoneWelcomeSheet(kind: kind, panes: panes, selection: $selection, onClose: onClose)
        } else {
            IPadMacWelcomeSheet(kind: kind, panes: panes, selection: $selection, onClose: onClose)
        }
        #elseif os(macOS)
        Group {
            IPadMacWelcomeSheet(kind: kind, panes: panes, selection: $selection, onClose: onClose)
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
        switch kind {
        case .welcome:
            return currentPaneCollection.onboardingPanes
        case .help:
            return currentPaneCollection.onboardingPanes.filter(\.isShownInHelp)
        }
    }

    private var currentPaneCollection: OnboardingPaneCollection {
        if BuildInfo.isPhone {
            return iPhoneOnboardingPaneCollection
        } else if BuildInfo.isPad {
            return iPadOnboardingPaneCollection
        } else {
            return macOSOnboardingPaneCollection
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
