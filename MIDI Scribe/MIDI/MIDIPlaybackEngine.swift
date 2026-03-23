//
//  MIDIPlaybackEngine.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import AudioToolbox
import AVFoundation
import Combine
import CoreMIDI
import Foundation

enum PlaybackOutputTarget: Hashable {
    case osSpeakers
    case midiChannel(Int)
}

@MainActor
final class MIDIPlaybackEngine: ObservableObject {
    @Published private(set) var isPlaying = false

    private let settings: AppSettings
    private let audioEngine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var settingsCancellable: AnyCancellable?
    private var playbackTask: Task<Void, Never>?
    private var playbackTakeID: UUID?
    private var playbackTarget: PlaybackOutputTarget = .osSpeakers
    private var outputClient = MIDIClientRef()
    private var outputPort = MIDIPortRef()

    init(settings: AppSettings) {
        self.settings = settings
        configureAudio()
        configureMIDIOutput()

        settingsCancellable = settings.$speakerOutputProgram
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reloadInstrument()
            }
    }

    deinit {
        playbackTask?.cancel()
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if outputClient != 0 {
            MIDIClientDispose(outputClient)
        }
    }

    func togglePlayback(for take: RecordedTake, target: PlaybackOutputTarget) {
        if isPlaying, playbackTakeID == take.id, playbackTarget == target {
            pause()
        } else {
            play(take: take, target: target)
        }
    }

    func isPlaying(take: RecordedTake, target: PlaybackOutputTarget) -> Bool {
        isPlaying && playbackTakeID == take.id && playbackTarget == target
    }

    func restartPlayback(for take: RecordedTake, target: PlaybackOutputTarget) {
        play(take: take, target: target)
    }

    func playLiveEventToSpeakers(_ event: RecordedMIDIEvent) {
        guard settings.echoScribedToSpeakers else { return }
        playThroughSpeakers(event)
    }

    func pause() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
        sendAllNotesOff()
    }

    private func play(take: RecordedTake, target: PlaybackOutputTarget) {
        pause()
        playbackTakeID = take.id
        playbackTarget = target
        isPlaying = true

        playbackTask = Task { [weak self] in
            guard let self else { return }
            var previousOffset: TimeInterval = 0

            for event in take.events.sorted(by: { $0.offsetFromTakeStart < $1.offsetFromTakeStart }) {
                let wait = max(event.offsetFromTakeStart - previousOffset, 0)
                if wait > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                }
                if Task.isCancelled { return }

                await MainActor.run {
                    self.play(event: event, target: target)
                }
                previousOffset = event.offsetFromTakeStart
            }

            await MainActor.run {
                self.isPlaying = false
                self.sendAllNotesOff()
            }
        }
    }

    private func configureAudio() {
        audioEngine.attach(sampler)
        audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)
        reloadInstrument()

        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try audioEngine.start()
        } catch {
        }
    }

    private func reloadInstrument() {
        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            try sampler.loadSoundBankInstrument(
                at: soundBankURL,
                program: UInt8(clamping: settings.speakerOutputProgram),
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
            )
        } catch {
        }
    }

    private var soundBankURL: URL {
        #if os(macOS)
        URL(fileURLWithPath: "/System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls")
        #else
        URL(fileURLWithPath: "/System/Library/Audio/Sounds/Banks/gs_instruments.dls")
        #endif
    }

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
        switch event.kind {
        case .noteOn:
            sampler.startNote(event.data1, withVelocity: event.data2 ?? 0, onChannel: event.channel - 1)
        case .noteOff:
            sampler.stopNote(event.data1, onChannel: event.channel - 1)
        default:
            sampler.sendMIDIEvent(event.status, data1: event.data1, data2: event.data2 ?? 0)
        }
    }

    private func sendToMIDIDestinations(_ event: RecordedMIDIEvent, channelOverride: Int) {
        guard outputPort != 0 else { return }
        var data = event.midiData
        guard !data.isEmpty else { return }
        data[0] = (data[0] & 0xF0) | UInt8(channelOverride - 1)

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
            let status = UInt8(0xB0 | (channel - 1))
            sampler.sendMIDIEvent(status, data1: 123, data2: 0)

            let event = RecordedMIDIEvent(
                receivedAt: Date(),
                offsetFromTakeStart: 0,
                kind: .controlChange,
                channel: UInt8(channel),
                status: status,
                data1: 123,
                data2: 0
            )
            sendToMIDIDestinations(event, channelOverride: channel)
        }
    }
}
