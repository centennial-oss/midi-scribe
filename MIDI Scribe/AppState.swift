//
//  AppState.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

enum TakeCommandRequest: Equatable {
    case togglePlayback(UUID)
    case restartPlayback(UUID)
    case split(UUID)
    case toggleStar(UUID)
    case export(UUID)
    case zoomIn(UUID)
    case zoomOut(UUID)
    case delete(UUID)

    var takeID: UUID {
        switch self {
        case .togglePlayback(let takeID),
             .restartPlayback(let takeID),
             .split(let takeID),
             .toggleStar(let takeID),
             .export(let takeID),
             .zoomIn(let takeID),
             .zoomOut(let takeID),
             .delete(let takeID):
            return takeID
        }
    }
}

struct TakeCommandState: Equatable {
    var takeID: UUID?
    var isSavedTake = false
    var isPlaying = false
    var isStarred = false
    var canSplit = false
    var canZoom = false
    var isActionInProgress = false

    var canPerformTakeAction: Bool {
        isSavedTake && !isActionInProgress
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var isShowingSettings = false
    @Published var isShowingAbout = false
    /// True while ⌥ Option or ⌃ Control is held; reveals **File ▸ Load Sample Takes** (macOS). Control is an alternate so Option still works when the iOS Simulator uses it for multi-touch.
    @Published var isLoadSampleTakesMenuModifierActive = false
    @Published var sampleTakeLoadRequestID = UUID()
    @Published var takeCommandState = TakeCommandState()
    @Published var takeCommandRequest: TakeCommandRequest?

#if os(macOS)
    private var flagsMonitor: Any?
    private var keyDownMonitor: Any?

    init() {
        refreshModifierFlags()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.isLoadSampleTakesMenuModifierActive = Self.isLoadSampleTakesMenuRevealed(event.modifierFlags)
            }
            return event
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self,
                      !Self.isTextInputActive,
                      self.takeCommandState.canPerformTakeAction,
                      let takeID = self.takeCommandState.takeID else { return false }
                return self.handleLocalKeyDown(event, takeID: takeID)
            }
            return handled ? nil : event
        }
    }

    deinit {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }
#endif

    func presentSettings() {
        guard !isShowingSettings else { return }
        isShowingSettings = true
    }

    func dismissSettings() {
        isShowingSettings = false
    }

    func presentAbout() {
        isShowingAbout = true
    }

    func requestLoadSampleTakes() {
        sampleTakeLoadRequestID = UUID()
    }

    func requestTakeCommand(_ request: TakeCommandRequest) {
        takeCommandRequest = request
    }

#if os(macOS)
    func refreshModifierFlags() {
        isLoadSampleTakesMenuModifierActive = Self.isLoadSampleTakesMenuRevealed(NSEvent.modifierFlags)
    }

    private static func isLoadSampleTakesMenuRevealed(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) || flags.contains(.control)
    }

    private static var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func handleLocalKeyDown(_ event: NSEvent, takeID: UUID) -> Bool {
        if event.charactersIgnoringModifiers == " ",
           event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) {
            requestTakeCommand(.togglePlayback(takeID))
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command] || flags == [.command, .shift] else { return false }

        switch event.charactersIgnoringModifiers {
        case "=", "+":
            requestTakeCommand(.zoomIn(takeID))
            return true
        case "-":
            requestTakeCommand(.zoomOut(takeID))
            return true
        default:
            return false
        }
    }
#endif
}
