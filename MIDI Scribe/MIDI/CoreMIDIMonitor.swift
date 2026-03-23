//
//  CoreMIDIMonitor.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Combine
import CoreMIDI
import Foundation

protocol MIDIListening: AnyObject {
    var onActiveNotesChanged: (@MainActor ([MIDINote]) -> Void)? { get set }
    var onActiveChannelsChanged: (@MainActor ([UInt8]) -> Void)? { get set }
    var onEligibleInputReceived: (@MainActor (Date) -> Void)? { get set }
    var onRecordedEventReceived: (@MainActor (RecordedMIDIEvent) -> Void)? { get set }

    func start() throws
    func stop()
}

enum CoreMIDIMonitorError: LocalizedError {
    case clientCreation(OSStatus)
    case inputPortCreation(OSStatus)
    case sourceConnection(OSStatus, sourceIndex: Int)

    var errorDescription: String? {
        switch self {
        case .clientCreation(let status):
            return "Unable to create MIDI client (\(status))."
        case .inputPortCreation(let status):
            return "Unable to create MIDI input port (\(status))."
        case .sourceConnection(let status, let sourceIndex):
            return "Unable to connect MIDI source \(sourceIndex) (\(status))."
        }
    }
}

final class CoreMIDIMonitor: MIDIListening {
    var onActiveNotesChanged: (@MainActor ([MIDINote]) -> Void)?
    var onActiveChannelsChanged: (@MainActor ([UInt8]) -> Void)?
    var onEligibleInputReceived: (@MainActor (Date) -> Void)?
    var onRecordedEventReceived: (@MainActor (RecordedMIDIEvent) -> Void)?

    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var activeNotes: [MIDINote] = []
    private var isStarted = false
    private let settings: AppSettings
    private var settingsCancellable: AnyCancellable?

    init(settings: AppSettings) {
        self.settings = settings
        settingsCancellable = Publishers.Merge(
            settings.$monitoredMIDIChannel.map { _ in () },
            settings.$disableScribing.map { _ in () }
        )
        .sink { [weak self] _ in
            self?.filterActiveNotesForSettings()
        }
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isStarted else { return }

        let clientStatus = MIDIClientCreateWithBlock("MIDI Scribe Input" as CFString, &client) { _ in }
        guard clientStatus == noErr else {
            throw CoreMIDIMonitorError.clientCreation(clientStatus)
        }

        let inputStatus = MIDIInputPortCreateWithBlock(client, "MIDI Scribe Listener" as CFString, &inputPort) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }
        guard inputStatus == noErr else {
            throw CoreMIDIMonitorError.inputPortCreation(inputStatus)
        }

        for sourceIndex in 0 ..< MIDIGetNumberOfSources() {
            let source = MIDIGetSource(sourceIndex)
            let connectionStatus = MIDIPortConnectSource(inputPort, source, nil)
            guard connectionStatus == noErr else {
                throw CoreMIDIMonitorError.sourceConnection(connectionStatus, sourceIndex: Int(sourceIndex))
            }
        }

        isStarted = true
    }

    func stop() {
        guard isStarted else { return }

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }

        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }

        activeNotes.removeAll()
        publishActiveNotes()
        isStarted = false
    }

    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        for packet in packetList.unsafeSequence() {
            parseMessages(in: packet.pointee)
        }
    }

    private func parseMessages(in packet: MIDIPacket) {
        let bytes = withUnsafeBytes(of: packet.data) { rawBuffer in
            Array(rawBuffer.prefix(Int(packet.length)))
        }
        var index = 0

        while index + 2 < bytes.count {
            let status = bytes[index]
            let command = status & 0xF0
            let channel = (status & 0x0F) + 1
            let receivedAt = Date()

            switch command {
            case 0x80, 0x90, 0xA0, 0xB0, 0xE0:
                let noteNumber = bytes[index + 1]
                let data2 = bytes[index + 2]

                if command == 0x90 && data2 > 0 {
                    noteOn(noteNumber: noteNumber, velocity: data2, channel: channel, receivedAt: receivedAt)
                } else {
                    handleThreeByteChannelMessage(
                        status: status,
                        command: command,
                        channel: channel,
                        data1: noteNumber,
                        data2: data2,
                        receivedAt: receivedAt
                    )
                }

                index += 3
            case 0xC0, 0xD0:
                let data1 = bytes[index + 1]
                handleTwoByteChannelMessage(
                    status: status,
                    command: command,
                    channel: channel,
                    data1: data1,
                    receivedAt: receivedAt
                )
                index += 2
            default:
                index += messageLength(for: status)
            }
        }
    }

    private func noteOn(noteNumber: UInt8, velocity: UInt8, channel: UInt8, receivedAt: Date) {
        guard settings.isScribingEnabled else { return }
        guard shouldMonitor(channel: channel) else { return }
        activeNotes.removeAll { $0.noteNumber == noteNumber && $0.channel == channel }
        activeNotes.append(MIDINote(noteNumber: noteNumber, velocity: velocity, channel: channel))
        publishRecordedEvent(
            RecordedMIDIEvent(
                receivedAt: receivedAt,
                offsetFromTakeStart: 0,
                kind: .noteOn,
                channel: channel,
                status: 0x90 | (channel - 1),
                data1: noteNumber,
                data2: velocity
            )
        )
        publishEligibleInput(receivedAt: receivedAt)
        publishActiveNotes()
    }

    private func noteOff(noteNumber: UInt8, velocity: UInt8, channel: UInt8, receivedAt: Date) {
        guard settings.isScribingEnabled else { return }
        guard shouldMonitor(channel: channel) else { return }
        activeNotes.removeAll { $0.noteNumber == noteNumber && $0.channel == channel }
        publishRecordedEvent(
            RecordedMIDIEvent(
                receivedAt: receivedAt,
                offsetFromTakeStart: 0,
                kind: .noteOff,
                channel: channel,
                status: 0x80 | (channel - 1),
                data1: noteNumber,
                data2: velocity
            )
        )
        publishEligibleInput(receivedAt: receivedAt)
        publishActiveNotes()
    }

    private func handleThreeByteChannelMessage(
        status: UInt8,
        command: UInt8,
        channel: UInt8,
        data1: UInt8,
        data2: UInt8,
        receivedAt: Date
    ) {
        guard settings.isScribingEnabled else { return }
        guard shouldMonitor(channel: channel) else { return }

        switch command {
        case 0x80:
            noteOff(noteNumber: data1, velocity: data2, channel: channel, receivedAt: receivedAt)
        case 0x90:
            noteOff(noteNumber: data1, velocity: data2, channel: channel, receivedAt: receivedAt)
        case 0xA0:
            publishRecordedEvent(
                RecordedMIDIEvent(receivedAt: receivedAt, offsetFromTakeStart: 0, kind: .polyphonicKeyPressure, channel: channel, status: status, data1: data1, data2: data2)
            )
            publishEligibleInput(receivedAt: receivedAt)
        case 0xB0:
            publishRecordedEvent(
                RecordedMIDIEvent(receivedAt: receivedAt, offsetFromTakeStart: 0, kind: .controlChange, channel: channel, status: status, data1: data1, data2: data2)
            )
            publishEligibleInput(receivedAt: receivedAt)
        case 0xE0:
            publishRecordedEvent(
                RecordedMIDIEvent(receivedAt: receivedAt, offsetFromTakeStart: 0, kind: .pitchBend, channel: channel, status: status, data1: data1, data2: data2)
            )
            publishEligibleInput(receivedAt: receivedAt)
        default:
            break
        }
    }

    private func handleTwoByteChannelMessage(
        status: UInt8,
        command: UInt8,
        channel: UInt8,
        data1: UInt8,
        receivedAt: Date
    ) {
        guard settings.isScribingEnabled else { return }
        guard shouldMonitor(channel: channel) else { return }

        let kind: MIDIChannelEventKind
        switch command {
        case 0xC0:
            kind = .programChange
        case 0xD0:
            kind = .channelPressure
        default:
            return
        }

        publishRecordedEvent(
            RecordedMIDIEvent(receivedAt: receivedAt, offsetFromTakeStart: 0, kind: kind, channel: channel, status: status, data1: data1)
        )
        publishEligibleInput(receivedAt: receivedAt)
    }

    private func publishActiveNotes() {
        let notes = activeNotes.sorted {
            if $0.noteNumber == $1.noteNumber {
                return $0.channel < $1.channel
            }
            return $0.noteNumber < $1.noteNumber
        }
        let channels = Array(Set(notes.map(\.channel))).sorted()

        Task { @MainActor [onActiveNotesChanged, onActiveChannelsChanged] in
            onActiveNotesChanged?(notes)
            onActiveChannelsChanged?(channels)
        }
    }

    private func publishEligibleInput(receivedAt: Date) {
        Task { @MainActor [onEligibleInputReceived] in
            onEligibleInputReceived?(receivedAt)
        }
    }

    private func publishRecordedEvent(_ event: RecordedMIDIEvent) {
        Task { @MainActor [onRecordedEventReceived] in
            onRecordedEventReceived?(event)
        }
    }

    private func messageLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0:
            return 2
        case 0xF0:
            switch status {
            case 0xF1, 0xF3:
                return 2
            case 0xF2:
                return 3
            default:
                return 1
            }
        default:
            return 3
        }
    }

    private func shouldMonitor(channel: UInt8) -> Bool {
        let monitoredChannel = settings.monitoredMIDIChannel
        return monitoredChannel == AppSettings.midiChannelAllValue || monitoredChannel == Int(channel)
    }

    private func filterActiveNotesForSettings() {
        guard settings.isScribingEnabled else {
            activeNotes.removeAll()
            publishActiveNotes()
            return
        }

        activeNotes.removeAll { !shouldMonitor(channel: $0.channel) }
        publishActiveNotes()
    }
}
