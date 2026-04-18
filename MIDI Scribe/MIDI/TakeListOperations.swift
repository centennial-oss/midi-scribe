//
//  TakeListOperations.swift
//  MIDI Scribe
//

import Foundation

enum TakeListPendingOperation: Equatable {
    case splitting
    case merging
    case renaming
    case starring
    case deleting

    var displayText: String {
        switch self {
        case .splitting: return "Splitting take…"
        case .merging: return "Merging takes…"
        case .renaming: return "Renaming take…"
        case .starring: return "Updating star…"
        case .deleting: return "Deleting take…"
        }
    }
}

enum TakeListBulkResult: Equatable {
    case merged(newTakeID: UUID, removedIDs: Set<UUID>)
    case deleted(removedIDs: Set<UUID>)
    case starred(affectedIDs: Set<UUID>)
}
