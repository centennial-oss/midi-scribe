//
//  AppSettings.swift
//  MIDI Scribe
//

import Combine
import Foundation

let appSettingsPreferenceKeys = [
    "disableScribing",
    "monitoredMIDIChannel",
    "newTakePauseSeconds",
    "recentTakesShownInMenus",
    "selectedPlaybackTarget",
    "speakerOutputProgram",
    "echoScribedToSpeakers",
    "startTakeWithNoteEvents",
    "takeStartControlChanges",
    "takeEndControlChanges",
    "welcomeSheetShown"
]

@MainActor
final class AppSettings: ObservableObject {
    static let midiChannelAllValue = 0
    static let defaultSpeakerOutputProgram = 2
    static let defaultStartTakeWithNoteEvents = true
    static let defaultTakeStartControlChanges: Set<UInt8> = []
    static let defaultTakeEndControlChanges: Set<UInt8> = []
    static let defaultPlaybackOutputTarget: PlaybackOutputTarget = .osSpeakers

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

    @Published var selectedPlaybackTarget: PlaybackOutputTarget {
        didSet {
            userDefaults.set(
                Self.playbackOutputTargetPreferenceValue(for: selectedPlaybackTarget),
                forKey: Self.selectedPlaybackTargetKey
            )
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

    let userDefaults: UserDefaults
    private var userDefaultsObserver: AnyCancellable?

    static let disableScribingKey = "disableScribing"
    static let monitoredMIDIChannelKey = "monitoredMIDIChannel"
    static let newTakePauseSecondsKey = "newTakePauseSeconds"
    static let recentTakesShownInMenusKey = "recentTakesShownInMenus"
    static let selectedPlaybackTargetKey = "selectedPlaybackTarget"
    static let speakerOutputProgramKey = "speakerOutputProgram"
    static let echoScribedToSpeakersKey = "echoScribedToSpeakers"
    static let startTakeWithNoteEventsKey = "startTakeWithNoteEvents"
    static let takeStartControlChangesKey = "takeStartControlChanges"
    static let takeEndControlChangesKey = "takeEndControlChanges"
    static let welcomeSheetShownKey = "welcomeSheetShown"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        disableScribing = userDefaults.object(forKey: Self.disableScribingKey) as? Bool ?? false
        monitoredMIDIChannel =
            userDefaults.object(forKey: Self.monitoredMIDIChannelKey) as? Int ?? Self.midiChannelAllValue
        newTakePauseSeconds = userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 30.0
        recentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 25
        selectedPlaybackTarget = Self.playbackOutputTarget(
            from: userDefaults.string(forKey: Self.selectedPlaybackTargetKey)
        )
        let rawSpeakerOutputProgram = userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int
        let resolvedSpeakerOutputProgram = Self.validSpeakerOutputProgram(rawSpeakerOutputProgram)
        speakerOutputProgram = resolvedSpeakerOutputProgram
        #if DEBUG
        NSLog(
            "[SpeakerProgram] settings init " +
                "rawUserDefault=\(rawSpeakerOutputProgram.map(String.init) ?? "nil") " +
                "resolved=\(resolvedSpeakerOutputProgram) default=\(Self.defaultSpeakerOutputProgram)"
        )
        #endif
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
        userDefaults.set(
            Self.playbackOutputTargetPreferenceValue(for: selectedPlaybackTarget),
            forKey: Self.selectedPlaybackTargetKey
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

    var hasWelcomeSheetShownValue: Bool {
        userDefaults.object(forKey: Self.welcomeSheetShownKey) as? Bool == true
    }

    func markWelcomeSheetShown() {
        userDefaults.set(true, forKey: Self.welcomeSheetShownKey)
        #if DEBUG
        NSLog("[Welcome Sheet] marked welcome sheet shown")
        #endif
    }

    func shouldStartTake(_ event: RecordedMIDIEvent) -> Bool {
        switch event.kind {
        case .noteOn:
            return startTakeWithNoteEvents
        case .controlChange:
            return isReleasedControlChange(event) && takeStartControlChanges.contains(event.data1)
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

    private func isReleasedControlChange(_ event: RecordedMIDIEvent) -> Bool {
        guard event.kind == .controlChange, let value = event.data2 else { return false }
        return value < 10
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
        name: "Sustain / Right",
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
        name: "Soft / Left",
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
        .sostenuto,
        .soft,
        .sustain,
        .otherControlChanges
    ]

    static let takeEndOptions: [TakeControlSignal] = [
        .sostenuto,
        .soft,
        .otherControlChanges
    ]
}
