//
//  TakeListOperations.swift
//  MIDI Scribe
//

import Foundation

enum TakeListPendingOperation: Equatable {
    case importing
    case splitting
    case duplicating
    case merging
    case renaming
    case starring
    case deleting
    case loadingSamples

    var displayText: String {
        switch self {
        case .importing: return "Importing MIDI file…"
        case .splitting: return "Splitting take…"
        case .duplicating: return "Duplicating take…"
        case .merging: return "Merging takes…"
        case .renaming: return "Renaming take…"
        case .starring: return "Updating star…"
        case .deleting: return "Deleting take…"
        case .loadingSamples: return "Loading sample takes…"
        }
    }

    var shouldDisplayProgressNotice: Bool {
        switch self {
        case .starring:
            false
        case .importing, .splitting, .duplicating, .merging, .renaming, .deleting, .loadingSamples:
            true
        }
    }
}

enum TakeListBulkResult: Equatable {
    case duplicated(newTakeID: UUID)
    case merged(newTakeID: UUID, removedIDs: Set<UUID>)
    case deleted(removedIDs: Set<UUID>)
    case starred(affectedIDs: Set<UUID>)
}
