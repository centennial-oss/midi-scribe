//
//  AppState.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var isShowingSettings = false

    func presentSettings() {
        guard !isShowingSettings else { return }
        isShowingSettings = true
    }

    func dismissSettings() {
        isShowingSettings = false
    }
}
