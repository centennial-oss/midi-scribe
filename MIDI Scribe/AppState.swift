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

@MainActor
final class AppState: ObservableObject {
    @Published var isShowingSettings = false
    @Published var isOptionKeyPressed = false
    @Published var sampleTakeLoadRequestID = UUID()

#if os(macOS)
    private var flagsMonitor: Any?

    init() {
        refreshModifierFlags()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.isOptionKeyPressed = event.modifierFlags.contains(.option)
            }
            return event
        }
    }

    deinit {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
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

    func requestLoadSampleTakes() {
        sampleTakeLoadRequestID = UUID()
    }

#if os(macOS)
    func refreshModifierFlags() {
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
    }
#endif
}
