//
//  macOSOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let macOSScreenshotSize = CGSize(width: 2000, height: 1504)

let macOSOnboardingPaneCollection = OnboardingPaneCollection(
    device: .macOS,
    onboardingPanes: [
        OnboardingPane(
            id: 0,
            content: .message(.welcome),
            isShownInHelp: false
        ),
        OnboardingPane(
            id: 1,
            title: "Start a New Take",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-01-start",
                annotations: [
                    stubAnnotation(
                        "mac-start-primary",
                        810,
                        670,
                        "Scribe your first Take by playing your instrument or pressing the green button",
                        .right
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1265, centerY: 670, width: 400, height: 90, cornerRadius: 36)
                ]
            )
        ),
        OnboardingPane(
            id: 2,
            title: "Take in Progress",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-02-capturing",
                annotations: [
                    stubAnnotation(
                        "mac-capturing-roll",
                        1120,
                        710,
                        "The Piano Roll will fill in while you play",
                        .bottom
                    ),
                    stubAnnotation(
                        "mac-capturing-stop",
                        1680,
                        240,
                        "Takes auto-end after a configurable timeout. Manually end or discard an in-progress Take here",
                        .top
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1265, centerY: 900, width: 1370, height: 400, cornerRadius: 36),
                    .roundedRect(centerX: 1690, centerY: 60, width: 155, height: 70, cornerRadius: 50)
                ]
            )
        ),
        OnboardingPane(
            id: 3,
            title: "Completed Take",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-03-completed-zooming",
                annotations: [
                    stubAnnotation(
                        "mac-completed-controls",
                        325,
                        200,
                        "Playback starts at the Playhead position",
                        .right
                    ),
                    stubAnnotation(
                        "mac-completed-zoom",
                        1620,
                        430,
                        "Click and drag on the\nPiano Roll to zoom to the selected area",
                        .left
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1265, centerY: 825, width: 1370, height: 1290, cornerRadius: 18)
                ]
            )
        ),
        OnboardingPane(
            id: 4,
            title: "Completed Take",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-04-drag-star",
                annotations: [
                    stubAnnotation(
                        "mac-drag-selection",
                        1080,
                        210,
                        "Click and Drag the Playhead handle to adjust the playback position",
                        .right
                    ),
                    stubAnnotation("mac-drag-actions", 1795, 200, "Star notable Takes\nto keep long-term", .top)
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1375, centerY: 825, width: 200, height: 1290, cornerRadius: 36),
                    .roundedRect(centerX: 1797, centerY: 60, width: 70, height: 70, cornerRadius: 50),
                    .roundedRect(centerX: 205, centerY: 600, width: 370, height: 180, cornerRadius: 24)
                ]
            )
        ),
        OnboardingPane(
            id: 5,
            title: "Bulk Editing",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-05-bulk",
                annotations: [
                    stubAnnotation(
                        "mac-bulk-edit",
                        465,
                        415,
                        "Use multi-select to operate on several Takes at once",
                        .bottom
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 270, centerY: 775, width: 500, height: 540, cornerRadius: 24)
                ]
            )
        ),
        OnboardingPane(
            id: 6,
            title: "Settings",
            content: screenshotContent(
                assetName: "Help/ScreenShots/macOS/macOS-06-settings",
                annotations: [
                    stubAnnotation("mac-settings-midi", 1660, 365, "Customize when to\nauto-end live Takes", .left),
                    stubAnnotation("mac-settings-pedal-start", 302, 695, "Use pedals to manually start and end Takes", .right),
                    stubAnnotation("mac-settings-samples", 1709, 905, "Load sample Takes to try out \(AppIdentifier.name) features", .left)
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1000, centerY: 752, width: 940, height: 1240, cornerRadius: 50)
                ]
            )
        ),
        OnboardingPane(
            id: 7,
            content: .message(.happyScribing)
        )
    ]
)

private func screenshotContent(
    assetName: String,
    annotations: [OnboardingAnnotation],
    undimmedZones: [OnboardingUndimmedZone] = []
) -> OnboardingPaneContent {
    .screenshot(
        OnboardingScreenshotContent(
            assetName: assetName,
            originalSize: macOSScreenshotSize,
            annotations: annotations,
            undimmedZones: undimmedZones
        )
    )
}

private func stubAnnotation(
    _ id: String,
    _ sourceX: CGFloat,
    _ sourceY: CGFloat,
    _ label: String,
    _ caret: OnboardingCaretPosition
) -> OnboardingAnnotation {
    OnboardingAnnotation(
        id: id,
        sourceX: sourceX,
        sourceY: sourceY,
        label: label,
        caretPosition: caret
    )
}
