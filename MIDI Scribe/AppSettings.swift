//
//  AppSettings.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let midiChannelAllValue = 0
    static let defaultSpeakerOutputProgram = 2
    static let defaultStartTakeWithNoteEvents = true
    static let defaultTakeStartControlChanges: Set<UInt8> = []
    static let defaultTakeEndControlChanges: Set<UInt8> = []

    @Published var disableScribing: Bool {
        didSet {
            userDefaults.set(disableScribing, forKey: Self.disableScribingKey)
        }
    }

    @Published var monitoredMIDIChannel: Int {
        didSet {
            userDefaults.set(monitoredMIDIChannel, forKey: Self.monitoredMIDIChannelKey)
        }
    }

    @Published var newTakePauseSeconds: Double {
        didSet {
            userDefaults.set(newTakePauseSeconds, forKey: Self.newTakePauseSecondsKey)
        }
    }

    @Published var recentTakesShownInMenus: Int {
        didSet {
            userDefaults.set(recentTakesShownInMenus, forKey: Self.recentTakesShownInMenusKey)
        }
    }

    @Published var speakerOutputProgram: Int {
        didSet {
            userDefaults.set(speakerOutputProgram, forKey: Self.speakerOutputProgramKey)
        }
    }

    @Published var echoScribedToSpeakers: Bool {
        didSet {
            userDefaults.set(echoScribedToSpeakers, forKey: Self.echoScribedToSpeakersKey)
        }
    }

    @Published var startTakeWithNoteEvents: Bool {
        didSet {
            userDefaults.set(startTakeWithNoteEvents, forKey: Self.startTakeWithNoteEventsKey)
        }
    }

    @Published var takeStartControlChanges: Set<UInt8> {
        didSet {
            userDefaults.set(
                takeStartControlChanges.map(Int.init).sorted(),
                forKey: Self.takeStartControlChangesKey
            )
        }
    }

    @Published var takeEndControlChanges: Set<UInt8> {
        didSet {
            userDefaults.set(takeEndControlChanges.map(Int.init).sorted(), forKey: Self.takeEndControlChangesKey)
        }
    }

    private let userDefaults: UserDefaults
    private var userDefaultsObserver: AnyCancellable?

    private static let disableScribingKey = "disableScribing"
    private static let monitoredMIDIChannelKey = "monitoredMIDIChannel"
    private static let newTakePauseSecondsKey = "newTakePauseSeconds"
    private static let recentTakesShownInMenusKey = "recentTakesShownInMenus"
    private static let speakerOutputProgramKey = "speakerOutputProgram"
    private static let echoScribedToSpeakersKey = "echoScribedToSpeakers"
    private static let startTakeWithNoteEventsKey = "startTakeWithNoteEvents"
    private static let takeStartControlChangesKey = "takeStartControlChanges"
    private static let takeEndControlChangesKey = "takeEndControlChanges"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        disableScribing = userDefaults.object(forKey: Self.disableScribingKey) as? Bool ?? false
        monitoredMIDIChannel =
            userDefaults.object(forKey: Self.monitoredMIDIChannelKey) as? Int ?? Self.midiChannelAllValue
        newTakePauseSeconds = userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 30.0
        recentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 25
        speakerOutputProgram = Self.validSpeakerOutputProgram(
            userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int
        )
        echoScribedToSpeakers =
            userDefaults.object(forKey: Self.echoScribedToSpeakersKey) as? Bool ?? true
        startTakeWithNoteEvents =
            userDefaults.object(forKey: Self.startTakeWithNoteEventsKey) as? Bool
                ?? Self.defaultStartTakeWithNoteEvents
        takeStartControlChanges = Self.controlChangeSet(
            forKey: Self.takeStartControlChangesKey,
            in: userDefaults,
            defaultValue: Self.defaultTakeStartControlChanges
        )
        takeEndControlChanges = Self.controlChangeSet(
            forKey: Self.takeEndControlChangesKey,
            in: userDefaults,
            defaultValue: Self.defaultTakeEndControlChanges
        )
        userDefaults.set(speakerOutputProgram, forKey: Self.speakerOutputProgramKey)

        userDefaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: userDefaults
        )
            .sink { [weak self] _ in
                self?.reloadFromUserDefaults()
            }
    }

    var isScribingEnabled: Bool {
        !disableScribing
    }

    func shouldStartTake(_ event: RecordedMIDIEvent) -> Bool {
        switch event.kind {
        case .noteOn:
            return startTakeWithNoteEvents
        case .controlChange:
            return isPressedControlChange(event) && takeStartControlChanges.contains(event.data1)
        default:
            return false
        }
    }

    func shouldEndTake(_ event: RecordedMIDIEvent) -> Bool {
        isPressedControlChange(event) && takeEndControlChanges.contains(event.data1)
    }

    private func isPressedControlChange(_ event: RecordedMIDIEvent) -> Bool {
        guard event.kind == .controlChange, let value = event.data2 else { return false }
        return value >= 64
    }

    func resetAllPreferences() {
        if let bundleID = Bundle.main.bundleIdentifier {
            userDefaults.removePersistentDomain(forName: bundleID)
        } else {
            userDefaults.dictionaryRepresentation().keys.forEach { key in
                userDefaults.removeObject(forKey: key)
            }
        }
        reloadFromUserDefaults()
    }

    private func reloadFromUserDefaults() {
        let updatedDisableScribing = userDefaults.object(forKey: Self.disableScribingKey) as? Bool ?? false
        let updatedMonitoredMIDIChannel =
            userDefaults.object(forKey: Self.monitoredMIDIChannelKey) as? Int ?? Self.midiChannelAllValue
        let updatedNewTakePauseSeconds =
            userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 30.0
        let updatedRecentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 25
        let updatedSpeakerOutputProgram =
            Self.validSpeakerOutputProgram(userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int)
        let updatedEchoScribedToSpeakers =
            userDefaults.object(forKey: Self.echoScribedToSpeakersKey) as? Bool ?? true

        if disableScribing != updatedDisableScribing {
            disableScribing = updatedDisableScribing
        }

        if monitoredMIDIChannel != updatedMonitoredMIDIChannel {
            monitoredMIDIChannel = updatedMonitoredMIDIChannel
        }

        if newTakePauseSeconds != updatedNewTakePauseSeconds {
            newTakePauseSeconds = updatedNewTakePauseSeconds
        }

        if recentTakesShownInMenus != updatedRecentTakesShownInMenus {
            recentTakesShownInMenus = updatedRecentTakesShownInMenus
        }

        if speakerOutputProgram != updatedSpeakerOutputProgram {
            speakerOutputProgram = updatedSpeakerOutputProgram
        } else if userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int != updatedSpeakerOutputProgram {
            userDefaults.set(updatedSpeakerOutputProgram, forKey: Self.speakerOutputProgramKey)
        }

        if echoScribedToSpeakers != updatedEchoScribedToSpeakers {
            echoScribedToSpeakers = updatedEchoScribedToSpeakers
        }

        reloadTakeControlSettings()
    }

    private func reloadTakeControlSettings() {
        let updatedStartTakeWithNoteEvents =
            userDefaults.object(forKey: Self.startTakeWithNoteEventsKey) as? Bool
                ?? Self.defaultStartTakeWithNoteEvents
        let updatedTakeStartControlChanges = Self.controlChangeSet(
            forKey: Self.takeStartControlChangesKey,
            in: userDefaults,
            defaultValue: Self.defaultTakeStartControlChanges
        )
        let updatedTakeEndControlChanges = Self.controlChangeSet(
            forKey: Self.takeEndControlChangesKey,
            in: userDefaults,
            defaultValue: Self.defaultTakeEndControlChanges
        )

        if startTakeWithNoteEvents != updatedStartTakeWithNoteEvents {
            startTakeWithNoteEvents = updatedStartTakeWithNoteEvents
        }

        if takeStartControlChanges != updatedTakeStartControlChanges {
            takeStartControlChanges = updatedTakeStartControlChanges
        }

        if takeEndControlChanges != updatedTakeEndControlChanges {
            takeEndControlChanges = updatedTakeEndControlChanges
        }
    }

    private static func validSpeakerOutputProgram(_ program: Int?) -> Int {
        guard
            let program,
            GeneralMIDI.programs.contains(where: { $0.program == program })
        else {
            return defaultSpeakerOutputProgram
        }
        return program
    }

    private static func controlChangeSet(
        forKey key: String,
        in userDefaults: UserDefaults,
        defaultValue: Set<UInt8>
    ) -> Set<UInt8> {
        guard let values = userDefaults.array(forKey: key) as? [Int] else {
            return defaultValue
        }
        return Set(values.compactMap { value in
            guard value >= 0, value <= 127 else { return nil }
            return UInt8(value)
        })
    }
}

struct TakeControlSignal: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let detail: String
    let controlChangeNumbers: Set<UInt8>

    static let notes = TakeControlSignal(
        id: "notes",
        name: "Key Press / Drum Hit",
        detail: "",
        controlChangeNumbers: []
    )
    static let sustain = TakeControlSignal(
        id: "sustain",
        name: "Sustain / Left",
        detail: "",
        controlChangeNumbers: [64]
    )
    static let sostenuto = TakeControlSignal(
        id: "sostenuto",
        name: "Sostenuto / Middle",
        detail: "",
        controlChangeNumbers: [66]
    )
    static let soft = TakeControlSignal(
        id: "soft",
        name: "Soft / Right",
        detail: "",
        controlChangeNumbers: [67]
    )
    static let otherControlChanges = TakeControlSignal(
        id: "otherControlChanges",
        name: "Other Control Changes",
        detail: "",
        controlChangeNumbers: Set((0...127).map(UInt8.init)).subtracting([64, 66, 67])
    )

    static let takeStartOptions: [TakeControlSignal] = [
        .notes,
        .sustain,
        .sostenuto,
        .soft,
        .otherControlChanges
    ]

    static let takeEndOptions: [TakeControlSignal] = [
        .sostenuto,
        .soft,
        .otherControlChanges
    ]
}
