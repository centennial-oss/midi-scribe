//
//  AppIdentifier.swift
//  MIDI Scribe
//

import Foundation

enum AppIdentifier {
    nonisolated static let bundleID = Bundle.main.bundleIdentifier!
    nonisolated static let appStoreID = "6760952962"

    nonisolated static func scoped(_ suffix: String) -> String {
        "\(bundleID).\(suffix)"
    }

    nonisolated static func logBundleIdentifier() {
        #if DEBUG
        NSLog("[AppInfo] \(BuildInfo.appName) bundle identifier: \(bundleID) (source: Bundle.main)")
        #endif
    }
}
