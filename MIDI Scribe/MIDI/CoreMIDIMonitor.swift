//
//  CoreMIDIMonitor.swift
//  MIDI Scribe
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

    var client = MIDIClientRef()
    var inputPort = MIDIPortRef()
    var connectedSources: [MIDIUniqueID: MIDIEndpointRef] = [:]
    var activeNotes: [MIDINote] = []
    var isStarted = false
    private let settings: AppSettings
    private var settingsCancellable: AnyCancellable?
    private var lastPublishedActiveNotes: [MIDINote] = []
    private var lastPublishedActiveChannels: [UInt8] = []

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

        let clientStatus = MIDIClientCreateWithBlock(
            "\(BuildInfo.appName) Input" as CFString,
            &client
        ) { [weak self] _ in
            self?.handleMIDINotification()
        }
        guard clientStatus == noErr else {
            throw CoreMIDIMonitorError.clientCreation(clientStatus)
        }

        let inputStatus = MIDIInputPortCreateWithBlock(
            client,
            "\(BuildInfo.appName) Listener" as CFString,
            &inputPort
        ) { [weak self] packetList, _ in
            self?.handlePacketList(packetList)
        }
        guard inputStatus == noErr else {
            cleanupMIDIObjects()
            throw CoreMIDIMonitorError.inputPortCreation(inputStatus)
        }

        try reconnectSources()
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }

        cleanupMIDIObjects()
        activeNotes.removeAll()
        publishActiveNotes()
        isStarted = false
    }
}

private struct ThreeByteChannelMessage {
    let status: UInt8
    let command: UInt8
    let channel: UInt8
    let data1: UInt8
    let data2: UInt8
    let receivedAt: Date
}

extension CoreMIDIMonitor {
    private func handlePacketList(_ packetList: UnsafePointer<MIDIPacketList>) {
        for packet in packetList.unsafeSequence() {
            parseMessages(in: packet.pointee)
        }
    }

    private func handleMIDINotification() {
        guard isStarted else { return }
        do {
            try reconnectSources()
        } catch {
        }
    }

    private func parseMessages(in packet: MIDIPacket) {
        // Read directly from the fixed-size packet tuple instead of allocating
        // a fresh [UInt8] per packet on the MIDI thread.
        withUnsafeBytes(of: packet.data) { rawBuffer in
            let count = Int(packet.length)
            guard count > 0, let base = rawBuffer.baseAddress else { return }
            let bytes = UnsafeBufferPointer<UInt8>(
                start: base.assumingMemoryBound(to: UInt8.self),
                count: min(count, rawBuffer.count)
            )
            parseMessages(bytes: bytes)
        }
    }

    private func parseMessages(bytes: UnsafeBufferPointer<UInt8>) {
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
                        ThreeByteChannelMessage(
                            status: status,
                            command: command,
                            channel: channel,
                            data1: noteNumber,
                            data2: data2,
                            receivedAt: receivedAt
                        )
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

    private func handleThreeByteChannelMessage(_ message: ThreeByteChannelMessage) {
        guard settings.isScribingEnabled else { return }
        guard shouldMonitor(channel: message.channel) else { return }

        switch message.command {
        case 0x80, 0x90:
            noteOff(
                noteNumber: message.data1,
                velocity: message.data2,
                channel: message.channel,
                receivedAt: message.receivedAt
            )
        case 0xA0:
            publishThreeByteKind(message, kind: .polyphonicKeyPressure)
        case 0xB0:
            logControlChange(message)
            publishThreeByteKind(message, kind: .controlChange)
        case 0xE0:
            publishThreeByteKind(message, kind: .pitchBend)
        default:
            break
        }
    }

    private func logControlChange(_ message: ThreeByteChannelMessage) {
        #if DEBUG
        let state = message.data2 == 0 ? "off" : "on"
        NSLog(
            "[MIDIChangeControl] " +
                "channel=\(message.channel) " +
                "controller=\(message.data1) " +
                "value=\(message.data2) " +
                "velocity=\(message.data2) " +
                "state=\(state) " +
                "status=0x\(String(format: "%02X", message.status)) " +
                "receivedAt=\(message.receivedAt)"
        )
        #endif
    }

    private func publishThreeByteKind(_ message: ThreeByteChannelMessage, kind: MIDIChannelEventKind) {
        publishRecordedEvent(
            RecordedMIDIEvent(
                receivedAt: message.receivedAt,
                offsetFromTakeStart: 0,
                kind: kind,
                channel: message.channel,
                status: message.status,
                data1: message.data1,
                data2: message.data2
            )
        )
        publishEligibleInput(receivedAt: message.receivedAt)
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
            RecordedMIDIEvent(
                receivedAt: receivedAt,
                offsetFromTakeStart: 0,
                kind: kind,
                channel: channel,
                status: status,
                data1: data1
            )
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
        guard notes != lastPublishedActiveNotes || channels != lastPublishedActiveChannels else { return }
        lastPublishedActiveNotes = notes
        lastPublishedActiveChannels = channels

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
