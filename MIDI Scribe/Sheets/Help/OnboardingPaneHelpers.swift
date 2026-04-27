//
//  OnboardingPaneHelpers.swift
//  MIDI Scribe
//

import SwiftUI

func screenshotContent(
    assetName: String,
    originalSize: CGSize,
    annotations: [OnboardingAnnotation],
    undimmedZones: [OnboardingUndimmedZone] = []
) -> OnboardingPaneContent {
    .screenshot(
        OnboardingScreenshotContent(
            assetName: assetName,
            originalSize: originalSize,
            annotations: annotations,
            undimmedZones: undimmedZones
        )
    )
}

func stubAnnotation(
    _ sourceX: CGFloat,
    _ sourceY: CGFloat,
    _ label: String,
    _ caret: OnboardingCaretPosition,
    avoidsLineWrapping: Bool = false
) -> OnboardingAnnotation {
    OnboardingAnnotation(
        id: "\(Int(sourceX))-\(Int(sourceY))-\(label)",
        sourceX: sourceX,
        sourceY: sourceY,
        label: label,
        caretPosition: caret,
        avoidsLineWrapping: avoidsLineWrapping
    )
}
