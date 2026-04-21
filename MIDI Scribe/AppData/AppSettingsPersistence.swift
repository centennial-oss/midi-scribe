//
//  AppSettingsPersistence.swift
//  MIDI Scribe
//

import Foundation

extension AppSettings {
    func resetAllPreferences() {
        appSettingsPreferenceKeys.forEach { key in
            userDefaults.removeObject(forKey: key)
        }
        reloadFromUserDefaults()
    }

    func reloadFromUserDefaults() {
        reloadGeneralSettings()
        reloadSpeakerSettings()
        reloadTakeControlSettings()
    }

    private func reloadGeneralSettings() {
        let updatedDisableScribing = userDefaults.object(forKey: Self.disableScribingKey) as? Bool ?? false
        let updatedMonitoredMIDIChannel =
            userDefaults.object(forKey: Self.monitoredMIDIChannelKey) as? Int ?? Self.midiChannelAllValue
        let updatedNewTakePauseSeconds =
            userDefaults.object(forKey: Self.newTakePauseSecondsKey) as? Double ?? 30.0
        let updatedRecentTakesShownInMenus =
            userDefaults.object(forKey: Self.recentTakesShownInMenusKey) as? Int ?? 25
        let updatedSelectedPlaybackTarget = Self.playbackOutputTarget(
            from: userDefaults.string(forKey: Self.selectedPlaybackTargetKey)
        )
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
        if selectedPlaybackTarget != updatedSelectedPlaybackTarget {
            selectedPlaybackTarget = updatedSelectedPlaybackTarget
        }
        if echoScribedToSpeakers != updatedEchoScribedToSpeakers {
            echoScribedToSpeakers = updatedEchoScribedToSpeakers
        }
    }

    private func reloadSpeakerSettings() {
        let rawSpeakerOutputProgram = userDefaults.object(forKey: Self.speakerOutputProgramKey) as? Int
        let updatedSpeakerOutputProgram = Self.validSpeakerOutputProgram(rawSpeakerOutputProgram)
        let rawSpeakerOutputProgramText = rawSpeakerOutputProgram.map(String.init) ?? "nil"
        if speakerOutputProgram != updatedSpeakerOutputProgram {
            #if DEBUG
            NSLog(
                "MIDI Scribe speaker program debug: settings reload changed " +
                    "old=\(speakerOutputProgram) new=\(updatedSpeakerOutputProgram) " +
                    "rawUserDefault=\(rawSpeakerOutputProgramText)"
            )
            #endif
            speakerOutputProgram = updatedSpeakerOutputProgram
            return
        }
        if rawSpeakerOutputProgram != updatedSpeakerOutputProgram {
            #if DEBUG
            NSLog(
                "MIDI Scribe speaker program debug: settings reload normalizing " +
                    "rawUserDefault=\(rawSpeakerOutputProgramText) " +
                    "resolved=\(updatedSpeakerOutputProgram)"
            )
            #endif
            userDefaults.set(updatedSpeakerOutputProgram, forKey: Self.speakerOutputProgramKey)
        }
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

    static func validSpeakerOutputProgram(_ program: Int?) -> Int {
        guard
            let program,
            GeneralMIDI.programs.contains(where: { $0.program == program })
        else {
            return defaultSpeakerOutputProgram
        }
        return program
    }

    static func playbackOutputTarget(from preferenceValue: String?) -> PlaybackOutputTarget {
        guard let preferenceValue else { return defaultPlaybackOutputTarget }
        if preferenceValue == "speakers" {
            return .osSpeakers
        }
        if let channelText = preferenceValue.split(separator: ":", maxSplits: 1).last,
           preferenceValue.hasPrefix("midiChannel:"),
           let channel = Int(channelText),
           (1...16).contains(channel) {
            return .midiChannel(channel)
        }
        return defaultPlaybackOutputTarget
    }

    static func playbackOutputTargetPreferenceValue(for target: PlaybackOutputTarget) -> String {
        switch target {
        case .osSpeakers:
            return "speakers"
        case .midiChannel(let channel):
            return "midiChannel:\(channel)"
        }
    }

    static func controlChangeSet(
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
