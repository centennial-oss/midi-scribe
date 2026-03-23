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

    @Published var selectedSidebarItem: SidebarItem = .currentTake
    @Published private(set) var currentNoteText = ""
    @Published private(set) var currentChannelText = ""
    @Published private(set) var currentTakeSnapshot = CurrentTakeSnapshot(startedAt: nil, lastEventAt: nil, events: [])
    @Published private(set) var recentTakes: [RecordedTake] = []
    @Published private(set) var lastCompletedTake: RecordedTake?
    @Published private(set) var errorText: String?
    @Published var selectedPlaybackTarget: PlaybackOutputTarget = .osSpeakers

    let settings: AppSettings
    let emptyLiveValuePlaceholder = "—"
    let playbackEngine: MIDIPlaybackEngine

    private let monitor: MIDIListening
    private let takeLifecycle = TakeLifecycleController()
    private var durationTicker: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

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
                    self?.lastCompletedTake = take
                    self?.recentTakes.insert(take, at: 0)
                    self?.selectedSidebarItem = .recentTake(take.id)
                }
            }
        }

        settingsCancellable = settings.$disableScribing
            .removeDuplicates()
            .sink { [weak self] disableScribing in
                self?.handleScribingEnabledChanged(isEnabled: !disableScribing)
            }
    }

    func start() {
        do {
            try monitor.start()
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    func stop() {
        Task {
            await takeLifecycle.endCurrentTake()
        }
        monitor.stop()
    }

    func appWillTerminate() {
        stop()
    }

    func nextTake() {
        Task {
            await takeLifecycle.endCurrentTake()
        }
    }

    func endTake() {
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

    func recentTake(id: UUID) -> RecordedTake? {
        recentTakes.first { $0.id == id }
    }

    func completedTakeDurationText(_ take: RecordedTake) -> String {
        formatDuration(take.duration)
    }

    func completedTakeChannelsText(_ take: RecordedTake) -> String {
        let channels = take.summary.uniqueChannels.map(String.init).joined(separator: ", ")
        return channels.isEmpty ? "None" : channels
    }

    func completedTakeRangeText(_ take: RecordedTake) -> String {
        formatNoteRange(lowest: take.summary.lowestNote, highest: take.summary.highestNote)
    }

    func togglePlayback(for take: RecordedTake) {
        playbackEngine.togglePlayback(for: take, target: selectedPlaybackTarget)
    }

    func restartPlayback(for take: RecordedTake) {
        playbackEngine.restartPlayback(for: take, target: selectedPlaybackTarget)
    }

    func setRecentTakes(_ takes: [RecordedTake]) {
        recentTakes = takes
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
}
