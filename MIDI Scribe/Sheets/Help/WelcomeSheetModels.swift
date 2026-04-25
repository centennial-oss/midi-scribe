//
//  WelcomeSheetModels.swift
//  MIDI Scribe
//

import SwiftUI

struct OnboardingPane: Identifiable, Hashable {
    let id: Int
    var title: String?
    let content: OnboardingPaneContent
    var isShownInHelp = true
    var hideCloseButton = false
    var isPaneHidden = false
}

enum OnboardingPaneContent: Hashable {
    case message(OnboardingMessageKind)
    case screenshot(OnboardingScreenshotAsset, OnboardingAnnotationSet)
}

enum OnboardingMessageKind: Hashable {
    case welcome
    case happyScribing

    var header: String {
        switch self {
        case .welcome:
            return "Welcome to \(BuildInfo.appName)!"
        case .happyScribing:
            return "Happy Scribing!"
        }
    }

    var body: String? {
        switch self {
        case .welcome:
            return "Swipe left to start a quick tour"
        case .happyScribing:
            return nil
        }
    }
}

enum OnboardingCaretPosition: Hashable {
    case top
    case left
    case right
    case bottom
}

struct OnboardingScreenshotAsset: Hashable {
    let phoneName: String
    let phoneOriginalSize: CGSize
    let regularName: String
    let regularOriginalSize: CGSize

    func name() -> String {
        BuildInfo.isPhone ? phoneName : regularName
    }

    func originalSize() -> CGSize {
        BuildInfo.isPhone ? phoneOriginalSize : regularOriginalSize
    }
}

struct OnboardingAnnotationSet: Hashable {
    let phone: [OnboardingAnnotation]
    let regular: [OnboardingAnnotation]

    func annotations() -> [OnboardingAnnotation] {
        BuildInfo.isPhone ? phone : regular
    }
}

struct OnboardingAnnotation: Identifiable, Hashable {
    let id: String
    // Coordinates are measured against the original screenshot size for this platform.
    let sourceX: CGFloat
    let sourceY: CGFloat
    let label: String
    let caretPosition: OnboardingCaretPosition
}

extension OnboardingScreenshotAsset {
    static let liveTake = OnboardingScreenshotAsset(
        phoneName: "OnboardingPhoneLiveTake",
        phoneOriginalSize: CGSize(width: 2796, height: 1290),
        regularName: "OnboardingRegularLiveTake",
        regularOriginalSize: CGSize(width: 2732, height: 2048)
    )

    static let playback = OnboardingScreenshotAsset(
        phoneName: "OnboardingPhonePlayback",
        phoneOriginalSize: CGSize(width: 2796, height: 1290),
        regularName: "OnboardingRegularPlayback",
        regularOriginalSize: CGSize(width: 2732, height: 2048)
    )

    static let editing = OnboardingScreenshotAsset(
        phoneName: "OnboardingPhoneEditing",
        phoneOriginalSize: CGSize(width: 2796, height: 1290),
        regularName: "OnboardingRegularEditing",
        regularOriginalSize: CGSize(width: 2732, height: 2048)
    )

    static let bulkEdit = OnboardingScreenshotAsset(
        phoneName: "OnboardingPhoneBulkEdit",
        phoneOriginalSize: CGSize(width: 2796, height: 1290),
        regularName: "OnboardingRegularBulkEdit",
        regularOriginalSize: CGSize(width: 2732, height: 2048)
    )

    static let settings = OnboardingScreenshotAsset(
        phoneName: "OnboardingPhoneSettings",
        phoneOriginalSize: CGSize(width: 2796, height: 1290),
        regularName: "OnboardingRegularSettings",
        regularOriginalSize: CGSize(width: 2732, height: 2048)
    )
}
