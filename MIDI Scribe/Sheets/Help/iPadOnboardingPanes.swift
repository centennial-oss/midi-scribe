//
//  iPadOnboardingPanes.swift
//  MIDI Scribe
//

import SwiftUI

private let iPadScreenshotSize = CGSize(width: 2000, height: 1504)

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
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-01-start",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1250,
                        180,
                        "This tour of \(AppIdentifier.name) presents screen shots and is not interactive.",
                        .none,
                        avoidsLineWrapping: true
                    ),
                    stubAnnotation(
                        810,
                        670,
                        "Scribe your first Take by\nplaying your instrument\nor pressing the button",
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
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-02-capturing",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1120,
                        710,
                        "The Piano Roll fills\nin while you play",
                        .bottom
                    ),
                    stubAnnotation(
                        1680,
                        240,
                        "Takes auto-end after a\nconfigurable timeout.\n" +
                            "Manually end or discard\nan in-progress Take here",
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
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-03-completed-zooming",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(
                        325,
                        200,
                        "Playback starts at the\nPlayhead position",
                        .right
                    ),
                    stubAnnotation(
                        1620,
                        430,
                        "Drag 2 fingers on the\nPiano Roll to zoom to\nthe selected area",
                        .left
                    ),
                    stubAnnotation(
                        1600,
                        1300,
                        "Drag 3 fingers to zoom freely",
                        .none,
                        avoidsLineWrapping: true
                    )
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1265, centerY: 823, width: 1370, height: 1295, cornerRadius: 18)
                ]
            )
        ),
        OnboardingPane(
            id: 4,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-04-drag-star",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(
                        1100,
                        210,
                        "Drag the Playhead\nhandle to adjust the\nplayback position",
                        .right
                    ),
                    stubAnnotation(1790, 200, "Star notable Takes\nto keep long-term", .top)
                ],
                undimmedZones: [
                    .roundedRect(centerX: 1375, centerY: 823, width: 200, height: 1295, cornerRadius: 36),
                    .roundedRect(centerX: 1797, centerY: 60, width: 70, height: 70, cornerRadius: 50),
                    .roundedRect(centerX: 205, centerY: 600, width: 370, height: 180, cornerRadius: 24)
                ]
            )
        ),
        OnboardingPane(
            id: 5,
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-05-bulk",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(
                        465,
                        385,
                        "Use multi-select to\noperate on several\nTakes at once",
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
            title: "",
            content: screenshotContent(
                assetName: "Help/ScreenShots/iPad/iPad-06-settings",
                originalSize: iPadScreenshotSize,
                annotations: [
                    stubAnnotation(1660, 365, "Customize when to\nauto-end live Takes", .left),
                    stubAnnotation(302, 695, "Use pedals to manually\nstart and end Takes", .right),
                    stubAnnotation(1690, 905, "Load sample Takes to\ntry out \(AppIdentifier.name)\nfeatures", .left)
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
