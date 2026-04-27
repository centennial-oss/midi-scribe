//
//  iPhoneOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let iPhoneScreenshotSize = CGSize(width: 2622, height: 1206)

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
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-01-start",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1311,
                        1100,
                        "This tour of \(AppIdentifier.name) presents screen shots and is not interactive.",
                        .none,
                        avoidsLineWrapping: true
                    ),
                    stubAnnotation(
                        1042,
                        466,
                        "Scribe a Take by playing your instrument or pressing the button",
                        .right
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1311, centerY: 468, width: 570, height: 148, cornerRadius: 75)
                ]
            )
        ),
        OnboardingPane(
            id: 2,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-02-capturing",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(
                        670,
                        686,
                        "The Piano Roll fills in while you play",
                        .bottom
                    ),
                    stubAnnotation(
                        1840,
                        198,
                        "Takes auto-end after a configurable timeout. Manually end or discard them here",
                        .top
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1310, centerY: 765, width: 2100, height: 165, cornerRadius: 36),
                    .roundedRect(centerX: 1840, centerY: 138, width: 270, height: 118, cornerRadius: 60)
                ]
            )
        ),
        OnboardingPane(
            id: 3,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-03-completed-zooming",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(
                        245,
                        355,
                        "Playback starts at the Playhead position",
                        .left
                    ),
                    stubAnnotation(
                        1855,
                        535,
                        "Swipe 2 fingers over\nthe Piano Roll to\nselect and zoom",
                        .left
                    ),
                    stubAnnotation(
                        832,
                        1025,
                        "Pinch the Piano Roll to zoom freely",
                        .none,
                        avoidsLineWrapping: true
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1297, centerY: 711, width: 2255, height: 790, cornerRadius: 28)
                ]
            ) // 2254x787@1301,712
        ),
        OnboardingPane(
            id: 4,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-04-drag-star",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1197,
                        365,
                        "Drag the Playhead handle to adjust the playback position",
                        .right
                    ),
                    stubAnnotation(1936, 198, "Star notable Takes\nto keep long-term", .top),
                    stubAnnotation(250, 132, "Open the Sidebar to switch Takes", .left, avoidsLineWrapping: true)
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1233, centerY: 714, width: 100, height: 794, cornerRadius: 50),
                    .roundedRect(centerX: 1936, centerY: 138, width: 118, height: 118, cornerRadius: 60),
                    .roundedRect(centerX: 180, centerY: 139, width: 128, height: 128, cornerRadius: 65)
                ]
            )
        ),
        OnboardingPane(
            id: 5,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-05-sidebar",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1166,
                        782,
                        "On the Sidebar, use multi-select to operate on several Takes at once",
                        .left
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 700, centerY: 612, width: 1012, height: 1170, cornerRadius: 60)
                ]
            )
        ),
        OnboardingPane(
            id: 7,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPhone/iPhone-07-settings",
                originalSize: iPhoneScreenshotSize,
                annotations: [
                    stubAnnotation(1425, 303, "In Settings, tune when\nto auto-end live Takes", .bottom),
                    stubAnnotation(555, 695, "Use pedals to\nmanually start\nand end Takes", .right),
                    stubAnnotation(1826, 996, "Load sample Takes to try out \(AppIdentifier.name) features", .bottom)
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1312, centerY: 690, width: 1622, height: 815, cornerRadius: 36)
                ]
            )
        ),
        OnboardingPane(
            id: 7,
            content: .message(.happyScribing)
        )
    ]
)
