//
//  ContentViewLastViewedTakePersistence.swift
//  MIDI Scribe
//

import Foundation

extension ContentView {
    private var lastViewedTakeDefaultsKey: String {
        "lastViewedTakeID"
    }

    func persistLastViewedTakeSelection(_ selection: ContentSidebarItem) {
        let defaults = UserDefaults.standard
        switch selection {
        case .recentTake(let id), .starredTake(let id):
            defaults.set(id.uuidString, forKey: lastViewedTakeDefaultsKey)
        case .currentTake:
            // Treat "Start a New Take" as clearing the "last viewed take."
            defaults.removeObject(forKey: lastViewedTakeDefaultsKey)
        case .organizing, .editingTakes:
            break
        }
    }

    func restoreLastViewedTakeIfNeeded() {
        guard !hasAttemptedLastViewedTakeRestore else { return }
        hasAttemptedLastViewedTakeRestore = true

        let defaults = UserDefaults.standard
        guard let idString = defaults.string(forKey: lastViewedTakeDefaultsKey),
              let takeID = UUID(uuidString: idString) else {
            return
        }

        guard viewModel.recentTake(id: takeID) != nil else {
            // Clear stale IDs that no longer exist in persistence.
            defaults.removeObject(forKey: lastViewedTakeDefaultsKey)
            return
        }

        guard viewModel.selectedSidebarItem == .currentTake else { return }
        viewModel.selectedSidebarItem = .recentTake(takeID)
    }
}
