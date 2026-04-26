import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import CoreMIDI
import Foundation
import os

// swiftlint:disable file_length
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
    private var audioEngine = AVAudioEngine()
    private var speakerInstrument: AVAudioUnitMIDIInstrument = AVAudioUnitSampler()
    private var settingsCancellable: AnyCancellable?
    var playbackTask: Task<Void, Never>?
    var playbackTake: RecordedTake?
    var playbackTarget: PlaybackOutputTarget = .osSpeakers
    var playbackResumeIndex = 0
    var playbackResumeOffset: TimeInterval = 0
    var playbackStartedAt: Date?
    var playbackSegmentStartOffset: TimeInterval = 0
    private var outputClient = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var speakerProgram: Int
    /// Serializes mutations to `speakerInstrument` / `audioEngine` (rebuilds, detaches,
    /// starts/stops) against `sendMIDIEvent` calls. The audio render thread dereferences
    /// state set up from the main thread; without this gate, tearing down the sampler
    /// while a scrub-driven `sendMIDIEvent` is still resolving can race with the
    /// IOThread.client callback and produce EXC_BAD_ACCESS crashes. os_unfair_lock is
    /// safe to acquire briefly from the main thread; we never hold it across awaits.
    private var samplerLock = os_unfair_lock()
    /// `true` while the sampler is being replaced. While set, scrub-path sends are
    /// dropped rather than routed to a half-torn-down sampler.
    private var samplerIsRebuilding = false
    /// Rolling counters for scrub-path drops, logged periodically in debug builds.
    private var scrubDropReasons: [String: Int] = [:]
    private var lastScrubDropLogUptime: TimeInterval = 0
    /// Observes `AVAudioEngineConfigurationChange`. When the OS changes the audio
    /// graph (output device change, sample rate change, another app taking exclusive
    /// audio, headphones plug/unplug, etc.), the engine is stopped and AUSampler
    /// state — including the loaded sound bank — can silently revert to defaults.
    /// Without re-loading the sound bank the sampler keeps rendering, but with the
    /// default/empty patch that users hear as "wrong instrument / bank 0".
    private var configurationChangeObserver: NSObjectProtocol?
    #if os(macOS)
    private var lastSpeakerOutputDeviceID: AudioDeviceID?
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
}
extension MIDIPlaybackEngine {
    private func configureAudio() {
        do {
            try rebuildSampler()
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try audioEngine.start()
            #if os(macOS)
            lastSpeakerOutputDeviceID = currentDefaultOutputDeviceID()
            #endif
        } catch {
            #if DEBUG
            NSLog("[MIDIPlayback] audio setup failed: \(error)")
            #endif
        }
    }
    private func reloadInstrument() {
        withSamplerRebuildGate {
            do {
                let wasRunning = audioEngine.isRunning
                if wasRunning {
                    catchObjC("audioEngine.stop") { self.audioEngine.stop() }
                }
                try rebuildSampler()
                if wasRunning {
                    catchObjC("audioEngine.start") {
                        do { try self.audioEngine.start() } catch {
                            #if DEBUG
                            NSLog("[MIDIPlayback] audio start failed: \(error)")
                            #endif
                        }
                    }
                }
            } catch {
                #if DEBUG
                NSLog("[MIDIPlayback] instrument reload failed: \(error)")
                #endif
            }
        }
    }

    func refreshSpeakerOutputRoute() {
        #if os(macOS)
        let deviceID = currentDefaultOutputDeviceID()
        guard deviceID != lastSpeakerOutputDeviceID else { return }
        lastSpeakerOutputDeviceID = deviceID
        withSamplerRebuildGate {
            do {
                sendAllNotesOff()
                catchObjC("audioEngine.stop") { self.audioEngine.stop() }
                audioEngine = AVAudioEngine()
                // NOTE: Don't pre-assign `speakerInstrument = AVAudioUnitSampler()`
                // here. `rebuildSampler()` creates its own new instrument and only
                // assigns it to `speakerInstrument` after `loadSoundBankInstrument`
                // succeeds. A pre-assigned, never-loaded sampler would otherwise
                // become the active instrument if the rebuild partially failed,
                // producing the "audio is bank 0" symptom.
                try rebuildSampler()
                catchObjC("audioEngine.start") {
                    do { try self.audioEngine.start() } catch {
                        #if DEBUG
                        NSLog("[MIDIPlayback] audio start failed: \(error)")
                        #endif
                    }
                }
            } catch {
                #if DEBUG
                NSLog("[MIDIPlayback] output route refresh failed: \(error)")
                #endif
            }
        }
        #elseif os(iOS)
        return
        #endif
    }

    /// Runs `body` with `samplerIsRebuilding` set so that concurrent scrub sends are
    /// dropped (and normal sends spin-wait briefly). Also holds `samplerLock` across
    /// the mutation, ensuring no in-flight `sendMIDIEvent` is running against the
    /// same sampler instance we're about to detach.
    private func withSamplerRebuildGate(_ body: () -> Void) {
        os_unfair_lock_lock(&samplerLock)
        samplerIsRebuilding = true
        os_unfair_lock_unlock(&samplerLock)
        body()
        os_unfair_lock_lock(&samplerLock)
        samplerIsRebuilding = false
        os_unfair_lock_unlock(&samplerLock)
    }

    private func catchObjC(_ label: String, _ block: () -> Void) {
        var caught: NSError?
        let didSucceed = MSCatchObjCException(block, &caught)
        if !didSucceed {
            NSLog(
                "[MIDIPlayback] caught \(label) exception " +
                    "error=\(caught?.localizedDescription ?? "nil")"
            )
        }
    }

    #if os(macOS)
    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr ? deviceID : nil
    }
    #endif
    private func resolvedSoundBankURL() throws -> URL { try SoundBankAssets.soundBankURL() }
    private func configureMIDIOutput() {
        let clientStatus = MIDIClientCreateWithBlock(
            "\(BuildInfo.appName) Playback" as CFString,
            &outputClient
        ) { _ in }
        guard clientStatus == noErr else { return }
        MIDIOutputPortCreate(outputClient, "\(BuildInfo.appName) Playback Port" as CFString, &outputPort)
    }

    func play(event: RecordedMIDIEvent, target: PlaybackOutputTarget) {
        switch target {
        case .osSpeakers:
            playThroughSpeakers(event, allowRebuild: true)
        case .midiChannel(let channel):
            sendToMIDIDestinations(event, channelOverride: channel)
        }
    }
    /// Routes a MIDI event to the internal AUSampler.
    ///
    /// - Parameter allowRebuild: When `true` (normal playback), the engine/sampler
    ///   may be rebuilt synchronously if it has become detached. When `false`
    ///   (scrub audition), we never rebuild — we simply drop the event. Scrub is
    ///   best-effort audio feedback and rebuilding the sampler while the user is
    ///   dragging the playhead is the most dangerous path: it tears down AUSampler
    ///   state that the IOThread.client render callback may still be referencing.
    private func playThroughSpeakers(_ event: RecordedMIDIEvent, allowRebuild: Bool) {
        guard !event.isPresetSelectionEvent else { return }
        guard let status = statusByte(for: event.kind, channel: Int(event.channel)) else { return }
        let data1 = event.data1 & 0x7F
        let data2 = (event.data2 ?? 0) & 0x7F

        os_unfair_lock_lock(&samplerLock)
        if samplerIsRebuilding {
            os_unfair_lock_unlock(&samplerLock)
            recordScrubDrop("rebuilding", allowRebuild: allowRebuild)
            return
        }
        let ready = speakerInstrumentIsReadyLocked(allowRebuild: allowRebuild)
        guard ready else {
            os_unfair_lock_unlock(&samplerLock)
            recordScrubDrop("notReady", allowRebuild: allowRebuild)
            return
        }
        let sampler = speakerInstrument
        sendMIDIEventSafely(to: sampler, status: status, data1: data1, data2: data2)
        os_unfair_lock_unlock(&samplerLock)
    }

    /// Calls `sendMIDIEvent` inside an Objective-C `@try`/`@catch`. AVAudioEngine /
    /// AUSampler occasionally raise `NSInternalInconsistencyException` when the
    /// engine state changes underneath a send (e.g. configuration change / output
    /// device switch during a scrub). Swift cannot catch these natively and they
    /// terminate the app; the bridging helper turns them into a no-op plus a log.
    private func sendMIDIEventSafely(
        to sampler: AVAudioUnitMIDIInstrument,
        status: UInt8,
        data1: UInt8,
        data2: UInt8
    ) {
        var caught: NSError?
        let didSucceed = MSCatchObjCException({
            sampler.sendMIDIEvent(status, data1: data1, data2: data2)
        }, &caught)
        if !didSucceed {
            NSLog(
                "[MIDIPlayback] caught sendMIDIEvent exception " +
                    "status=\(status) data1=\(data1) data2=\(data2) error=\(caught?.localizedDescription ?? "nil")"
            )
        }
    }

    private func recordScrubDrop(_ reason: String, allowRebuild: Bool) {
        guard !allowRebuild else { return }
        #if DEBUG
        scrubDropReasons[reason, default: 0] += 1
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastScrubDropLogUptime > 1.0, !scrubDropReasons.isEmpty {
            lastScrubDropLogUptime = now
            NSLog("[MIDIPlayback] scrub audition drops: \(scrubDropReasons)")
            scrubDropReasons.removeAll(keepingCapacity: true)
        }
        #endif
    }

    /// Must be called with `samplerLock` held.
    private func speakerInstrumentIsReadyLocked(allowRebuild: Bool) -> Bool {
        if speakerInstrument.engine === audioEngine, audioEngine.isRunning {
            return true
        }
        guard allowRebuild else { return false }
        samplerIsRebuilding = true
        os_unfair_lock_unlock(&samplerLock)
        let didSucceed = ensureSpeakerAudioReadyOutsideLock()
        os_unfair_lock_lock(&samplerLock)
        samplerIsRebuilding = false
        return didSucceed
    }
    private func sendToMIDIDestinations(_ event: RecordedMIDIEvent, channelOverride: Int) {
        guard outputPort != 0 else { return }
        guard let channelNibble = midiChannelNibble(for: channelOverride) else { return }
        var data = event.midiData
        guard !data.isEmpty else { return }
        data[0] = (data[0] & 0xF0) | channelNibble
        if data.count > 1 {
            for index in 1 ..< data.count {
                data[index] = data[index] & 0x7F
            }
        }
        let packetListSize = 1024
        let packetListPointer = UnsafeMutableRawPointer.allocate(
            byteCount: packetListSize,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { packetListPointer.deallocate() }
        let typedPacketListPointer = packetListPointer.bindMemory(to: MIDIPacketList.self, capacity: 1)
        data.withUnsafeBytes { bytes in
            let packetList = typedPacketListPointer
            let packet = MIDIPacketListInit(packetList)
            _ = MIDIPacketListAdd(
                packetList,
                packetListSize,
                packet,
                0,
                data.count,
                bytes.bindMemory(to: UInt8.self).baseAddress!
            )

            for destinationIndex in 0 ..< MIDIGetNumberOfDestinations() {
                MIDISend(outputPort, MIDIGetDestination(destinationIndex), packetList)
            }
        }
    }

    private func sendAllNotesOff() {
        for channel in 1...16 {
            sendControlChange(64, value: 0, on: channel)
            sendControlChange(66, value: 0, on: channel)
            sendControlChange(67, value: 0, on: channel)
            sendControlChange(120, value: 0, on: channel)
            sendControlChange(121, value: 0, on: channel)
            sendControlChange(123, value: 0, on: channel)
        }
    }

    private func captureResumePosition() {
        guard let playbackStartedAt else { return }
        playbackResumeOffset = playbackSegmentStartOffset + max(Date().timeIntervalSince(playbackStartedAt), 0)
        self.playbackStartedAt = nil
    }

    func finishPlayback() {
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
        resetPlaybackPosition()
    }

    func firstEventIndex(in take: RecordedTake, atOrAfter offset: TimeInterval) -> Int {
        take.events.firstIndex { $0.offsetFromTakeStart >= offset } ?? take.events.count
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

    func pedalReentryEvents(in take: RecordedTake, at offset: TimeInterval) -> [RecordedMIDIEvent] {
        let pedalControllers: Set<UInt8> = [64, 66, 67]
        var latestByChannelAndController: [UInt8: [UInt8: UInt8]] = [:]
        for event in take.events {
            if event.offsetFromTakeStart >= offset { break }
            guard event.kind == .controlChange, pedalControllers.contains(event.data1) else { continue }
            latestByChannelAndController[event.channel, default: [:]][event.data1] = event.data2 ?? 0
        }
        let now = Date()
        return latestByChannelAndController.keys.sorted().flatMap { channel in
            guard let ccValues = latestByChannelAndController[channel],
                  let channelNibble = midiChannelNibble(for: Int(channel))
            else { return [RecordedMIDIEvent]() }
            return pedalControllers.sorted().compactMap { controller in
                guard let value = ccValues[controller], value >= 64 else { return nil }
                return RecordedMIDIEvent(
                    receivedAt: now,
                    offsetFromTakeStart: offset,
                    kind: .controlChange,
                    channel: channel,
                    status: UInt8(0xB0 | channelNibble),
                    data1: controller,
                    data2: value
                )
            }
        }
    }

    private func rebuildSampler() throws {
        let wasAttached = speakerInstrument.engine === audioEngine
        if wasAttached {
            sendAllNotesOff()
            let previous = speakerInstrument
            catchObjC("audioEngine.disconnect/detach") {
                self.audioEngine.disconnectNodeInput(previous)
                self.audioEngine.disconnectNodeOutput(previous)
                self.audioEngine.detach(previous)
            }
        }
        let soundBankURL = try resolvedSoundBankURL()
        let newInstrument = AVAudioUnitSampler()
        catchObjC("audioEngine.attach/connect") {
            self.audioEngine.attach(newInstrument)
            self.audioEngine.connect(newInstrument, to: self.audioEngine.mainMixerNode, format: nil)
        }
        let program = UInt8(clamping: speakerProgram)
        let bankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let bankLSB = UInt8(kAUSampler_DefaultBankLSB)
        #if DEBUG
        NSLog(
            "[SpeakerProgram] loadSoundBankInstrument " +
                "program=\(program) bankMSB=\(bankMSB) bankLSB=\(bankLSB) url=\(soundBankURL.lastPathComponent)"
        )
        #endif
        do {
            try newInstrument.loadSoundBankInstrument(
                at: soundBankURL,
                program: program,
                bankMSB: bankMSB,
                bankLSB: bankLSB
            )
        } catch {
            // If loading failed, don't leave `newInstrument` attached as a silent /
            // default-patch sampler (which the user perceives as "wrong bank / bank
            // 0"). Detach it and rethrow so the caller knows the rebuild failed.
            catchObjC("audioEngine.detach (failed-load cleanup)") {
                self.audioEngine.disconnectNodeInput(newInstrument)
                self.audioEngine.disconnectNodeOutput(newInstrument)
                self.audioEngine.detach(newInstrument)
            }
            #if DEBUG
            NSLog("[MIDIPlayback] loadSoundBankInstrument failed program=\(program) error=\(error)")
            #endif
            throw error
        }
        // Belt-and-suspenders: explicitly pin the current program on the new sampler.
        // `loadSoundBankInstrument` should have done this, but AUSampler has been
        // observed to reset its program to 0 after engine-configuration changes on
        // recent OSes, so we re-send the program change explicitly.
        pinProgramChange(on: newInstrument, program: program)
        speakerInstrument = newInstrument
    }

    /// Emits an explicit bank-select + program-change sequence on the given sampler
    /// so its current program cannot drift to 0 because of an internal AU reset.
    private func pinProgramChange(on sampler: AVAudioUnitMIDIInstrument, program: UInt8) {
        let bankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let bankLSB = UInt8(kAUSampler_DefaultBankLSB)
        for channel in 0..<UInt8(16) {
            let controlChangeStatus: UInt8 = 0xB0 | channel
            let programChangeStatus: UInt8 = 0xC0 | channel
            catchObjC("sampler.sendMIDIEvent (pin program)") {
                sampler.sendMIDIEvent(controlChangeStatus, data1: 0, data2: bankMSB)   // CC#0  bank MSB
                sampler.sendMIDIEvent(controlChangeStatus, data1: 32, data2: bankLSB)  // CC#32 bank LSB
                sampler.sendMIDIEvent(programChangeStatus, data1: program, data2: 0)   // program change
            }
        }
    }

    private func sendControlChange(_ controller: UInt8, value: UInt8, on channel: Int) {
        guard let channelNibble = midiChannelNibble(for: channel) else { return }
        let status = UInt8(0xB0 | channelNibble)
        os_unfair_lock_lock(&samplerLock)
        if !samplerIsRebuilding, speakerInstrumentIsReadyLocked(allowRebuild: true) {
            sendMIDIEventSafely(to: speakerInstrument, status: status, data1: controller, data2: value)
        }
        os_unfair_lock_unlock(&samplerLock)

        let event = RecordedMIDIEvent(
            receivedAt: Date(),
            offsetFromTakeStart: 0,
            kind: .controlChange,
            channel: UInt8(channel),
            status: status,
            data1: controller,
            data2: value
        )
        sendToMIDIDestinations(event, channelOverride: channel)
    }

    private func midiChannelNibble(for channel: Int) -> UInt8? {
        guard (1...16).contains(channel) else { return nil }
        return UInt8(channel - 1)
    }

    private func statusByte(for kind: MIDIChannelEventKind, channel: Int) -> UInt8? {
        guard let channelNibble = midiChannelNibble(for: channel) else { return nil }
        let command: UInt8
        switch kind {
        case .noteOff:
            command = 0x80
        case .noteOn:
            command = 0x90
        case .polyphonicKeyPressure:
            command = 0xA0
        case .controlChange:
            command = 0xB0
        case .programChange:
            command = 0xC0
        case .channelPressure:
            command = 0xD0
        case .pitchBend:
            command = 0xE0
        }
        return command | channelNibble
    }

    /// Rebuild / restart path used by the normal playback send. Must NOT hold
    /// `samplerLock` when called, because `rebuildSampler()` itself takes it.
    private func ensureSpeakerAudioReadyOutsideLock() -> Bool {
        if speakerInstrument.engine !== audioEngine {
            do {
                try rebuildSampler()
            } catch {
                #if DEBUG
                NSLog("[MIDIPlayback] sampler rebuild failed: \(error)")
                #endif
                return false
            }
        }
        if !audioEngine.isRunning {
            var caught: NSError?
            let didSucceed = MSCatchObjCException({
                do {
                    try self.audioEngine.start()
                } catch {
                    #if DEBUG
                    NSLog("[MIDIPlayback] audio start failed: \(error)")
                    #endif
                }
            }, &caught)
            if !didSucceed {
                NSLog(
                    "[MIDIPlayback] caught audioEngine.start exception " +
                        "error=\(caught?.localizedDescription ?? "nil")"
                )
                return false
            }
        }
        return speakerInstrument.engine === audioEngine && audioEngine.isRunning
    }
}
