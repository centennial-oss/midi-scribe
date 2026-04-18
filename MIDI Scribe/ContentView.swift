//
//  ContentView.swift
//  MIDI Scribe
//
//  Created by James Ranson on 3/21/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum SidebarItem: Hashable {
    case currentTake
    case organizing
    case starredTake(UUID)
    case recentTake(UUID)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredTake.startedAt, order: .reverse) private var storedRecentTakes: [StoredTake]
    @ObservedObject private var settings: AppSettings
    @StateObject private var viewModel: MIDILiveNoteViewModel
    @State private var pendingDeleteTakeID: UUID?
    @State private var exportDocument: MIDIFileDocument?
    @State private var exportSuggestedName: String = "take"
    @State private var isPresentingExporter = false
    @State private var exportErrorMessage: String?
    @State private var isPresentingMergeDialog = false
    @State private var mergeSilenceMsText: String = "0"
    @State private var renamingTakeID: UUID?
    @State private var renameDraft: String = ""

    init(settings: AppSettings) {
        self.settings = settings
        _viewModel = StateObject(wrappedValue: MIDILiveNoteViewModel(settings: settings))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
#if os(macOS)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
#endif
        } detail: {
            detailContent
        }
        .frame(minWidth: 520, minHeight: 320)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .onReceive(NotificationCenter.default.publisher(for: appWillTerminateNotification)) { _ in
            viewModel.appWillTerminate()
        }
        .onAppear {
            // One-time wiring that never needs to change.
            let container = modelContext.container
            if viewModel.persistenceService == nil {
                viewModel.persistenceService = TakePersistenceService(container: container)
            }
            viewModel.resolveFullTake = { id in
                let context = ModelContext(container)
                let takeID = id.uuidString
                let descriptor = FetchDescriptor<StoredTake>(
                    predicate: #Predicate<StoredTake> { $0.takeID == takeID }
                )
                return (try? context.fetch(descriptor))?.first?.recordedTake
            }
            viewModel.setRecentTakes(storedRecentTakes.map(\.listItem))
        }
        // Rebuild our lightweight list whenever rows are added/removed/reordered.
        // We key on takeIDs only (O(n) string compare) instead of faulting
        // extra @Attribute properties on every body pass, which was causing
        // main-thread hangs on sidebar selection.
        .onChange(of: storedRecentTakes.map(\.takeID)) { _, _ in
            viewModel.setRecentTakes(storedRecentTakes.map(\.listItem))
        }
        .onChange(of: viewModel.lastCompletedTake?.id) { _, _ in
            persistLastCompletedTakeIfNeeded()
        }
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
        .alert("Merge \(viewModel.multiSelection.count) Takes", isPresented: $isPresentingMergeDialog) {
            TextField("Silence between takes (ms)", text: $mergeSilenceMsText)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
            Button("Merge") {
                let ms = Int(mergeSilenceMsText) ?? 0
                viewModel.mergeSelectedTakes(silenceBetweenMs: ms)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the number of milliseconds of silence to insert between consecutive takes (default 0).")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $viewModel.selectedSidebarItem) {
            HStack {
                Text("Scribing Enabled")
                Spacer()
                Toggle("", isOn: Binding(
                    get: { settings.isScribingEnabled },
                    set: { settings.disableScribing = !$0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }

            Divider()

            Text("Current Take")
                .tag(SidebarItem.currentTake)

            Text("Organizing")
                .tag(SidebarItem.organizing)

            if !viewModel.starredTakes.isEmpty {
                Section("Starred") {
                    ForEach(viewModel.starredTakes) { take in
                        sidebarRow(for: take, asStarred: true)
                            .tag(SidebarItem.starredTake(take.id))
                    }
                }
            }

            Section("Recent Takes") {
                ForEach(viewModel.recentTakes) { take in
                    sidebarRow(for: take, asStarred: false)
                        .tag(SidebarItem.recentTake(take.id))
                }
            }

            if viewModel.multiSelection.count >= 2 {
                Section {
                    Button("Merge \(viewModel.multiSelection.count) Selected") {
                        mergeSilenceMsText = "0"
                        isPresentingMergeDialog = true
                    }
                    .disabled(viewModel.isTakeActionInProgress)
                }
            }

            if let op = viewModel.pendingOperation {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(op.displayText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(for take: RecordedTakeListItem, asStarred: Bool) -> some View {
        HStack(spacing: 8) {
            if renamingTakeID == take.id {
                TextField("Name", text: $renameDraft, onCommit: { commitRename() })
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
            } else {
                Text(take.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if take.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                }
                Spacer(minLength: 8)
                Text(viewModel.completedTakeDurationText(take))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Toggle("", isOn: bindingForMultiSelection(take.id))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .help("Select for bulk merge")
                .disabled(viewModel.isTakeActionInProgress)
        }
        .contextMenu {
            Button(take.isStarred ? "Unstar" : "Star") {
                viewModel.toggleStar(takeID: take.id)
            }
            .disabled(viewModel.isTakeActionInProgress)
            Button("Rename…") {
                beginRename(take)
            }
            .disabled(viewModel.isTakeActionInProgress)
            Divider()
            Button("Delete", role: .destructive) {
                pendingDeleteTakeID = take.id
            }
            .disabled(viewModel.isTakeActionInProgress)
        }
    }

    private func bindingForMultiSelection(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { viewModel.multiSelection.contains(id) },
            set: { isOn in
                if isOn {
                    viewModel.multiSelection.insert(id)
                } else {
                    viewModel.multiSelection.remove(id)
                }
            }
        )
    }

    private var appWillTerminateNotification: Notification.Name {
#if os(macOS)
        NSApplication.willTerminateNotification
#else
        UIApplication.willTerminateNotification
#endif
    }

    @ViewBuilder
    private var detailContent: some View {
        switch viewModel.selectedSidebarItem {
        case .currentTake:
            currentTakeDetail
        case .recentTake(let takeID), .starredTake(let takeID):
            completedTakeDetail(for: takeID)
        case .organizing:
            placeholderDetail("Organizing tools will appear here.")
        }
    }

    private var currentTakeDetail: some View {
        VStack(spacing: 32) {
            HStack(spacing: 20) {
                Button("Next Take") {
                    viewModel.nextTake()
                }
                .disabled(!viewModel.isTakeInProgress)

                Button("End Take") {
                    viewModel.endTake()
                }
                .disabled(!viewModel.isTakeInProgress)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Toggle("Echo Scribed Data To Speakers", isOn: $settings.echoScribedToSpeakers)
                .frame(maxWidth: .infinity, alignment: .leading)

            if viewModel.isTakeInProgress {
                VStack(spacing: 48) {
                    VStack(spacing: 12) {
                        Text("Current Take Duration")
                            .font(.headline)

                        Text(viewModel.currentTakeDurationText)
                            .font(.system(size: 36, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }

                    VStack(spacing: 16) {
                        Text("Current MIDI Note(s)")
                            .font(.headline)

                        Text(viewModel.currentNoteText)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 60)

                        if let errorText = viewModel.errorText {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }

                    VStack(spacing: 16) {
                        Text("Current MIDI Channel(s)")
                            .font(.headline)

                        Text(viewModel.currentChannelText)
                            .font(.system(size: 44, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 60)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        Text("Recorded Take Summary")
                            .font(.headline)

                        Text(viewModel.currentTakeSummaryText)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)

                        if viewModel.shouldShowIdleTimeoutText {
                            Text(viewModel.idleTimeoutText)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Text(viewModel.currentTakePromptText)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Text(viewModel.lastTakeSummaryText)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func completedTakeDetail(for takeID: UUID) -> some View {
        VStack(spacing: 24) {
            if let take = viewModel.recentTake(id: takeID) {
                HStack(spacing: 16) {
                    Button(viewModel.isPlaying(takeID: take.id) ? "Pause" : "Play") {
                        viewModel.togglePlayback(for: take.id)
                    }
                    .disabled(viewModel.isTakeActionInProgress)

                    Button("Restart") {
                        viewModel.restartPlayback(for: take.id)
                    }
                    .disabled(viewModel.isTakeActionInProgress)

                    Button(viewModel.canSplit(takeID: take.id) ? "Split Take Here (\(formatOffset(viewModel.pausedPlaybackOffset ?? 0)))" : "Split Take Here") {
                        viewModel.splitCurrentPausedTake()
                    }
                    .disabled(!viewModel.canSplit(takeID: take.id) || viewModel.isTakeActionInProgress)
                    .help("Pause playback at the point where you want to split, then click here.")

                    Picker("Output Device", selection: $viewModel.selectedPlaybackTarget) {
                        Text("OS Speakers").tag(PlaybackOutputTarget.osSpeakers)
                        ForEach(1...16, id: \.self) { channel in
                            Text("MIDI Channel \(channel)").tag(PlaybackOutputTarget.midiChannel(channel))
                        }
                    }
                    .frame(maxWidth: 260)
                    .disabled(viewModel.isTakeActionInProgress)

                    Button(take.isStarred ? "Unstar" : "Star") {
                        viewModel.toggleStar(takeID: take.id)
                    }
                    .disabled(viewModel.isTakeActionInProgress)

                    Button("Export .mid") {
                        exportTake(id: take.id)
                    }
                    .disabled(viewModel.isTakeActionInProgress)

                    Button("Delete Take", role: .destructive) {
                        pendingDeleteTakeID = take.id
                    }
                    .disabled(viewModel.isTakeActionInProgress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let op = viewModel.pendingOperation {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(op.displayText)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let actionErrorText = viewModel.actionErrorText {
                    Text(actionErrorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                takeTitleView(for: take)

                VStack(alignment: .leading, spacing: 16) {
                    labeledValue("Duration", viewModel.completedTakeDurationText(take))
                    labeledValue("Events", "\(take.summary.eventCount)")
                    labeledValue("Note On / Off", "\(take.summary.noteOnCount) / \(take.summary.noteOffCount)")
                    labeledValue("Channels", viewModel.completedTakeChannelsText(take))
                    labeledValue("Range", viewModel.completedTakeRangeText(take))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Take not found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func takeTitleView(for take: RecordedTakeListItem) -> some View {
        if renamingTakeID == take.id {
            HStack {
                TextField("Take name", text: $renameDraft, onCommit: { commitRename() })
                    .textFieldStyle(.roundedBorder)
                    .font(.title2)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                Button("Save") { commitRename() }
                Button("Cancel") { cancelRename() }
                if take.userTitle != nil {
                    Button("Reset to Default") {
                        viewModel.renameTake(id: take.id, to: nil)
                        cancelRename()
                    }
                }
            }
        } else {
            HStack {
                Text(take.displayTitle)
                    .font(.title2.monospaced())
                Button("Rename") { beginRename(take) }
                    .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture(count: 2) { beginRename(take) }
        }
    }

    private func placeholderDetail(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.body.monospaced())
            .foregroundStyle(.secondary)
        }
    }

    private func formatOffset(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remaining = seconds - TimeInterval(minutes * 60)
        return String(format: "%dm %.1fs", minutes, remaining)
    }

    // MARK: - Rename flow

    private func beginRename(_ take: RecordedTakeListItem) {
        renamingTakeID = take.id
        renameDraft = take.userTitle ?? take.baseTitle
    }

    private func commitRename() {
        guard let id = renamingTakeID else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        viewModel.renameTake(id: id, to: trimmed.isEmpty ? nil : trimmed)
        renamingTakeID = nil
        renameDraft = ""
    }

    private func cancelRename() {
        renamingTakeID = nil
        renameDraft = ""
    }

    private func persistLastCompletedTakeIfNeeded() {
        guard let listItem = viewModel.lastCompletedTake else { return }
        guard let take = viewModel.fullTake(id: listItem.id) else { return }

        let container = modelContext.container
        Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let takeID = take.id.uuidString
            let descriptor = FetchDescriptor<StoredTake>(
                predicate: #Predicate<StoredTake> { storedTake in
                    storedTake.takeID == takeID
                }
            )
            if let existing = try? context.fetch(descriptor), !existing.isEmpty {
                return
            }
            context.insert(StoredTake(recordedTake: take))
            try? context.save()
        }
    }

    private func exportTake(id: UUID) {
        exportErrorMessage = nil

        if let cached = viewModel.fullTake(id: id) {
            presentExporter(for: cached)
            return
        }

        let container = modelContext.container
        let takeID = id.uuidString
        Task {
            let take: RecordedTake? = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<StoredTake>(
                    predicate: #Predicate<StoredTake> { $0.takeID == takeID }
                )
                return (try? context.fetch(descriptor))?.first?.recordedTake
            }.value

            guard let take else {
                exportErrorMessage = "Unable to load take for export."
                return
            }
            presentExporter(for: take)
        }
    }

    private func presentExporter(for take: RecordedTake) {
        let document = MIDIFileDocument(take: take)
        exportSuggestedName = document.suggestedFileName
        exportDocument = document
        isPresentingExporter = true
    }

    private func deleteTake(id: UUID) {
        pendingDeleteTakeID = nil
        viewModel.playbackEngine.pause()
        viewModel.deleteTakeViaPersistence(id: id)

        if case .recentTake(let selectedID) = viewModel.selectedSidebarItem, selectedID == id {
            viewModel.selectedSidebarItem = .currentTake
        } else if case .starredTake(let selectedID) = viewModel.selectedSidebarItem, selectedID == id {
            viewModel.selectedSidebarItem = .currentTake
        }
    }
}
