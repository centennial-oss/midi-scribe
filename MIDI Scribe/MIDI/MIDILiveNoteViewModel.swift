//
//  MIDILiveNoteViewModel.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Combine
import Foundation

@MainActor
final class MIDILiveNoteViewModel: ObservableObject {
    private static let idleTimeoutDisplayDelay: TimeInterval = 5
    private static let monitorStartRetryDelays: [TimeInterval] = [1, 2, 5, 10, 15, 30]

    @Published var selectedSidebarItem: SidebarItem = .currentTake
    @Published private(set) var currentNoteText = ""
    @Published private(set) var currentChannelText = ""
    @Published private(set) var currentTakeSnapshot = CurrentTakeSnapshot.empty
    @Published private(set) var recentTakes: [RecordedTakeListItem] = []
    @Published private(set) var lastCompletedTake: RecordedTakeListItem?
    /// Lazy cache of fully-materialized takes (with events). Only populated
    /// when a take is actually played or inspected in detail.
    private var materializedTakes: [UUID: RecordedTake] = [:]
    var resolveFullTake: (@Sendable (UUID) -> RecordedTake?)?
    @Published private(set) var errorText: String?
    @Published var selectedPlaybackTarget: PlaybackOutputTarget = .osSpeakers

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
    @Published private(set) var pendingOperation: TakeOperation?

    enum TakeOperation: Equatable {
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

    /// True while any mutating take operation is running. UI uses this to
    /// disable the playback/split/star/rename/delete controls and show a
    /// progress indicator.
    var isTakeActionInProgress: Bool { pendingOperation != nil }

    private let monitor: MIDIListening
    private let takeLifecycle = TakeLifecycleController()
    private var durationTicker: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var playbackEngineCancellable: AnyCancellable?
    private var monitorRetryTask: Task<Void, Never>?
    private var completedTakeSelectionMode: CompletedTakeSelectionMode = .showCompleted

    init(settings: AppSettings, monitor: MIDIListening? = nil) {
        self.settings = settings
        self.playbackEngine = MIDIPlaybackEngine(settings: settings)

        let resolvedMonitor = monitor ?? CoreMIDIMonitor(settings: settings)
        self.monitor = resolvedMonitor
        self.monitor.onActiveNotesChanged = { [weak self] notes in
            self?.currentNoteText = notes.isEmpty ? self?.emptyLiveValuePlaceholder ?? "" : notes.map(\.displayName).joined(separator: ", ")
        }
        self.monitor.onActiveChannelsChanged = { [weak self] channels in
            self?.currentChannelText = channels.isEmpty ? self?.emptyLiveValuePlaceholder ?? "" : channels.map { "Channel \($0)" }.joined(separator: ", ")
        }
        self.monitor.onEligibleInputReceived = { [weak self] receivedAt in
            self?.handleEligibleInput(receivedAt)
        }
        self.monitor.onRecordedEventReceived = { [weak self] event in
            self?.handleRecordedEvent(event)
        }

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
        }

        playbackEngineCancellable = playbackEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        settingsCancellable = settings.$disableScribing
            .removeDuplicates()
            .sink { [weak self] disableScribing in
                self?.handleScribingEnabledChanged(isEnabled: !disableScribing)
            }
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

    func appWillTerminate() {
        stop()
    }

    func nextTake() {
        completedTakeSelectionMode = .stayOnCurrent
        Task {
            await takeLifecycle.endCurrentTake()
        }
    }

    func endTake() {
        completedTakeSelectionMode = .showCompleted
        Task {
            await takeLifecycle.endCurrentTake()
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
        return "Events: \(summary.eventCount)  Notes On/Off: \(summary.noteOnCount)/\(summary.noteOffCount)  Channels: \(channels.isEmpty ? "None" : channels)  Range: \(noteRangeText)"
    }

    var shouldShowIdleTimeoutText: Bool {
        guard currentTakeSnapshot.isInProgress, let lastEventAt = currentTakeSnapshot.lastEventAt else { return false }
        return Date().timeIntervalSince(lastEventAt) > Self.idleTimeoutDisplayDelay
    }

    var idleTimeoutText: String {
        guard let lastEventAt = currentTakeSnapshot.lastEventAt else { return "" }
        let remaining = max(settings.newTakePauseSeconds - Date().timeIntervalSince(lastEventAt), 0)
        return "Idle Timeout in \(formatDuration(remaining))"
    }

    var lastTakeSummaryText: String {
        guard let lastCompletedTake else { return "No completed takes recorded yet." }
        let summary = lastCompletedTake.summary
        let channels = summary.uniqueChannels.map(String.init).joined(separator: ", ")
        let noteRangeText = formatNoteRange(lowest: summary.lowestNote, highest: summary.highestNote)
        return "Last take: \(formatDuration(summary.duration)), \(summary.eventCount) events, channels \(channels.isEmpty ? "None" : channels), range \(noteRangeText)"
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

    func togglePlayback(for takeID: UUID) {
        if isPlaying(takeID: takeID) {
            playbackEngine.pause()
            return
        }
        loadFullTakeAndPlay(takeID: takeID, restart: false)
    }

    func restartPlayback(for takeID: UUID) {
        loadFullTakeAndPlay(takeID: takeID, restart: true)
    }

    private func loadFullTakeAndPlay(takeID: UUID, restart: Bool) {
        if let cached = materializedTakes[takeID] {
            if restart {
                playbackEngine.restartPlayback(for: cached, target: selectedPlaybackTarget)
            } else {
                playbackEngine.togglePlayback(for: cached, target: selectedPlaybackTarget)
            }
            return
        }

        let target = selectedPlaybackTarget
        let resolver = resolveFullTake
        Task { [weak self] in
            let take: RecordedTake? = await Task.detached(priority: .userInitiated) { [resolver] in
                resolver?(takeID)
            }.value

            guard let self, let take else { return }
            self.materializedTakes[takeID] = take
            if restart {
                self.playbackEngine.restartPlayback(for: take, target: target)
            } else {
                self.playbackEngine.togglePlayback(for: take, target: target)
            }
        }
    }

    func isPlaying(takeID: UUID) -> Bool {
        playbackEngine.currentTakeID == takeID && playbackEngine.isPlaying && playbackEngine.currentTarget == selectedPlaybackTarget
    }

    func deleteTake(id: UUID) {
        recentTakes.removeAll { $0.id == id }
        materializedTakes.removeValue(forKey: id)

        if lastCompletedTake?.id == id {
            lastCompletedTake = recentTakes.first
        }

        if case .recentTake(let selectedID) = selectedSidebarItem, selectedID == id {
            selectedSidebarItem = .currentTake
        }
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

    var currentTakePromptText: String {
        if !settings.isScribingEnabled {
            return "Enable scribing, then start playing your MIDI instrument \(monitoredChannelPrompt)to begin a new Take."
        }

        return "Start playing your MIDI instrument \(monitoredChannelPrompt)to begin a new Take."
    }

    private var monitoredChannelPrompt: String {
        if settings.monitoredMIDIChannel == AppSettings.midiChannelAllValue {
            return ""
        }

        return "on Channel \(settings.monitoredMIDIChannel) "
    }

    // MARK: - Mutating actions (star/rename/split/merge)

    /// True if there is a paused playback position that is strictly inside
    /// the take (not at the very start or end), so "Split Take Here" is
    /// meaningful.
    func canSplit(takeID: UUID) -> Bool {
        guard let take = recentTake(id: takeID) else { return false }
        guard playbackEngine.currentTakeID == takeID, !playbackEngine.isPlaying else { return false }
        guard let offset = playbackEngine.pausedAtOffset else { return false }
        return offset > 0.01 && offset < take.duration - 0.01
    }

    var pausedPlaybackOffset: TimeInterval? {
        playbackEngine.pausedAtOffset
    }

    func toggleStar(takeID: UUID) {
        guard let take = recentTake(id: takeID) else { return }
        let newValue = !take.isStarred
        // Optimistic local update so the sidebar reflects the change
        // immediately; ContentView only rebuilds from SwiftData on add/remove.
        updateListItem(id: takeID) { current in
            RecordedTakeListItem(
                id: current.id,
                startedAt: current.startedAt,
                endedAt: current.endedAt,
                title: current.title,
                baseTitle: current.baseTitle,
                userTitle: current.userTitle,
                isStarred: newValue,
                summary: current.summary
            )
        }
        runPersistence(operation: .starring) { service in
            try await service.setStarred(newValue, takeID: takeID)
        }
    }

    func renameTake(id takeID: UUID, to newName: String?) {
        let trimmed = newName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String? = (trimmed?.isEmpty ?? true) ? nil : trimmed
        updateListItem(id: takeID) { current in
            RecordedTakeListItem(
                id: current.id,
                startedAt: current.startedAt,
                endedAt: current.endedAt,
                title: resolved ?? current.baseTitle,
                baseTitle: current.baseTitle,
                userTitle: resolved,
                isStarred: current.isStarred,
                summary: current.summary
            )
        }
        runPersistence(operation: .renaming) { service in
            try await service.renameTake(id: takeID, to: newName)
        }
    }

    private func updateListItem(id takeID: UUID, transform: (RecordedTakeListItem) -> RecordedTakeListItem) {
        if let index = recentTakes.firstIndex(where: { $0.id == takeID }) {
            recentTakes[index] = transform(recentTakes[index])
        }
        if lastCompletedTake?.id == takeID, let last = lastCompletedTake {
            lastCompletedTake = transform(last)
        }
    }

    func deleteTakeViaPersistence(id takeID: UUID) {
        materializedTakes.removeValue(forKey: takeID)
        runPersistence(operation: .deleting) { service in
            try await service.deleteTake(id: takeID)
        }
    }

    func splitCurrentPausedTake() {
        guard let takeID = playbackEngine.currentTakeID,
              let offset = playbackEngine.pausedAtOffset,
              canSplit(takeID: takeID) else { return }
        // The take we're about to mutate is the same one the playback engine
        // thinks it's paused inside. Fully reset the engine so Play after the
        // split starts from offset 0 of the newly shortened first half
        // instead of the now-invalid pre-split offset.
        playbackEngine.stopAndReset()
        materializedTakes.removeValue(forKey: takeID)
        runPersistence(operation: .splitting) { service in
            _ = try await service.splitTake(id: takeID, at: offset)
        }
    }

    func mergeSelectedTakes(silenceBetweenMs: Int) {
        let ids = Array(multiSelection)
        guard ids.count >= 2 else { return }
        // If the playback engine is currently tied to one of the merged
        // takes (now deleted), reset it so Play on the new merged take is
        // fresh. Even if unrelated, resetting is safe.
        if let current = playbackEngine.currentTakeID, ids.contains(current) {
            playbackEngine.stopAndReset()
        }
        for id in ids { materializedTakes.removeValue(forKey: id) }
        multiSelection.removeAll()
        runPersistence(operation: .merging) { service in
            _ = try await service.mergeTakes(ids: ids, silenceBetweenMs: silenceBetweenMs)
        }
    }

    private func runPersistence(
        operation: TakeOperation,
        _ work: @escaping @Sendable (TakePersistenceService) async throws -> Void
    ) {
        guard let persistenceService else {
            actionErrorText = "Persistence service not available."
            return
        }
        guard pendingOperation == nil else {
            // Don't stack operations on top of each other.
            return
        }
        pendingOperation = operation
        actionErrorText = nil
        Task { [weak self] in
            do {
                try await work(persistenceService)
            } catch {
                await MainActor.run { [weak self] in
                    self?.actionErrorText = error.localizedDescription
                }
            }
            await MainActor.run { [weak self] in
                self?.pendingOperation = nil
            }
        }
    }

    private func handleEligibleInput(_ receivedAt: Date) {
        guard settings.isScribingEnabled else { return }
        Task {
            await takeLifecycle.ingestInput(at: receivedAt, timeout: settings.newTakePauseSeconds)
        }
    }

    private func handleRecordedEvent(_ event: RecordedMIDIEvent) {
        guard settings.isScribingEnabled else { return }
        playbackEngine.playLiveEventToSpeakers(event)
        Task {
            await takeLifecycle.appendEvent(event, timeout: settings.newTakePauseSeconds)
        }
    }

    private func handleScribingEnabledChanged(isEnabled: Bool) {
        if !isEnabled {
            currentNoteText = emptyLiveValuePlaceholder
            currentChannelText = emptyLiveValuePlaceholder

            Task {
                await takeLifecycle.endCurrentTake()
            }
        } else {
            startMonitorWithRetry(resetBackoff: true)
        }
    }

    private func applyCurrentTakeSnapshot(_ snapshot: CurrentTakeSnapshot) {
        currentTakeSnapshot = snapshot

        if snapshot.isInProgress {
            durationTicker?.cancel()
            durationTicker = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
        } else {
            durationTicker?.cancel()
            durationTicker = nil
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let elapsedSeconds = max(0, Int(duration))
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return "\(minutes)m \(seconds)s"
    }

    private func formatNoteRange(lowest: UInt8?, highest: UInt8?) -> String {
        switch (lowest, highest) {
        case let (lowest?, highest?):
            let lowNote = MIDINote(noteNumber: lowest, velocity: 0, channel: 1).displayName
            let highNote = MIDINote(noteNumber: highest, velocity: 0, channel: 1).displayName
            return lowest == highest ? lowNote : "\(lowNote) - \(highNote)"
        default:
            return "None"
        }
    }

    private func handleCompletedTakeSelection(for take: RecordedTakeListItem) {
        switch completedTakeSelectionMode {
        case .showCompleted:
            selectedSidebarItem = .recentTake(take.id)
        case .stayOnCurrent:
            selectedSidebarItem = .currentTake
        }

        completedTakeSelectionMode = .showCompleted
    }

    private func startMonitorWithRetry(resetBackoff: Bool) {
        if resetBackoff {
            monitorRetryTask?.cancel()
            monitorRetryTask = nil
        }

        guard monitorRetryTask == nil else { return }

        monitorRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var attempt = 0

            while !Task.isCancelled {
                do {
                    try monitor.start()
                    errorText = nil
                    monitorRetryTask = nil
                    return
                } catch {
                    errorText = "MIDI input unavailable. Retrying... \(error.localizedDescription)"
                }

                let delay = Self.monitorStartRetryDelays[min(attempt, Self.monitorStartRetryDelays.count - 1)]
                attempt += 1
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            monitorRetryTask = nil
        }
    }
}

private enum CompletedTakeSelectionMode {
    case showCompleted
    case stayOnCurrent
}
