//
//  MIDILiveNoteViewModelDisplay.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    var currentTakeDurationText: String {
        formatDuration(currentTakeSnapshot.startedAt.map { _ in currentTakeSnapshot.duration } ?? 0)
    }

    var shouldShowIdleTimeoutText: Bool {
        guard currentTakeSnapshot.isInProgress, let lastEventAt = currentTakeSnapshot.lastEventAt else { return false }
        return Date().timeIntervalSince(lastEventAt) > Self.idleTimeoutDisplayDelay
    }

    var shouldShowCurrentNoteText: Bool {
        !currentNoteText.isEmpty && currentNoteText != emptyLiveValuePlaceholder
    }

    var shouldShowNowNoteText: Bool {
        if isDisplayingCompletedTake {
            guard let auditionNoteText else { return false }
            return !auditionNoteText.isEmpty
        }
        return shouldShowCurrentNoteText
    }

    var nowNoteText: String {
        if isDisplayingCompletedTake {
            return auditionNoteText ?? ""
        }
        return currentNoteText
    }

    var isDisplayingCompletedTake: Bool {
        switch selectedSidebarItem {
        case .recentTake, .starredTake:
            return true
        default:
            return false
        }
    }

    var idleTimeoutText: String {
        guard let lastEventAt = currentTakeSnapshot.lastEventAt else { return "" }
        let remaining = max(settings.newTakePauseSeconds - Date().timeIntervalSince(lastEventAt), 0)
        return "Idle Timeout in \(formatDuration(remaining))"
    }

    var currentTakeSummaryText: String {
        let summary = currentTakeSnapshot.summary
        let channels = summary.uniqueChannels.map(String.init).joined(separator: ", ")
        let noteRangeText = formatNoteRange(lowest: summary.lowestNote, highest: summary.highestNote)
        let channelLabel = channels.isEmpty ? "None" : channels
        return [
            "Notes: \(max(summary.noteOnCount, summary.noteOffCount))",
            "Range: \(noteRangeText)",
            "Channels: \(channelLabel)"
        ].joined(separator: "  ")
    }

    func completedTakeDurationText(_ take: RecordedTakeListItem) -> String {
        formatDuration(take.duration)
    }

    func completedTakeChannelsText(_ take: RecordedTakeListItem) -> String {
        let channels = take.summary.uniqueChannels.map(String.init).joined(separator: ", ")
        return channels.isEmpty ? "None" : channels
    }

    func completedTakeRangeText(_ take: RecordedTakeListItem) -> String {
        formatNoteRange(lowest: take.summary.lowestNote, highest: take.summary.highestNote)
    }
}
