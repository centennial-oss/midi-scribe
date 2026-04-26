//
//  BuildInfo.swift
//  MIDI Scribe
//
//  Version and build metadata. BuildInfo.generated.swift is produced by the
//  "Generate Build Info" Run Script phase and supplies commit, date, and arch.
//

import Foundation
#if os(iOS)
import UIKit
#endif

enum BuildInfo {
    /// Semantic version (from Info.plist / MARKETING_VERSION). Use TAGVER at build to override.
    nonisolated static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "local"
    }

    static var commit: String { BuildInfoGenerated.buildCommit }
    static var buildDate: String { BuildInfoGenerated.buildDate }
    static var buildType: String { BuildInfoGenerated.buildConfiguration }
    static var buildArch: String { BuildInfoGenerated.buildArch }

    #if os(iOS)
    nonisolated static let isPhonePad = true
    nonisolated static let isPhone = UIDevice.current.userInterfaceIdiom == .phone
    nonisolated static let isPad = UIDevice.current.userInterfaceIdiom == .pad
    nonisolated static let isMac = false
    nonisolated static let platform: String = "iOS"
    nonisolated static let deviceOS: String = isPad ? "iPadOS" : "iOS"
    #elseif os(macOS)
    nonisolated static let isPhonePad = false
    nonisolated static let isPhone = false
    nonisolated static let isPad = false
    nonisolated static let isMac = true
    nonisolated static let platform: String = "macOS"
    nonisolated static let deviceOS: String = "macOS"
    #endif

    /// Copyable blob for support/debug (e.g. paste into issues).
    static var copyableBlob: String {
        """
        Version: \(version) (\(deviceOS), \(buildArch))
        Commit: \(commit)
        Date: \(buildDate)
        Build Type: \(buildType)
        """
    }
}
