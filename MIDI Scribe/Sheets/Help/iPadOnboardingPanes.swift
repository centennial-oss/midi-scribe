//
//  iPadOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let iPadScreenshotSize = CGSize(width: 2732, height: 2048)

let iPadOnboardingPaneCollection = OnboardingPaneCollection(
    device: .iPad,
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
                    assetName: "Help/ScreenShots/iPad/start-take-idle-sidebar",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-live-start",
                            sourceX: 620,
                            sourceY: 1740,
                            label: "Start a Take here, from the Take menu, or with your configured shortcut.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "ipad-live-roll",
                            sourceX: 1850,
                            sourceY: 760,
                            label: "The piano roll fills in live as MIDI arrives.",
                            caretPosition: .top
                        )
                    ],
                    undimmedZones: [
                        .roundedRect(centerX: 1360, centerY: 1030, width: 2200, height: 1400, cornerRadius: 36),
                        .roundedRect(centerX: 620, centerY: 1740, width: 560, height: 220, cornerRadius: 24)
                    ]
                )
            )
        ),
        OnboardingPane(
            id: 2,
            title: "Ending a Take",
            content: .screenshot(
                OnboardingScreenshotContent(
                    assetName: "Help/ScreenShots/iPad/start-take-idle-sidebar",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-live-stop",
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
                    assetName: "Help/ScreenShots/iPad/saved-take",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-playback-controls",
                            sourceX: 1500,
                            sourceY: 1760,
                            label: "Playback controls let you rewind, play or pause, and restart.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "ipad-playback-playhead",
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
                    assetName: "Help/ScreenShots/iPad/saved-take",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-playback-zoom",
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
                    assetName: "Help/ScreenShots/iPad/saved-take-sidebar",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-edit-actions",
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
                    assetName: "Help/ScreenShots/iPad/OnboardingRegularBulkEdit",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-bulk-actions",
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
                    assetName: "Help/ScreenShots/iPad/OnboardingRegularSettings",
                    originalSize: iPadScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "ipad-settings",
                            sourceX: 2060,
                            sourceY: 420,
                            label: "Use Settings to tune recording triggers and \(AppIdentifier.name) behavior.",
                            caretPosition: .none
                        )
                    ],
                    undimmedZones: [
                        .circle(centerX: 2060, centerY: 420, diameter: 280)
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
