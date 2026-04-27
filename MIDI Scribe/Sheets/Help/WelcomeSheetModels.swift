//
//  WelcomeSheetModels.swift
//  MIDI Scribe
//

import SwiftUI

enum OnboardingDeviceType: Hashable {
    case iPhone
    case iPad
    case macOS
}

struct OnboardingPaneCollection: Hashable {
    let device: OnboardingDeviceType
    let onboardingPanes: [OnboardingPane]
}

struct OnboardingPane: Identifiable, Hashable {
    let id: Int
    var title: String?
    let content: OnboardingPaneContent
    var isShownInHelp = true
    var hideCloseButton = false
}

enum OnboardingPaneContent: Hashable {
    case message(OnboardingMessageKind)
    case screenshot(OnboardingScreenshotContent)
}

enum OnboardingMessageKind: Hashable {
    case welcome
    case happyScribing

    var header: String {
        switch self {
        case .welcome:
            return "Welcome to \(AppIdentifier.name)!"
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
    case none
}

struct OnboardingScreenshotContent: Hashable {
    let assetName: String
    let originalSize: CGSize
    let annotations: [OnboardingAnnotation]
    let undimmedZones: [OnboardingUndimmedZone]

    init(
        assetName: String,
        originalSize: CGSize,
        annotations: [OnboardingAnnotation],
        undimmedZones: [OnboardingUndimmedZone] = []
    ) {
        self.assetName = assetName
        self.originalSize = originalSize
        self.annotations = annotations
        self.undimmedZones = undimmedZones
    }
}

enum OnboardingUndimmedZone: Hashable {
    case roundedRect(
        centerX: CGFloat,
        centerY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    )
    case circle(
        centerX: CGFloat,
        centerY: CGFloat,
        diameter: CGFloat
    )
}

struct OnboardingAnnotation: Identifiable, Hashable {
    let id: String
    // Coordinates are measured against the original screenshot size for this platform.
    let sourceX: CGFloat
    let sourceY: CGFloat
    let label: String
    let caretPosition: OnboardingCaretPosition
    let avoidsLineWrapping: Bool

    init(
        id: String,
        sourceX: CGFloat,
        sourceY: CGFloat,
        label: String,
        caretPosition: OnboardingCaretPosition,
        avoidsLineWrapping: Bool = false
    ) {
        self.id = id
        self.sourceX = sourceX
        self.sourceY = sourceY
        self.label = label
        self.caretPosition = caretPosition
        self.avoidsLineWrapping = avoidsLineWrapping
    }
}
