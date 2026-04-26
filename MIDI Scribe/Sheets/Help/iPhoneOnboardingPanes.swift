//
//  iPhoneOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let iPhoneScreenshotSize = CGSize(width: 2796, height: 1290)

let iPhoneOnboardingPaneCollection = OnboardingPaneCollection(
    device: .iPhone,
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
                    assetName: "OnboardingPhoneLiveTake",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-live-start",
                            sourceX: 520,
                            sourceY: 1080,
                            label: "Start a Take from here. When recording begins, this becomes the live capture view.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "phone-live-roll",
                            sourceX: 1760,
                            sourceY: 420,
                            label: "The piano roll fills in as you play. Live capture is read-only.",
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
                    assetName: "OnboardingPhoneLiveTake",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-live-stop",
                            sourceX: 1420,
                            sourceY: 1095,
                            label: "Stop saves the Take. Trash cancels the recording without keeping it.",
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
                    assetName: "OnboardingPhonePlayback",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-playback-controls",
                            sourceX: 1360,
                            sourceY: 1080,
                            label: "Use rewind, play or pause, and restart to review a saved Take.",
                            caretPosition: .bottom
                        ),
                        OnboardingAnnotation(
                            id: "phone-playback-playhead",
                            sourceX: 1780,
                            sourceY: 350,
                            label: "Tap in the roll to move the playhead. Drag its handle to scrub while paused.",
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
                    assetName: "OnboardingPhonePlayback",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-playback-zoom",
                            sourceX: 2060,
                            sourceY: 575,
                            label: "Drag a rectangle across the piano roll to zoom into that region.",
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
                    assetName: "OnboardingPhoneEditing",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-edit-actions",
                            sourceX: 2360,
                            sourceY: 250,
                            label: "Rename, split at the playhead, star, or export the selected Take.",
                            caretPosition: .right
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
                    assetName: "OnboardingPhoneBulkEdit",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-bulk-actions",
                            sourceX: 1390,
                            sourceY: 1090,
                            label: """
                            Bulk edit lets you select multiple Takes.
                            Merge appears after two or more are selected.
                            """,
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
                    assetName: "OnboardingPhoneSettings",
                    originalSize: iPhoneScreenshotSize,
                    annotations: [
                        OnboardingAnnotation(
                            id: "phone-settings",
                            sourceX: 2230,
                            sourceY: 210,
                            label: "Settings controls recording triggers and app behavior.",
                            caretPosition: .top
                        )
                    ],
                    undimmedZones: [
                        .circle(centerX: 2230, centerY: 210, diameter: 250)
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
