//
//  OnboardingPresentationKind.swift
//  MIDI Scribe
//

import Foundation

enum OnboardingPresentationKind {
    case welcome
    case help

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to \(BuildInfo.appName)"
        case .help:
            return "\(BuildInfo.appName) Help"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "A quick tour of recording, playback, editing, and export."
        case .help:
            return "A quick reference for recording, playback, editing, and export."
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .welcome:
            return "Get Started"
        case .help:
            return "Close"
        }
    }
}
