import Foundation
import SwiftData

extension TakePersistenceService {
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
        let rawBase = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = rawBase.isEmpty ? "Imported MIDI" : rawBase
        let existing = (try? context.fetch(FetchDescriptor<StoredTake>()).map(\.displayTitle)) ?? []
        let usedTitles = Set(existing)
        guard usedTitles.contains(baseTitle) else { return baseTitle }

        var suffix = 2
        while usedTitles.contains("\(baseTitle) (\(suffix))") {
            suffix += 1
        }
        return "\(baseTitle) (\(suffix))"
    }
}
