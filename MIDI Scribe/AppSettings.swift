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

    private let userDefaults: UserDefaults
    private var userDefaultsObserver: AnyCancellable?

    private static let disableScribingKey = "disableScribing"
    private static let monitoredMIDIChannelKey = "monitoredMIDIChannel"
    private static let newTakePauseSecondsKey = "newTakePauseSeconds"
    private static let recentTakesShownInMenusKey = "recentTakesShownInMenus"
    private static let speakerOutputProgramKey = "speakerOutputProgram"
    private static let echoScribedToSpeakersKey = "echoScribedToSpeakers"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        disableScribing = userDefaults.object(forKey: Self.disableScribingKey) as? Bool ?? false
        monitoredMIDIChannel =
            userDefaults.object(forKey: Self.monitoredMIDIChannelKey) as? Int ?? Self.midiChannelAllValue
        newTakePauseSeconds = userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 180.0
        recentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 10
        speakerOutputProgram = Self.validSpeakerOutputProgram(
            userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int
        )
        echoScribedToSpeakers =
            userDefaults.object(forKey: Self.echoScribedToSpeakersKey) as? Bool ?? true
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
            userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 180.0
        let updatedRecentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 10
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
}
