//
//  ContentViewExportFilenameTests.swift
//  MIDI ScribeTests
//

import Testing
@testable import MIDI_Scribe

struct ContentViewExportFilenameTests {
    @MainActor
    @Test func appendsMidWhenMissingExtension() {
        let contentView = ContentView(settings: AppSettings(userDefaults: UserDefaults()))
        #expect(contentView.suggestedExportFilename(from: "My Take") == "My Take.mid")
    }

    @MainActor
    @Test func preservesMidExtensionCaseInsensitive() {
        let contentView = ContentView(settings: AppSettings(userDefaults: UserDefaults()))
        #expect(contentView.suggestedExportFilename(from: "My Take.MID") == "My Take.MID")
    }

    @MainActor
    @Test func preservesMidiExtensionCaseInsensitive() {
        let contentView = ContentView(settings: AppSettings(userDefaults: UserDefaults()))
        #expect(contentView.suggestedExportFilename(from: "My Take.mIdI") == "My Take.mIdI")
    }
}
