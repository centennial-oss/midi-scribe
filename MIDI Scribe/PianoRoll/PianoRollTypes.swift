//
//  PianoRollTypes.swift
//  MIDI Scribe
//

import SwiftUI

let pianoRollSustainCCColor = Color(red: 0.5, green: 0, blue: 1).opacity(0.7)
let pianoRollSostenutoCCColor = Color(red: 0.9, green: 0, blue: 0.9).opacity(0.7)
let pianoRollSoftCCColor = Color.teal.opacity(0.6)
let pianoRollOtherCCColor = Color(white: 0.45).opacity(0.45)

struct PianoRollNote: Identifiable {
    let id = UUID()
    let pitch: UInt8
    let channel: UInt8
    let velocity: UInt8
    let startOffset: TimeInterval
    var duration: TimeInterval
}

enum PianoRollCCKind: CaseIterable {
    case sustain
    case soft
    case sostenuto
    case other

    var laneIndex: Int {
        switch self {
        case .sustain: return 0
        case .sostenuto: return 1
        case .soft: return 2
        case .other: return 3
        }
    }

    var color: Color {
        switch self {
        case .sustain: return pianoRollSustainCCColor
        case .soft: return pianoRollSoftCCColor
        case .sostenuto: return pianoRollSostenutoCCColor
        case .other: return pianoRollOtherCCColor
        }
    }
}

struct PianoRollCC: Identifiable {
    let id = UUID()
    let kind: PianoRollCCKind
    let startOffset: TimeInterval
    var duration: TimeInterval
}
