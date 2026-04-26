import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import CoreMIDI
import Foundation
import os

enum PlaybackOutputTarget: Hashable {
    case osSpeakers
    case midiChannel(Int)
}
@MainActor
final class MIDIPlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTakeID: UUID?
    @Published private(set) var currentTarget: PlaybackOutputTarget?
    @Published private(set) var pausedAtOffset: TimeInterval?
    var currentPlaybackTime: TimeInterval {
        if let pausedAtOffset { return pausedAtOffset }
        guard isPlaying, let playbackStartedAt else { return 0 }
        return playbackSegmentStartOffset + max(Date().timeIntervalSince(playbackStartedAt), 0)
    }

    private let settings: AppSettings
    var audioEngine = AVAudioEngine()
    var speakerInstrument: AVAudioUnitMIDIInstrument = AVAudioUnitSampler()
    private var settingsCancellable: AnyCancellable?
    var playbackTask: Task<Void, Never>?
    var playbackTake: RecordedTake?
    var playbackTarget: PlaybackOutputTarget = .osSpeakers
    var playbackResumeIndex = 0
    var playbackResumeOffset: TimeInterval = 0
    var playbackStartedAt: Date?
    var playbackSegmentStartOffset: TimeInterval = 0
    var outputClient = MIDIClientRef()
    var outputPort = MIDIPortRef()
    var speakerProgram: Int
    /// Serializes mutations to `speakerInstrument` / `audioEngine` (rebuilds, detaches,
    /// starts/stops) against `sendMIDIEvent` calls. The audio render thread dereferences
    /// state set up from the main thread; without this gate, tearing down the sampler
    /// while a scrub-driven `sendMIDIEvent` is still resolving can race with the
    /// IOThread.client callback and produce EXC_BAD_ACCESS crashes. os_unfair_lock is
    /// safe to acquire briefly from the main thread; we never hold it across awaits.
    var samplerLock = os_unfair_lock()
    /// `true` while the sampler is being replaced. While set, scrub-path sends are
    /// dropped rather than routed to a half-torn-down sampler.
    var samplerIsRebuilding = false
    /// Rolling counters for scrub-path drops, logged periodically in debug builds.
    var scrubDropReasons: [String: Int] = [:]
    var lastScrubDropLogUptime: TimeInterval = 0
    /// Observes `AVAudioEngineConfigurationChange`. When the OS changes the audio
    /// graph (output device change, sample rate change, another app taking exclusive
    /// audio, headphones plug/unplug, etc.), the engine is stopped and AUSampler
    /// state — including the loaded sound bank — can silently revert to defaults.
    /// Without re-loading the sound bank the sampler keeps rendering, but with the
    /// default/empty patch that users hear as "wrong instrument / bank 0".
    private var configurationChangeObserver: NSObjectProtocol?
    #if os(macOS)
    var lastSpeakerOutputDeviceID: AudioDeviceID?
    #endif
    init(settings: AppSettings) {
        self.settings = settings
        self.speakerProgram = settings.speakerOutputProgram
        #if DEBUG
        NSLog(
            "[SpeakerProgram] playback engine init " +
                "settingsProgram=\(settings.speakerOutputProgram) cachedProgram=\(speakerProgram)"
        )
        #endif
        configureAudio()
        configureMIDIOutput()
        observeAudioEngineConfigurationChanges()

        settingsCancellable = settings.$speakerOutputProgram
            .removeDuplicates()
            .sink { [weak self] program in
                #if DEBUG
                NSLog("[SpeakerProgram] settings publisher program=\(program)")
                #endif
                self?.speakerProgram = program
                self?.reloadInstrument()
            }
    }

    deinit {
        playbackTask?.cancel()
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if outputClient != 0 { MIDIClientDispose(outputClient) }
    }

    private func observeAudioEngineConfigurationChanges() {
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // The notification can arrive on a background thread. Hop to the main
            // actor before touching engine / sampler state.
            Task { @MainActor [weak self] in
                guard let self else { return }
                #if DEBUG
                NSLog(
                    "[SpeakerProgram] AVAudioEngineConfigurationChange " +
                        "program=\(self.speakerProgram) engineRunning=\(self.audioEngine.isRunning)"
                )
                #endif
                // Re-attach and re-load the sound bank so the sampler doesn't keep
                // rendering with a reset/default patch (symptom: "audio is bank 0").
                self.reloadInstrument()
            }
        }
    }
    func togglePlayback(for take: RecordedTake, target: PlaybackOutputTarget) {
        if isPlaying(take: take, target: target) {
            pause()
        } else {
            playOrResume(take: take, target: target)
        }
    }

    func isPlaying(take: RecordedTake, target: PlaybackOutputTarget) -> Bool {
        isPlaying && currentTakeID == take.id && currentTarget == target
    }

    func restartPlayback(for take: RecordedTake, target: PlaybackOutputTarget) {
        resetPlaybackPosition()
        playOrResume(take: take, target: target)
    }

    func rewindToBeginning(takeID: UUID? = nil) { pause(); resetPlaybackPosition(); currentTakeID = takeID }
    func playLiveEventToSpeakers(_ event: RecordedMIDIEvent) {
        guard settings.echoScribedToSpeakers else { return }
        playThroughSpeakers(event, allowRebuild: true)
    }

    func pause() {
        if isPlaying {
            captureResumePosition()
        }
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
        snapResumePositionToActiveNoteStart()
        pausedAtOffset = playbackResumeOffset > 0 ? playbackResumeOffset : nil
    }

    func stopAndReset() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
        resetPlaybackPosition()
    }

    func updatePausedOffset(to offset: TimeInterval, takeID: UUID? = nil) {
        let safeOffset = max(0, offset)
        if let takeID {
            currentTakeID = takeID
        }
        pausedAtOffset = safeOffset
        playbackResumeOffset = safeOffset
        if let playbackTake {
            playbackResumeIndex = firstEventIndex(in: playbackTake, atOrAfter: safeOffset)
        }
    }
    func activatePlaybackState(take: RecordedTake, target: PlaybackOutputTarget) {
        playbackTake = take; currentTakeID = take.id; currentTarget = target; playbackTarget = target
        isPlaying = true; pausedAtOffset = nil; playbackStartedAt = Date()
        playbackSegmentStartOffset = playbackResumeOffset
    }
    func playScrubEvent(_ event: RecordedMIDIEvent, target: PlaybackOutputTarget) {
        switch target {
        case .osSpeakers:
            playThroughSpeakers(event, allowRebuild: false)
        case .midiChannel(let channel):
            sendToMIDIDestinations(event, channelOverride: channel)
        }
    }
    func stopScrubbingNotes() { sendAllNotesOff() }

    func finishPlayback() {
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
        resetPlaybackPosition()
    }

    func resetPlaybackPosition() {
        playbackResumeIndex = 0
        playbackResumeOffset = 0
        playbackStartedAt = nil
        playbackSegmentStartOffset = 0
        playbackTake = nil
        currentTakeID = nil
        currentTarget = nil
        pausedAtOffset = nil
    }
}
