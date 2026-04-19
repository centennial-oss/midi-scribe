//
//  MIDILiveNoteViewModel+SampleTakes.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    func loadSampleTakes() {
        guard pendingOperation == nil else { return }
        guard let persistenceService else {
            actionErrorText = "Storage is not ready yet."
            return
        }

        pendingOperation = .loadingSamples
        actionErrorText = nil

        Task {
            do {
                let insertedIDs = try await persistenceService.importSampleTakes(SampleMIDIFiles.all)
                pendingOperation = nil
                if let firstID = insertedIDs.first {
                    selectedSidebarItem = .recentTake(firstID)
                }
            } catch {
                pendingOperation = nil
                actionErrorText = "Unable to load sample takes: \(error.localizedDescription)"
            }
        }
    }
}
