//
//  MIDILiveNoteViewModel.swift
//  MIDI Scribe
//

import Combine
import Foundation

@MainActor
final class MIDILiveNoteViewModel: ObservableObject {
    private static let idleTimeoutDisplayDelay: TimeInterval = 5
    static let monitorStartRetryDelays: [TimeInterval] = [1, 2, 5, 10, 15, 30]

    @Published var selectedSidebarItem: ContentSidebarItem = .currentTake {
        didSet {
            resetPlaybackIfDisplayedTakeChanged(old: oldValue, new: selectedSidebarItem)
        }
    }
    @Published var currentNoteText = ""
    @Published var currentChannelText = ""
    @Published var currentTakeSnapshot = CurrentTakeSnapshot.empty
    /// Incrementally-grown list of events in the take currently being
    /// recorded. Kept on the main actor so the live piano roll can render
    /// in real time without copying the full events array from the
    /// lifecycle actor on every note. Cleared when a take ends.
    @Published var liveTakeEvents: [RecordedMIDIEvent] = []
    /// When a take starts we stamp its id here so the live piano roll has
    /// a stable identity for `onChange(of: take.id)` hooks.
    @Published var liveTakeID: UUID = UUID()
    /// Time the first event for the live take was received.
    @Published var liveTakeStartedAt: Date?
    @Published var recentTakes: [RecordedTakeListItem] = []
    @Published var lastCompletedTake: RecordedTakeListItem?
    /// Lazy cache of fully-materialized takes (with events). Only populated
    /// when a take is actually played or inspected in detail.
    @Published var materializedTakes: [UUID: RecordedTake] = [:]
    var resolveFullTake: (@Sendable (UUID) -> RecordedTake?)?
    @Published var errorText: String?
    @Published var selectedPlaybackTarget: PlaybackOutputTarget {
        didSet {
            guard selectedPlaybackTarget != settings.selectedPlaybackTarget else { return }
            settings.selectedPlaybackTarget = selectedPlaybackTarget
        }
    }

    let settings: AppSettings
    let emptyLiveValuePlaceholder = "—"
    let playbackEngine: MIDIPlaybackEngine
    /// Injected by ContentView once the ModelContainer is available. All
    /// mutating take operations go through here so they run off the main
    /// thread.
    var persistenceService: TakePersistenceService?
    @Published var actionErrorText: String?
    /// Takes the user has multi-selected in the sidebar for bulk operations.
    @Published var multiSelection: Set<UUID> = []
    /// When non-nil, a background persistence operation is in progress.
    /// UI can use this to show a spinner and disable take actions.
    @Published var pendingOperation: TakeListPendingOperation?

    /// True while any mutating take operation is running. UI uses this to
    /// disable the playback/split/star/rename/delete controls and show a
    /// progress indicator.
    var isTakeActionInProgress: Bool { pendingOperation != nil }

    let monitor: MIDIListening
    let takeLifecycle = TakeLifecycleController()
    var durationTicker: AnyCancellable?
    var settingsCancellables: Set<AnyCancellable> = []
    var playbackEngineCancellable: AnyCancellable?
    var monitorRetryTask: Task<Void, Never>?
    var completedTakeSelectionMode: CompletedTakeSelectionMode = .showCompleted
    var hasStartedRecordableTake = false
    var suppressedTakeStartControlChange: UInt8?
    var materializingTakeIDs: Set<UUID> = []
    var playbackRequestAfterCurrentTakeEnds: DeferredPlaybackRequest?

    /// Most recent bulk-operation result. UI consumes this to decide which
    /// sidebar item to select after exiting Edit mode.
    @Published private(set) var lastBulkResult: TakeListBulkResult?

    init(settings: AppSettings, monitor: MIDIListening? = nil) {
        self.settings = settings
        self.playbackEngine = MIDIPlaybackEngine(settings: settings)
        self.selectedPlaybackTarget = settings.selectedPlaybackTarget

        let resolvedMonitor = monitor ?? CoreMIDIMonitor(settings: settings)
        self.monitor = resolvedMonitor
        wireMonitorCallbacks(resolvedMonitor)
        scheduleTakeLifecycleWiring()
        wirePlaybackAndSettings()
    }

    func start() {
        startMonitorWithRetry(resetBackoff: true)
    }

    func stop() {
        monitorRetryTask?.cancel()
        monitorRetryTask = nil
        Task {
            await takeLifecycle.endCurrentTake()
        }
        monitor.stop()
    }

    func startTake() {
        guard settings.isScribingEnabled else { return }
        completedTakeSelectionMode = .stayOnCurrent
        selectedSidebarItem = .currentTake
        Task {
            await takeLifecycle.ingestInput(at: Date(), timeout: settings.newTakePauseSeconds)
        }
    }

    func appWillTerminate() {
        stop()
    }

    func endTake() {
        completedTakeSelectionMode = .showCompleted
        Task {
            await takeLifecycle.endCurrentTake()
        }
    }

    func cancelTake() {
        completedTakeSelectionMode = .stayOnCurrent
        selectedSidebarItem = .currentTake
        Task {
            await takeLifecycle.discardCurrentTake()
        }
    }

    var isTakeInProgress: Bool {
        currentTakeSnapshot.isInProgress
    }

    var currentTakeDurationText: String {
        formatDuration(currentTakeSnapshot.startedAt.map { _ in currentTakeSnapshot.duration } ?? 0)
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

    var shouldShowIdleTimeoutText: Bool {
        guard currentTakeSnapshot.isInProgress, let lastEventAt = currentTakeSnapshot.lastEventAt else { return false }
        return Date().timeIntervalSince(lastEventAt) > Self.idleTimeoutDisplayDelay
    }

    var shouldShowCurrentNoteText: Bool {
        !currentNoteText.isEmpty && currentNoteText != emptyLiveValuePlaceholder
    }

    var idleTimeoutText: String {
        guard let lastEventAt = currentTakeSnapshot.lastEventAt else { return "" }
        let remaining = max(settings.newTakePauseSeconds - Date().timeIntervalSince(lastEventAt), 0)
        return "Idle Timeout in \(formatDuration(remaining))"
    }

    func recentTake(id: UUID) -> RecordedTakeListItem? {
        recentTakes.first { $0.id == id }
    }

    /// Starred subset of `recentTakes`, for the sidebar's "Starred" section.
    var starredTakes: [RecordedTakeListItem] {
        recentTakes.filter(\.isStarred)
    }

    /// Materialize (with events) a take on demand. Cached so repeated taps
    /// don't re-fault events from SwiftData.
    func fullTake(id: UUID) -> RecordedTake? {
        if let cached = materializedTakes[id] { return cached }
        guard let resolved = resolveFullTake?(id) else { return nil }
        materializedTakes[id] = resolved
        return resolved
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

    func setRecentTakes(_ takes: [RecordedTakeListItem]) {
        recentTakes = takes
        // Drop cached full takes that are no longer in the list so memory
        // doesn't grow unbounded with deleted rows.
        let validIDs = Set(takes.map(\.id))
        materializedTakes = materializedTakes.filter { validIDs.contains($0.key) }

        if lastCompletedTake == nil {
            lastCompletedTake = takes.first
        } else if let lastCompletedTake, let refreshed = takes.first(where: { $0.id == lastCompletedTake.id }) {
            self.lastCompletedTake = refreshed
        }
    }

    func clearLastBulkResult() {
        lastBulkResult = nil
    }

    private func resetPlaybackIfDisplayedTakeChanged(old: ContentSidebarItem, new: ContentSidebarItem) {
        let oldTakeID = takeID(fromAny: old)
        let newTakeID = takeID(fromAny: new)
        guard oldTakeID != newTakeID, newTakeID != nil else { return }

        playbackEngine.stopAndReset()
    }

    private func takeID(fromAny item: ContentSidebarItem) -> UUID? {
        switch item {
        case .recentTake(let id), .starredTake(let id): return id
        default: return nil
        }
    }

    func recordMergedBulkResult(newTakeID: UUID, removedIDs: Set<UUID>) {
        lastBulkResult = .merged(newTakeID: newTakeID, removedIDs: removedIDs)
    }

    func recordDeletedBulkResult(removedIDs: Set<UUID>) {
        lastBulkResult = .deleted(removedIDs: removedIDs)
    }

    func recordStarredBulkResult(affectedIDs: Set<UUID>) {
        lastBulkResult = .starred(affectedIDs: affectedIDs)
    }

    // MARK: - Private setup

    private func wireMonitorCallbacks(_ resolvedMonitor: MIDIListening) {
        resolvedMonitor.onActiveNotesChanged = { [weak self] notes in
            guard let self else { return }
            let text: String
            if notes.isEmpty {
                text = self.emptyLiveValuePlaceholder
            } else {
                text = notes.map(\.displayName).joined(separator: ", ")
            }
            self.currentNoteText = text
        }
        resolvedMonitor.onActiveChannelsChanged = { [weak self] channels in
            guard let self else { return }
            let text: String
            if channels.isEmpty {
                text = self.emptyLiveValuePlaceholder
            } else {
                text = channels.map { "Channel \($0)" }.joined(separator: ", ")
            }
            self.currentChannelText = text
        }
        resolvedMonitor.onEligibleInputReceived = { [weak self] receivedAt in
            self?.handleEligibleInput(receivedAt)
        }
        resolvedMonitor.onRecordedEventReceived = { [weak self] event in
            self?.handleRecordedEvent(event)
        }
    }

    private func scheduleTakeLifecycleWiring() {
        Task { [weak self] in
            guard let self else { return }
            await takeLifecycle.setOnSnapshotChanged { [weak self] snapshot in
                Task { @MainActor [weak self] in
                    self?.applyCurrentTakeSnapshot(snapshot)
                }
            }
            await takeLifecycle.setOnTakeCompleted { [weak self] take in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let listItem = RecordedTakeListItem(
                        id: take.id,
                        startedAt: take.startedAt,
                        endedAt: take.endedAt,
                        title: take.displayTitle,
                        baseTitle: take.displayTitle,
                        userTitle: nil,
                        isStarred: false,
                        summary: take.summary
                    )
                    self.materializedTakes[take.id] = take
                    self.lastCompletedTake = listItem
                    self.recentTakes.insert(listItem, at: 0)
                    self.handleCompletedTakeSelection(for: listItem)
                }
            }
            await takeLifecycle.setOnTakeDiscarded { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleDiscardedTake()
                }
            }
        }
    }

}

enum CompletedTakeSelectionMode {
    case showCompleted
    case stayOnCurrent
    case preserveSelection(ContentSidebarItem)
}

struct DeferredPlaybackRequest {
    let takeID: UUID
    let restart: Bool
    let target: PlaybackOutputTarget
}
