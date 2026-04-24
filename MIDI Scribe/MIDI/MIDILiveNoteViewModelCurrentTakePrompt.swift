//
//  MIDILiveNoteViewModelCurrentTakePrompt.swift
//  MIDI Scribe
//

import Foundation

extension MIDILiveNoteViewModel {
    var currentTakeStartMethods: [String] {
        guard settings.isScribingEnabled else { return [] }

        var methods: [String] = []
        if settings.startTakeWithNoteEvents {
            methods.append("Start playing your MIDI instrument\(monitoredChannelSuffix)")
        }
        if settings.takeStartControlChanges.contains(64) {
            methods.append("Press and release the Sustain Pedal")
        }
        if settings.takeStartControlChanges.contains(66) {
            methods.append("Press and release the Sostenuto Pedal")
        }
        if settings.takeStartControlChanges.contains(67) {
            methods.append("Press and release the Soft Pedal")
        }
        if settings.takeStartControlChanges.contains(where: { ![64, 66, 67].contains($0) }) {
            methods.append("Send other MIDI Control Changes")
        }
        return methods
    }

    private var monitoredChannelSuffix: String {
        if settings.monitoredMIDIChannel == AppSettings.midiChannelAllValue {
            return ""
        }
        return " on Channel \(settings.monitoredMIDIChannel)"
    }
}
