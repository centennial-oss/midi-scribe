import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func beginMIDIImportPresentation() {
        viewModel.playbackEngine.pause()
        importAlert = nil
        isPresentingImporter = true
    }

    func handleIncomingMIDIURL(_ url: URL) {
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
                importAlert = MIDIImportAlert(
                    title: "Import Failed",
                    message: error.localizedDescription
                )
            }
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
}
