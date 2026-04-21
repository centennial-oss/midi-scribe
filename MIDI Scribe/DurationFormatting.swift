//
//  DurationFormatting.swift
//  MIDI Scribe
//

import Foundation

enum DurationFormatting {
    /// Whole-second display for short UI labels: `42s` when under one minute,
    /// `3m 5s` when a minute or longer (minutes omitted below 60s).
    static func compactWholeSeconds(_ timeInterval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(timeInterval))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        if minutes == 0 {
            return "\(remainingSeconds)s"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }
}
