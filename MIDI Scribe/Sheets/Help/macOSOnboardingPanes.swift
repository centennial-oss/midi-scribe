//
//  macOSOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let macOSScreenshotSize = CGSize(width: 2732, height: 2048)

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
            title: "Live Capture",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularLiveTake",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-live-start",
                            sourceX: 620,
                            sourceY: 1740,
                            label: "Start a Take here, from the Take menu, or with your configured shortcut.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "mac-live-roll",
                            sourceX: 1850,
                            sourceY: 760,
                            label: "The piano roll fills in live as MIDI arrives.",
                            caretPosition: .top
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 2,
            title: "Ending a Take",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularLiveTake",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-live-stop",
                            sourceX: 1320,
                            sourceY: 1780,
                            label: "Stop ends and saves the Take. Trash cancels the recording.",
                            caretPosition: .bottom
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 3,
            title: "Playback Controls",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularPlayback",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-playback-controls",
                            sourceX: 1500,
                            sourceY: 1760,
                            label: "Playback controls let you rewind, play or pause, and restart.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "mac-playback-playhead",
                            sourceX: 1900,
                            sourceY: 650,
                            label: "Click the roll to move the playhead. Drag the handle to scrub.",
                            caretPosition: .top
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 4,
            title: "Zooming the Piano Roll",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularPlayback",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-playback-zoom",
                            sourceX: 2100,
                            sourceY: 820,
                            label: "Drag across the piano roll to zoom into a selected region.",
                            caretPosition: .right
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 5,
            title: "Take Actions",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularEditing",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-edit-actions",
                            sourceX: 480,
                            sourceY: 620,
                            label: "Per-Take actions include rename, split at the playhead, star, and export.",
                            caretPosition: .left
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 6,
            title: "Bulk Edit",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularBulkEdit",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-bulk-actions",
                            sourceX: 560,
                            sourceY: 1640,
                            label: "Select multiple Takes to star, delete, or merge them together.",
                            caretPosition: .bottom
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 7,
            title: "Settings",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "OnboardingRegularSettings",
                    originalSize: macOSScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "mac-settings",
                            sourceX: 2060,
                            sourceY: 420,
                            label: "Use Settings to tune recording triggers and MIDI Scribe behavior.",
                            caretPosition: .top
                        )
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 8,
            content: .message(.happyScribing)
        )
    ]
)
