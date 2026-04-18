//
//  MIDIFileDocument.swift
//  MIDI Scribe
//
//  FileDocument adapter so we can present a native save sheet via
//  SwiftUI's .fileExporter. Write-only; we never read .mid files back in.
//

import SwiftUI
import UniformTypeIdentifiers

struct MIDIFileDocument: FileDocument {
    static let readableContentTypes: [UTType] = []
    static let writableContentTypes: [UTType] = [.midi]

    let data: Data
    let suggestedFileName: String

    init(take: RecordedTake) {
        self.data = StandardMIDIFileWriter.data(for: take)
        self.suggestedFileName = Self.sanitize(take.displayTitle)
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    /// Replace characters that would be illegal or annoying in a file name
    /// (slashes, colons, etc.) so the suggested name is usable on all targets.
    private static func sanitize(_ input: String) -> String {
        let disallowed = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let replaced = input.unicodeScalars
            .map { disallowed.contains($0) ? "-" : Character($0) }
            .map(String.init)
            .joined()
        let trimmed = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "take" : trimmed
    }
}
