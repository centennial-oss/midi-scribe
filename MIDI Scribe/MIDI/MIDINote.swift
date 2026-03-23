//
//  MIDINote.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import Foundation

struct MIDINote: Equatable, Identifiable {
    let noteNumber: UInt8
    let velocity: UInt8
    let channel: UInt8

    var id: String {
        "\(channel)-\(noteNumber)"
    }

    var displayName: String {
        let names = ["C", "C\u{266F}", "D", "E\u{266D}", "E", "F", "F\u{266F}", "G", "A\u{266D}", "A", "B\u{266D}", "B"]
        let octave = Int(noteNumber) / 12 - 1
        let pitchClass = Int(noteNumber) % 12
        return "\(names[pitchClass])\(octave)"
    }
}
