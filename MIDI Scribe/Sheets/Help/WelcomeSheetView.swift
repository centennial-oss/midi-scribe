//
//  WelcomeSheetView.swift
//  MIDI Scribe
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

extension ContentView {
    func welcomeSheetContent(_ content: some View) -> some View {
        #if os(iOS)
        content
            .modifier(
                IPadWelcomePresentationModifier(
                    isPresentingWelcomeSheet: $isPresentingWelcomeSheet,
                    onDismiss: {
                        appState.setWelcomeTourPresented(false)
                        settings.markWelcomeSheetShown()
                    }
                )
            )
            .onChange(of: isPresentingWelcomeSheet) { _, isPresented in
                appState.setWelcomeTourPresented(isPresented)
            }
        #else
        content
            .sheet(
                isPresented: $isPresentingWelcomeSheet,
                onDismiss: {
                    appState.setWelcomeTourPresented(false)
                    settings.markWelcomeSheetShown()
                },
                content: {
                    WelcomeSheetView()
                }
            )
            .onChange(of: isPresentingWelcomeSheet) { _, isPresented in
                appState.setWelcomeTourPresented(isPresented)
            }
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
                appState.setWelcomeTourPresented(true)
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
                .onKeyPress(.leftArrow) {
                    goBack(panes: panes)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    advance(panes: panes)
                    return .handled
                }
        } else {
            IPadMacWelcomeSheet(kind: kind, panes: panes, selection: $selection, onClose: onClose)
                .onKeyPress(.leftArrow) {
                    goBack(panes: panes)
                    return .handled
                }
                .onKeyPress(.rightArrow) {
                    advance(panes: panes)
                    return .handled
                }
        }
        #elseif os(macOS)
        IPadMacWelcomeSheet(kind: kind, panes: panes, selection: $selection, onClose: onClose)
            .background(
                WelcomeSheetKeyHandler(
                    onLeftArrow: {
                        goBack(panes: panes)
                    },
                    onRightArrow: {
                        advance(panes: panes)
                    },
                    onEscape: {
                        guard kind == .help || selection == panes.count - 1 else { return }
                        onClose()
                    }
                )
            )
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

    private func advance(panes: [OnboardingPane]) {
        guard selection < panes.count - 1 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selection += 1
        }
    }

    private func goBack(panes _: [OnboardingPane]) {
        guard selection > 0 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selection -= 1
        }
    }
}

#if os(macOS)
private struct WelcomeSheetKeyHandler: NSViewRepresentable {
    let onLeftArrow: () -> Void
    let onRightArrow: () -> Void
    let onEscape: () -> Void

    func makeNSView(context _: Context) -> WelcomeSheetKeyMonitorView {
        let view = WelcomeSheetKeyMonitorView()
        view.onLeftArrow = onLeftArrow
        view.onRightArrow = onRightArrow
        view.onEscape = onEscape
        view.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: WelcomeSheetKeyMonitorView, context _: Context) {
        nsView.onLeftArrow = onLeftArrow
        nsView.onRightArrow = onRightArrow
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: WelcomeSheetKeyMonitorView, coordinator _: ()) {
        nsView.stopMonitoring()
    }
}

private final class WelcomeSheetKeyMonitorView: NSView {
    var onLeftArrow: (() -> Void)?
    var onRightArrow: (() -> Void)?
    var onEscape: (() -> Void)?

    private var monitor: Any?

    func startMonitoring() {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
            guard event.modifierFlags.isDisjoint(with: blockedModifiers) else {
                return event
            }

            switch event.keyCode {
            case 123:
                self?.onLeftArrow?()
                return nil
            case 124:
                self?.onRightArrow?()
                return nil
            case 53:
                self?.onEscape?()
                return nil
            default:
                return event
            }
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
#endif

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
