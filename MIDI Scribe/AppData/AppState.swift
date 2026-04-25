//
//  AppState.swift
//  MIDI Scribe
//

import Combine
import Foundation
#if os(macOS)
import AppKit
#endif

enum TakeCommandRequest: Equatable {
    case startCurrentTake
    case endCurrentTake
    case cancelCurrentTake
    case togglePlayback(UUID)
    case rewindPlayback(UUID)
    case restartPlayback(UUID)
    case split(UUID)
    case toggleStar(UUID)
    case rename(UUID)
    case export(UUID)
    case zoomIn(UUID)
    case zoomOut(UUID)
    case resetZoom(UUID)
    case delete(UUID)

    var takeID: UUID? {
        switch self {
        case .startCurrentTake,
             .endCurrentTake,
             .cancelCurrentTake:
            return nil
        case .togglePlayback(let takeID),
             .rewindPlayback(let takeID),
             .restartPlayback(let takeID),
             .split(let takeID),
             .toggleStar(let takeID),
             .rename(let takeID),
             .export(let takeID),
             .zoomIn(let takeID),
             .zoomOut(let takeID),
             .resetZoom(let takeID),
             .delete(let takeID):
            return takeID
        }
    }
}

struct TakeCommandState: Equatable {
    var takeID: UUID?
    var isCurrentTakeSelected = false
    var isCurrentTakeInProgress = false
    var isSavedTake = false
    var isPlaying = false
    var isStarred = false
    var canSplit = false
    var canZoom = false
    var isActionInProgress = false

    var canPerformTakeAction: Bool {
        isSavedTake && !isActionInProgress
    }

    var canRenameTake: Bool {
        canPerformTakeAction && !isPlaying
    }

    var canPerformCurrentTakeAction: Bool {
        isCurrentTakeInProgress && !isActionInProgress
    }

    var canPerformCurrentTakeShortcut: Bool {
        isCurrentTakeSelected && !isActionInProgress
    }
}

enum SampleTakeLoadResult: Equatable {
    case success(count: Int)
    case failure(message: String)
}

enum AppModalPresentationRequest: Equatable {
    case settings
    case about
    case help
}

@MainActor
final class AppState: ObservableObject {
    @Published var isShowingSettings = false
    @Published var isShowingAbout = false
    @Published var isShowingHelp = false
    @Published var sampleTakeLoadRequestID = UUID()
    @Published var sampleTakeLoadResult: SampleTakeLoadResult?
    @Published var isLoadingSampleTakes = false
    @Published var dataResetRequestID = UUID()
    @Published var midiImportRequestID = UUID()
    @Published var takeCommandState = TakeCommandState()
    @Published var takeCommandRequest: TakeCommandRequest?
    @Published var modalPresentationRequest: AppModalPresentationRequest?
    @Published private(set) var incomingURLRequestID = UUID()

    private(set) var pendingIncomingURL: URL?

#if os(macOS)
    private var keyDownMonitor: Any?

    init() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self,
                      !Self.isTextInputActive else { return false }
                return self.handleLocalKeyDown(event)
            }
            return handled ? nil : event
        }
    }

    deinit {
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

    func presentHelp() {
        isShowingHelp = true
    }

    func requestModalPresentation(_ request: AppModalPresentationRequest) {
        modalPresentationRequest = request
    }

    func requestLoadSampleTakes() {
        sampleTakeLoadResult = nil
        isLoadingSampleTakes = true
        sampleTakeLoadRequestID = UUID()
    }

    func reportSampleTakeLoadResult(_ result: SampleTakeLoadResult) {
        isLoadingSampleTakes = false
        sampleTakeLoadResult = result
    }

    func requestDataReset() {
        dataResetRequestID = UUID()
    }

    func requestMIDIImport() {
        midiImportRequestID = UUID()
    }

    func requestTakeCommand(_ request: TakeCommandRequest) {
        takeCommandRequest = request
    }

    func receiveIncomingURL(_ url: URL) {
#if DEBUG
        NSLog("[AppState] receiveIncomingURL: %@", url.absoluteString)
#endif
        pendingIncomingURL = url
        incomingURLRequestID = UUID()
    }

    func consumePendingIncomingURL() -> URL? {
        defer { pendingIncomingURL = nil }
        return pendingIncomingURL
    }

#if os(macOS)
    private static var isTextInputActive: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> Bool {
        if handleCurrentTakeShortcut(event) {
            return true
        }

        guard takeCommandState.canPerformTakeAction, let takeID = takeCommandState.takeID else { return false }

        if event.charactersIgnoringModifiers == " ",
           event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) {
            requestTakeCommand(.togglePlayback(takeID))
            return true
        }

        if handlePlainTakeShortcut(event, takeID: takeID) {
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.command] || flags == [.command, .shift] else { return false }

        switch event.charactersIgnoringModifiers {
        case "\u{F702}":
            requestTakeCommand(.rewindPlayback(takeID))
            return true
        case "=", "+":
            requestTakeCommand(.zoomIn(takeID))
            return true
        case "-":
            requestTakeCommand(.zoomOut(takeID))
            return true
        case "0":
            requestTakeCommand(.resetZoom(takeID))
            return true
        default:
            return false
        }
    }

    private func handleCurrentTakeShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
              takeCommandState.canPerformCurrentTakeShortcut else { return false }

        if event.charactersIgnoringModifiers == " " {
            requestTakeCommand(takeCommandState.isCurrentTakeInProgress ? .endCurrentTake : .startCurrentTake)
            return true
        }

        if event.keyCode == 53 {
            requestTakeCommand(.cancelCurrentTake)
            return true
        }

        return false
    }

    private func handlePlainTakeShortcut(_ event: NSEvent, takeID: UUID) -> Bool {
        guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else { return false }

        switch event.charactersIgnoringModifiers {
        case "/":
            guard takeCommandState.canSplit else { return false }
            requestTakeCommand(.split(takeID))
        case "s", "S":
            requestTakeCommand(.toggleStar(takeID))
        case "r", "R":
            guard takeCommandState.canRenameTake else { return false }
            requestTakeCommand(.rename(takeID))
        default:
            return false
        }

        return true
    }
#endif
}
