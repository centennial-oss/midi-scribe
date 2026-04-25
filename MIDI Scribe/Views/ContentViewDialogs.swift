//
//  ContentView+Dialogs.swift
//  MIDI Scribe
//

import SwiftUI
import UniformTypeIdentifiers

extension ContentView {
    func dialogContent(_ content: some View) -> some View {
        alertContent(exportContent(deleteDialogContent(liveTakeDeleteDialogContent(content))))
    }

    private func liveTakeDeleteDialogContent(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Discard Live Take?",
                isPresented: $isPresentingLiveTakeDeleteConfirm
            ) {
                Button("Discard Take", role: .destructive) {
                    confirmLiveTakeDelete()
                }
                Button("Cancel", role: .cancel) {
                    isPresentingLiveTakeDeleteConfirm = false
                }
            } message: {
                Text(
                    "This in-progress take has been recording for \(viewModel.currentTakeDurationText). " +
                        "Discarding it will permanently lose the recording so far."
                )
            }
    }

    private func deleteDialogContent(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Delete Take?",
                isPresented: Binding(
                    get: { pendingDeleteTakeID != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDeleteTakeID = nil
                        }
                    }
                ),
                presenting: pendingDeleteTakeID
            ) { takeID in
                Button("Delete Take", role: .destructive) {
                    deleteTake(id: takeID)
                }
                Button("Cancel", role: .cancel) {
                    pendingDeleteTakeID = nil
                }
            } message: { takeID in
                Text(viewModel.recentTake(id: takeID)?.displayTitle ?? "This take")
            }
    }

    private func exportContent(_ content: some View) -> some View {
        content
            .fileImporter(
                isPresented: $isPresentingImporter,
                allowedContentTypes: [.midi],
                onCompletion: handleMIDIImportSelection
            )
            .fileExporter(
                isPresented: $isPresentingExporter,
                document: exportDocument,
                contentType: .midi,
                defaultFilename: exportSuggestedName
            ) { result in
                switch result {
                case .success:
                    exportErrorMessage = nil
                case .failure(let error):
                    exportErrorMessage = "Export failed: \(error.localizedDescription)"
                }
                exportDocument = nil
            }
    }

    private func alertContent(_ content: some View) -> some View {
        importAlertContent(coreAlertContent(content))
    }

    private func coreAlertContent(_ content: some View) -> some View {
        content
            .alert("Merge \(viewModel.multiSelection.count) Takes", isPresented: $isPresentingMergeDialog) {
                TextField("Silence between takes (ms)", text: $mergeSilenceMsText)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Button("Merge") {
                    let silenceMillis = Int(mergeSilenceMsText) ?? 0
                    viewModel.mergeSelectedTakes(silenceBetweenMs: silenceMillis)
                    clearBulkSelection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the number of milliseconds of silence to insert between consecutive takes (default 0).")
            }
            .alert("Rename Take", isPresented: Binding(
                get: { renamingTakeID != nil },
                set: { if !$0 { cancelRename() } }
            )) {
                TextField("Name", text: $renameDraft)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { cancelRename() }
            } message: {
                Text("Enter a new name for this take.")
            }
            .alert("Delete \(viewModel.multiSelection.count) Takes?", isPresented: $isPresentingBulkDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteSelectedTakes()
                    clearBulkSelection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the selected takes. This action cannot be undone.")
            }
    }

    private func importAlertContent(_ content: some View) -> some View {
        content
            .alert(
                "Import MIDI File?",
                isPresented: Binding(
                    get: { pendingSharedImport != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingSharedImport = nil
                        }
                    }
                ),
                presenting: pendingSharedImport
            ) { sharedImport in
                Button("Import") {
                    pendingSharedImport = sharedImport
                    confirmSharedMIDIImport()
                }
                Button("Cancel", role: .cancel) {
                    pendingSharedImport = nil
                }
            } message: { sharedImport in
                Text("Import \(sharedImport.fileName)?")
            }
            .alert(item: $importAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
    }

    func splitDialogContent(_ content: some View) -> some View {
        content
            .confirmationDialog(
                "Split Take?",
                isPresented: Binding(
                    get: { pendingSplitTakeID != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingSplitTakeID = nil
                        }
                    }
                ),
                presenting: pendingSplitTakeID
            ) { takeID in
                Button("Split Take", role: .destructive) {
                    splitTake(id: takeID)
                }
                Button("Cancel", role: .cancel) {
                    pendingSplitTakeID = nil
                }
            } message: { takeID in
                Text(splitConfirmationMessage(for: takeID))
            }
    }
}
