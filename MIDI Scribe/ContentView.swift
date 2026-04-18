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
    case starred
    case organizing
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

    init(settings: AppSettings) {
        self.settings = settings
        _viewModel = StateObject(wrappedValue: MIDILiveNoteViewModel(settings: settings))
    }

    var body: some View {
        NavigationSplitView {
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

                Text("Starred")
                    .tag(SidebarItem.starred)

                Text("Organizing")
                    .tag(SidebarItem.organizing)

                Section("Recent Takes") {
                    ForEach(viewModel.recentTakes) { take in
                        Text(take.displayTitle)
                            .tag(SidebarItem.recentTake(take.id))
                    }
                }
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
        .task(id: storedRecentTakes.map(\.takeID)) {
            viewModel.setRecentTakes(storedRecentTakes.map(\.listItem))
            let container = modelContext.container
            viewModel.resolveFullTake = { id in
                // Fresh context so this can safely run off the main thread.
                let context = ModelContext(container)
                let takeID = id.uuidString
                let descriptor = FetchDescriptor<StoredTake>(
                    predicate: #Predicate<StoredTake> { $0.takeID == takeID }
                )
                return (try? context.fetch(descriptor))?.first?.recordedTake
            }
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
        case .recentTake(let takeID):
            completedTakeDetail(for: takeID)
        case .starred:
            placeholderDetail("Starred takes will appear here.")
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

                    Button("Restart") {
                        viewModel.restartPlayback(for: take.id)
                    }

                    Picker("Output Device", selection: $viewModel.selectedPlaybackTarget) {
                        Text("OS Speakers").tag(PlaybackOutputTarget.osSpeakers)
                        ForEach(1...16, id: \.self) { channel in
                            Text("MIDI Channel \(channel)").tag(PlaybackOutputTarget.midiChannel(channel))
                        }
                    }
                    .frame(maxWidth: 260)

                    Button("Export .mid") {
                        exportTake(id: take.id)
                    }

                    Button("Delete Take", role: .destructive) {
                        pendingDeleteTakeID = take.id
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let exportErrorMessage {
                    Text(exportErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text(take.displayTitle)
                    .font(.title2.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)

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

    private func persistLastCompletedTakeIfNeeded() {
        guard let listItem = viewModel.lastCompletedTake else { return }
        // Resolve the full take (with events) from the view model's cache;
        // it was just completed so it's in memory and won't touch SwiftData.
        guard let take = viewModel.fullTake(id: listItem.id) else { return }

        let container = modelContext.container
        // Run the insert on a background context so serializing thousands of
        // events doesn't block the main thread (the "beachball while saving"
        // symptom).
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

        // Use the cached full take if we have it; otherwise fetch on a
        // background context so large takes don't stall the UI.
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

        let takeID = id.uuidString
        let descriptor = FetchDescriptor<StoredTake>(
            predicate: #Predicate<StoredTake> { storedTake in
                storedTake.takeID == takeID
            }
        )

        if let matches = try? modelContext.fetch(descriptor) {
            for take in matches {
                modelContext.delete(take)
            }
            try? modelContext.save()
        }

        viewModel.deleteTake(id: id)
    }
}
