import AudioToolbox
import AVFoundation
import CoreAudio
import CoreMIDI
import Foundation
import os

extension MIDIPlaybackEngine {
    func configureAudio() {
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

    func reloadInstrument() {
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

    func catchObjC(_ label: String, _ block: () -> Void) {
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
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        return status == noErr ? deviceID : nil
    }
    #endif

    func resolvedSoundBankURL() throws -> URL { try SoundBankAssets.soundBankURL() }

    func configureMIDIOutput() {
        let clientStatus = MIDIClientCreateWithBlock(
            "\(AppIdentifier.name) Playback" as CFString,
            &outputClient
        ) { _ in }
        guard clientStatus == noErr else { return }
        MIDIOutputPortCreate(outputClient, "\(AppIdentifier.name) Playback Port" as CFString, &outputPort)
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
    func playThroughSpeakers(_ event: RecordedMIDIEvent, allowRebuild: Bool) {
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

    func sendToMIDIDestinations(_ event: RecordedMIDIEvent, channelOverride: Int) {
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

    func sendAllNotesOff() {
        for channel in 1...16 {
            sendControlChange(64, value: 0, on: channel)
            sendControlChange(66, value: 0, on: channel)
            sendControlChange(67, value: 0, on: channel)
            sendControlChange(120, value: 0, on: channel)
            sendControlChange(121, value: 0, on: channel)
            sendControlChange(123, value: 0, on: channel)
        }
    }

    func captureResumePosition() {
        guard let playbackStartedAt else { return }
        playbackResumeOffset = playbackSegmentStartOffset + max(Date().timeIntervalSince(playbackStartedAt), 0)
        self.playbackStartedAt = nil
    }

    func firstEventIndex(in take: RecordedTake, atOrAfter offset: TimeInterval) -> Int {
        take.events.firstIndex { $0.offsetFromTakeStart >= offset } ?? take.events.count
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

}
