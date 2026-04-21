//
//  PianoRollTypes.swift
//  MIDI Scribe
//

import SwiftUI

struct PianoRollNote: Identifiable {
    let id = UUID()
    let pitch: UInt8
    let channel: UInt8
    let velocity: UInt8
    let startOffset: TimeInterval
    var duration: TimeInterval
}

enum PianoRollCCKind {
    case sustain
    case sostenuto
    case soft
    case other

    var color: Color {
        switch self {
        case .sustain: return .purple.opacity(0.8)
        case .sostenuto: return .orange.opacity(0.8)
        case .soft: return .blue.opacity(0.8)
        case .other: return .yellow.opacity(0.8)
        }
    }
}

struct PianoRollCC: Identifiable {
    let id = UUID()
    let kind: PianoRollCCKind
    let startOffset: TimeInterval
    var duration: TimeInterval
}
