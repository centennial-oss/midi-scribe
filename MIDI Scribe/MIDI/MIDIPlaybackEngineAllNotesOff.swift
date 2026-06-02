//
//  MIDIPlaybackEngineAllNotesOff.swift
//  MIDI Scribe
//
//  Coalesced "all notes off" reset, sent on every pause/stop/scrub-end.
//  Previously this made 96 separate `sendControlChange` calls (6 reset
//  controllers × 16 channels), each taking the sampler lock and allocating
//  its own one-packet `MIDIPacketList` per external MIDI destination. Now it
//  takes the sampler lock once and builds a single coalesced packet list
//  (96 packets) sent once per destination.
//

import CoreMIDI
import Foundation
import os

extension MIDIPlaybackEngine {
    /// Reset controllers: sustain (64), sostenuto (66), soft (67),
    /// all-sound-off (120), reset-all-controllers (121), all-notes-off (123).
    nonisolated private static let allNotesOffControllers: [UInt8] = [64, 66, 67, 120, 121, 123]

    nonisolated func sendAllNotesOff() {
        let controllers = Self.allNotesOffControllers

        // Sampler: one lock acquisition for all reset messages instead of 96.
        os_unfair_lock_lock(&samplerLock)
        if !samplerIsRebuilding, speakerInstrumentIsReadyLocked(allowRebuild: true) {
            let sampler = speakerInstrument
            for channelNibble in 0 ..< 16 {
                let status = UInt8(0xB0) | UInt8(channelNibble)
                for controller in controllers {
                    sendMIDIEventSafely(to: sampler, status: status, data1: controller, data2: 0)
                }
            }
        }
        os_unfair_lock_unlock(&samplerLock)

        // External MIDI: one coalesced packet list sent once per destination.
        var messages: [[UInt8]] = []
        messages.reserveCapacity(16 * controllers.count)
        for channelNibble in 0 ..< 16 {
            let status = UInt8(0xB0) | UInt8(channelNibble)
            for controller in controllers {
                messages.append([status, controller, 0])
            }
        }
        sendCoalescedToMIDIDestinations(messages)
    }

    /// Builds one `MIDIPacketList` containing all `messages` and sends it once
    /// per destination. Each message is `[status, data1, data2]` with bytes
    /// already in valid 7-bit / channel-nibble form.
    nonisolated private func sendCoalescedToMIDIDestinations(_ messages: [[UInt8]]) {
        guard outputPort != 0, !messages.isEmpty else { return }
        let destinations = currentMIDIDestinations()
        guard !destinations.isEmpty else { return }

        let byteCount = max(1024, messages.count * 64 + 256)
        let listPointer = UnsafeMutableRawPointer.allocate(
            byteCount: byteCount,
            alignment: MemoryLayout<MIDIPacketList>.alignment
        )
        defer { listPointer.deallocate() }
        let packetList = listPointer.bindMemory(to: MIDIPacketList.self, capacity: 1)

        var currentPacket = MIDIPacketListInit(packetList)
        for message in messages {
            let added: UnsafeMutablePointer<MIDIPacket>? = message.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return currentPacket }
                return MIDIPacketListAdd(packetList, byteCount, currentPacket, 0, message.count, base)
            }
            guard let added else { break } // out of buffer space; send what fit
            currentPacket = added
        }

        for destination in destinations {
            MIDISend(outputPort, destination, packetList)
        }
    }
}
