import Foundation
import SwiftData

extension TakePersistenceService {
#if os(iOS)
    private static let sharedImportAppGroupID = "group.org.centennialoss.midiscribe"
#endif
    private static let sharedImportDirectoryName = "SharedIncoming"

    struct ImportedTakeResult: Sendable, Equatable {
        let id: UUID
        let title: String
    }

    func importMIDIFile(from url: URL) async throws -> ImportedTakeResult {
        try await runReturning { context in
            let title = Self.resolvedImportedTitle(from: url, in: context)
            let data = try Data(contentsOf: url)
            let take = try StandardMIDIFileReader.take(from: data, title: title)
            let stored = StoredTake(recordedTake: take)
            stored.title = title
            context.insert(stored)
            try context.save()
            return ImportedTakeResult(id: take.id, title: title)
        }
    }

    private static func resolvedImportedTitle(from url: URL, in context: ModelContext) -> String {
        let rawBase = sharedImportDisplayBaseName(from: url) ?? url.deletingPathExtension().lastPathComponent
        let sanitizedBase = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = sanitizedBase.isEmpty ? "Imported MIDI" : sanitizedBase
        let existing = (try? context.fetch(FetchDescriptor<StoredTake>()).map(\.displayTitle)) ?? []
        let usedTitles = Set(existing)
        guard usedTitles.contains(baseTitle) else { return baseTitle }

        var suffix = 2
        while usedTitles.contains("\(baseTitle) (\(suffix))") {
            suffix += 1
        }
        return "\(baseTitle) (\(suffix))"
    }

    private static func sharedImportDisplayBaseName(from url: URL) -> String? {
        guard isSharedImportFile(url) else { return nil }

        let rawBase = url.deletingPathExtension().lastPathComponent
        let prefixLength = 36
        guard rawBase.count > prefixLength + 1 else { return nil }

        let prefixEndIndex = rawBase.index(rawBase.startIndex, offsetBy: prefixLength)
        let separatorIndex = prefixEndIndex
        guard rawBase[separatorIndex] == "-" else { return nil }

        let prefix = String(rawBase[..<prefixEndIndex])
        guard UUID(uuidString: prefix) != nil else { return nil }

        let trimmedStartIndex = rawBase.index(after: separatorIndex)
        let trimmed = String(rawBase[trimmedStartIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isSharedImportFile(_ url: URL) -> Bool {
#if os(iOS)
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: sharedImportAppGroupID
        ) else {
            return false
        }

        let incomingDirectory = containerURL.appendingPathComponent(
            sharedImportDirectoryName,
            isDirectory: true
        )
        let standardizedIncoming = incomingDirectory.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path
        return standardizedURL.hasPrefix(standardizedIncoming + "/")
#else
        return false
#endif
    }
}
