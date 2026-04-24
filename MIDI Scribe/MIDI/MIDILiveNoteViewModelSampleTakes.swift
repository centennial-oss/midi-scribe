//
//  MIDILiveNoteViewModel+SampleTakes.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    func loadSampleTakes() async -> Result<Int, Error> {
        guard pendingOperation == nil else {
            return .failure(SampleTakeLoadError.operationInProgress)
        }
        guard let persistenceService else {
            let message = "Storage is not ready yet."
            actionErrorText = message
            return .failure(SampleTakeLoadError.storageUnavailable)
        }

        pendingOperation = .loadingSamples
        actionErrorText = nil

        do {
            let insertedIDs = try await persistenceService.importSampleTakes(SampleMIDIFiles.all)
            pendingOperation = nil
            if let firstID = insertedIDs.first {
                selectedSidebarItem = .recentTake(firstID)
            }
            return .success(insertedIDs.count)
        } catch {
            pendingOperation = nil
            let message = "Unable to load sample takes: \(error.localizedDescription)"
            actionErrorText = message
            return .failure(error)
        }
    }
}

enum SampleTakeLoadError: LocalizedError {
    case operationInProgress
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .operationInProgress:
            return "Please wait for the current action to finish."
        case .storageUnavailable:
            return "Storage is not ready yet."
        }
    }
}
