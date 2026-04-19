import AudioToolbox
import AVFoundation
import Combine
import CoreAudio
import CoreMIDI
import Foundation

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
    private var playbackTask: Task<Void, Never>?
    private var playbackTake: RecordedTake?
    private var playbackTarget: PlaybackOutputTarget = .osSpeakers
    private var playbackResumeIndex = 0
    private var playbackResumeOffset: TimeInterval = 0
    private var playbackStartedAt: Date?
    private var playbackSegmentStartOffset: TimeInterval = 0
    private var outputClient = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var speakerProgram: Int
    #if os(macOS)
    private var lastSpeakerOutputDeviceID: AudioDeviceID?
    #endif

    init(settings: AppSettings) {
        self.settings = settings
        self.speakerProgram = settings.speakerOutputProgram
        configureAudio()
        configureMIDIOutput()

        settingsCancellable = settings.$speakerOutputProgram
            .removeDuplicates()
            .sink { [weak self] program in
                self?.speakerProgram = program
                self?.reloadInstrument()
            }
    }

    deinit {
        playbackTask?.cancel()
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if outputClient != 0 { MIDIClientDispose(outputClient) }
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
        playThroughSpeakers(event)
    }

    func pause() {
        if isPlaying {
            captureResumePosition()
        }
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
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

    func playScrubEvent(_ event: RecordedMIDIEvent, target: PlaybackOutputTarget) { play(event: event, target: target) }

    func stopScrubbingNotes() { sendAllNotesOff() }
}
extension MIDIPlaybackEngine {
    private func playOrResume(take: RecordedTake, target: PlaybackOutputTarget) {
        if playbackTask != nil {
            pause()
        }
        if target == .osSpeakers { refreshSpeakerOutputRoute() }

        if currentTakeID != take.id || currentTarget != target {
            let preservedResumeOffset = playbackResumeOffset
            resetPlaybackPosition()
            if preservedResumeOffset > 0 {
                playbackResumeOffset = preservedResumeOffset
                playbackResumeIndex = firstEventIndex(in: take, atOrAfter: preservedResumeOffset)
            }
        }

        playbackTake = take
        currentTakeID = take.id
        currentTarget = target
        playbackTarget = target
        isPlaying = true
        pausedAtOffset = nil
        playbackStartedAt = Date()
        playbackSegmentStartOffset = playbackResumeOffset

        let events = take.events
        let startIndex = playbackResumeIndex
        let startOffset = playbackResumeOffset
        let playbackEpoch = Date().addingTimeInterval(-startOffset)
        let syntheticPedalDownEvents = pedalReentryEvents(in: take, at: startOffset)

        for event in syntheticPedalDownEvents {
            play(event: event, target: target)
        }

        playbackTask = Task { [weak self] in
            guard let self else { return }
            var immediateBurstCount = 0

            for index in startIndex ..< events.count {
                let event = events[index]
                let targetDate = playbackEpoch.addingTimeInterval(event.offsetFromTakeStart)
                let wait = targetDate.timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    immediateBurstCount = 0
                } else {
                    immediateBurstCount += 1
                    if immediateBurstCount >= 128 {
                        // Seeking into dense sections can enqueue many events at
                        // once; briefly yielding prevents a single-frame burst.
                        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                        immediateBurstCount = 0
                    }
                }
                if Task.isCancelled { return }

                await MainActor.run {
                    self.playbackResumeIndex = index + 1
                    self.playbackResumeOffset = event.offsetFromTakeStart
                    self.play(event: event, target: target)
                }
            }

            await MainActor.run {
                self.finishPlayback()
            }
        }
    }

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
            print("MIDI Scribe playback audio setup failed: \(error)")
        }
    }

    private func reloadInstrument() {
        do {
            let wasRunning = audioEngine.isRunning
            if wasRunning {
                audioEngine.stop()
            }
            try rebuildSampler()
            if wasRunning {
                try audioEngine.start()
            }
        } catch {
            print("MIDI Scribe playback instrument reload failed: \(error)")
        }
    }

    private func refreshSpeakerOutputRoute() {
        #if os(macOS)
        let deviceID = currentDefaultOutputDeviceID()
        guard deviceID != lastSpeakerOutputDeviceID else { return }
        lastSpeakerOutputDeviceID = deviceID
        do {
            sendAllNotesOff()
            audioEngine.stop()
            audioEngine = AVAudioEngine()
            speakerInstrument = AVAudioUnitSampler()
            try rebuildSampler()
            try audioEngine.start()
        } catch {
            print("MIDI Scribe playback output route refresh failed: \(error)")
        }
        #elseif os(iOS)
        // iOS routes are managed by AVAudioSession; rebuilding the sampler here can leave
        // playback silent after route checks that were introduced for macOS.
        return
        #endif
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
        let clientStatus = MIDIClientCreateWithBlock("MIDI Scribe Playback" as CFString, &outputClient) { _ in }
        guard clientStatus == noErr else { return }
        MIDIOutputPortCreate(outputClient, "MIDI Scribe Playback Port" as CFString, &outputPort)
    }

    private func play(event: RecordedMIDIEvent, target: PlaybackOutputTarget) {
        switch target {
        case .osSpeakers:
            playThroughSpeakers(event)
        case .midiChannel(let channel):
            sendToMIDIDestinations(event, channelOverride: channel)
        }
    }

    private func playThroughSpeakers(_ event: RecordedMIDIEvent) {
        guard event.kind != .programChange else { return }
        guard ensureSpeakerAudioReady() else { return }
        guard let status = statusByte(for: event.kind, channel: Int(event.channel)) else { return }
        let data1 = event.data1 & 0x7F
        let data2 = (event.data2 ?? 0) & 0x7F
        speakerInstrument.sendMIDIEvent(status, data1: data1, data2: data2)
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

        speakerInstrument.reset()
    }

    private func captureResumePosition() {
        guard let playbackStartedAt else { return }
        playbackResumeOffset = playbackSegmentStartOffset + max(Date().timeIntervalSince(playbackStartedAt), 0)
        self.playbackStartedAt = nil
    }

    private func finishPlayback() {
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
        resetPlaybackPosition()
    }

    private func firstEventIndex(in take: RecordedTake, atOrAfter offset: TimeInterval) -> Int {
        take.events.firstIndex { $0.offsetFromTakeStart >= offset } ?? take.events.count
    }

    private func resetPlaybackPosition() {
        playbackResumeIndex = 0
        playbackResumeOffset = 0
        playbackStartedAt = nil
        playbackSegmentStartOffset = 0
        playbackTake = nil
        currentTakeID = nil
        currentTarget = nil
        pausedAtOffset = nil
    }

    private func pedalReentryEvents(in take: RecordedTake, at offset: TimeInterval) -> [RecordedMIDIEvent] {
        // Controllers that can keep notes sounding/colored across seek boundaries.
        let pedalControllers: Set<UInt8> = [64, 66, 67] // sustain, sostenuto, soft
        var latestByChannelAndController: [UInt8: [UInt8: UInt8]] = [:]

        for event in take.events {
            if event.offsetFromTakeStart >= offset {
                break
            }
            guard event.kind == .controlChange, pedalControllers.contains(event.data1) else {
                continue
            }
            latestByChannelAndController[event.channel, default: [:]][event.data1] = event.data2 ?? 0
        }

        var syntheticEvents: [RecordedMIDIEvent] = []
        let now = Date()
        for channel in latestByChannelAndController.keys.sorted() {
            guard let ccValues = latestByChannelAndController[channel] else { continue }
            guard let channelNibble = midiChannelNibble(for: Int(channel)) else { continue }
            for controller in pedalControllers.sorted() {
                guard let value = ccValues[controller], value >= 64 else { continue }
                let status = UInt8(0xB0 | channelNibble)
                syntheticEvents.append(
                    RecordedMIDIEvent(
                        receivedAt: now,
                        offsetFromTakeStart: offset,
                        kind: .controlChange,
                        channel: channel,
                        status: status,
                        data1: controller,
                        data2: value
                    )
                )
            }
        }

        return syntheticEvents
    }

    private func rebuildSampler() throws {
        let wasAttached = speakerInstrument.engine === audioEngine
        if wasAttached {
            sendAllNotesOff()
            audioEngine.disconnectNodeInput(speakerInstrument)
            audioEngine.disconnectNodeOutput(speakerInstrument)
            audioEngine.detach(speakerInstrument)
        }
        let soundBankURL = try resolvedSoundBankURL()
        let newInstrument = AVAudioUnitSampler()
        audioEngine.attach(newInstrument)
        audioEngine.connect(newInstrument, to: audioEngine.mainMixerNode, format: nil)
        try newInstrument.loadSoundBankInstrument(
            at: soundBankURL,
            program: UInt8(clamping: speakerProgram),
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
            bankLSB: UInt8(kAUSampler_DefaultBankLSB)
        )
        speakerInstrument = newInstrument
    }

    private func sendControlChange(_ controller: UInt8, value: UInt8, on channel: Int) {
        guard let channelNibble = midiChannelNibble(for: channel) else { return }
        let status = UInt8(0xB0 | channelNibble)
        if ensureSpeakerAudioReady() {
            speakerInstrument.sendMIDIEvent(status, data1: controller, data2: value)
        }

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

    private func ensureSpeakerAudioReady() -> Bool {
        if speakerInstrument.engine !== audioEngine {
            do {
                try rebuildSampler()
            } catch {
                print("MIDI Scribe playback sampler rebuild failed: \(error)")
                return false
            }
        }
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                print("MIDI Scribe playback audio start failed: \(error)")
                return false
            }
        }
        return speakerInstrument.engine === audioEngine && audioEngine.isRunning
    }
}
