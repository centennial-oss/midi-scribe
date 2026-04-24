import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func importPendingSharedFilesIfAny() {
        guard canAttemptAutomaticSharedImport else {
#if DEBUG
            NSLog(
                "[Import] Skipping pending shared import scan; storageReady=%@ pendingOperation=%@",
                viewModel.persistenceService == nil ? "false" : "true",
                String(describing: viewModel.pendingOperation)
            )
#endif
            return
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedImportConfig.appGroupID
        ) else {
            return
        }

        let incomingDirectory = containerURL.appendingPathComponent(
            SharedImportConfig.incomingDirectoryName,
            isDirectory: true
        )
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: incomingDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let midiFiles = fileURLs.filter(urlRepresentsMIDIFile)
        guard let nextFile = midiFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
            return
        }
#if DEBUG
        NSLog("[Import] Found pending shared file on launch/foreground: %@", nextFile.path)
#endif
        importSharedMIDIFileIfPossible(from: nextFile)
    }

    func beginMIDIImportPresentation() {
        viewModel.playbackEngine.pause()
        importAlert = nil
        isPresentingImporter = true
    }

    func handleIncomingMIDIURL(_ url: URL) {
#if DEBUG
        NSLog("[Import] handleIncomingMIDIURL: %@", url.absoluteString)
#endif
        if handleSharedImportDeepLink(url) {
#if DEBUG
            NSLog("[Import] URL handled as shared deep link")
#endif
            return
        }
        guard urlRepresentsMIDIFile(url) else { return }
        viewModel.playbackEngine.pause()
        pendingSharedImport = PendingSharedImport(url: url, fileName: url.lastPathComponent)
    }

    func confirmSharedMIDIImport() {
        guard let pendingSharedImport else { return }
        self.pendingSharedImport = nil
        importMIDIFile(from: pendingSharedImport.url)
    }

    func handleMIDIImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importMIDIFile(from: url)
        case .failure(let error):
            if isCancelledImport(error) {
                return
            }
            importAlert = MIDIImportAlert(
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    func importMIDIFile(from url: URL) {
#if DEBUG
        NSLog("[Import] importMIDIFile start: %@", url.path)
#endif
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let result = await viewModel.importMIDIFile(from: url)
            switch result {
            case .success(let imported):
#if DEBUG
                NSLog("[Import] importMIDIFile success: %@", imported.title)
#endif
                if isEditingList {
                    isEditingList = false
                    viewModel.multiSelection.removeAll()
                    selectionAnchorID = nil
                    preEditSelection = nil
                }
                viewModel.selectedSidebarItem = .recentTake(imported.id)
                importAlert = MIDIImportAlert(
                    title: "Import Succeeded",
                    message: "\"\(imported.title)\" is now available in Recent Takes."
                )
            case .failure(let error):
#if DEBUG
                NSLog("[Import] importMIDIFile failure: %@", error.localizedDescription)
#endif
                importAlert = MIDIImportAlert(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    func importSharedMIDIFileIfPossible(from url: URL) {
#if DEBUG
        NSLog("[Import] importSharedMIDIFileIfPossible start: %@", url.path)
#endif
        guard canAttemptAutomaticSharedImport else {
            logDeferredSharedImport()
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        Task {
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let result = await viewModel.importMIDIFile(from: url)
            handleSharedImportResult(result, sourceURL: url)
        }
    }

    func urlRepresentsMIDIFile(_ url: URL) -> Bool {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .midi) {
            return true
        }
        let ext = url.pathExtension.lowercased()
        return ext == "mid" || ext == "midi"
    }

    func isCancelledImport(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    func handleSharedImportDeepLink(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == SharedImportConfig.deepLinkScheme,
              url.host?.lowercased() == SharedImportConfig.deepLinkHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let relativePath = components.queryItems?
                  .first(where: { $0.name == SharedImportConfig.deepLinkFileQueryItem })?
                  .value else {
            return false
        }
#if DEBUG
        NSLog("[Import] Shared deep link relative path: %@", relativePath)
#endif

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedImportConfig.appGroupID
        ) else {
#if DEBUG
            NSLog("[Import] App Group container unavailable for id %@", SharedImportConfig.appGroupID)
#endif
            importAlert = MIDIImportAlert(
                title: "Import Failed",
                message: "Unable to access shared import storage."
            )
            return true
        }

        let fileURL = containerURL.appendingPathComponent(relativePath)
#if DEBUG
        NSLog("[Import] Resolved shared file URL: %@", fileURL.path)
#endif
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            importAlert = MIDIImportAlert(
                title: "Import Failed",
                message: "Shared MIDI file was not found."
            )
            return true
        }

        importSharedMIDIFileIfPossible(from: fileURL)
        return true
    }

    func isSharedImportFile(_ url: URL) -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedImportConfig.appGroupID
        ) else {
            return false
        }

        let incomingDirectory = containerURL.appendingPathComponent(
            SharedImportConfig.incomingDirectoryName,
            isDirectory: true
        )
        let standardizedIncoming = incomingDirectory.standardizedFileURL.path
        let standardizedURL = url.standardizedFileURL.path
        return standardizedURL.hasPrefix(standardizedIncoming + "/")
    }

    var canAttemptAutomaticSharedImport: Bool {
        viewModel.persistenceService != nil && viewModel.pendingOperation == nil
    }

    func isRetryableSharedImportFailure(_ error: Error) -> Bool {
        guard let loadError = error as? SampleTakeLoadError else { return false }
        switch loadError {
        case .operationInProgress, .storageUnavailable:
            return true
        }
    }

    func handleSharedImportResult(
        _ result: Result<TakePersistenceService.ImportedTakeResult, Error>,
        sourceURL: URL
    ) {
        switch result {
        case .success(let imported):
            handleSuccessfulSharedImport(imported, sourceURL: sourceURL)
        case .failure(let error):
            handleFailedSharedImport(error)
        }
    }

    func handleSuccessfulSharedImport(
        _ imported: TakePersistenceService.ImportedTakeResult,
        sourceURL: URL
    ) {
#if DEBUG
        NSLog("[Import] shared import success: %@", imported.title)
#endif
        try? FileManager.default.removeItem(at: sourceURL)
        if isEditingList {
            isEditingList = false
            viewModel.multiSelection.removeAll()
            selectionAnchorID = nil
            preEditSelection = nil
        }
        viewModel.selectedSidebarItem = .recentTake(imported.id)
        importAlert = MIDIImportAlert(
            title: "Import Succeeded",
            message: "\"\(imported.title)\" is now available in Recent Takes."
        )
    }

    func handleFailedSharedImport(_ error: Error) {
        if isRetryableSharedImportFailure(error) {
#if DEBUG
            NSLog("[Import] shared import deferred after retryable failure: %@", error.localizedDescription)
#endif
            return
        }
#if DEBUG
        NSLog("[Import] shared import hard failure: %@", error.localizedDescription)
#endif
        importAlert = MIDIImportAlert(
            title: "Import Failed",
            message: error.localizedDescription
        )
    }

    func logDeferredSharedImport() {
#if DEBUG
        NSLog(
            "[Import] Deferred shared import; storageReady=%@ pendingOperation=%@",
            viewModel.persistenceService == nil ? "false" : "true",
            String(describing: viewModel.pendingOperation)
        )
#endif
    }
}
