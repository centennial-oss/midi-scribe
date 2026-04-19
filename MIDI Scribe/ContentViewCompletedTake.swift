//
//  ContentView+CompletedTake.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    private var completedTakeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    func completedTakeDetail(for takeID: UUID) -> some View {
        VStack(spacing: 6) {
            if let take = viewModel.recentTake(id: takeID) {
                completedTakeProgressAndErrors

                completedTakeMetadata(for: take)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let fullTake = viewModel.fullTake(id: take.id) {
                    VStack(alignment: .trailing, spacing: 8) {
                        PianoRollView(take: fullTake, viewModel: viewModel, zoomLevel: $pianoRollZoomLevel)
                            .id(take.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

#if os(iOS)
                        if UIDevice.current.userInterfaceIdiom != .phone {
                            completedTakeZoomSliderRow(for: take)
                        }
#else
                        completedTakeZoomSliderRow(for: take)
#endif
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Text("Take not found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            if let take = viewModel.recentTake(id: takeID) {
                completedTakeToolbar(for: take)
            }
        }
        .navigationTitle(viewModel.recentTake(id: takeID)?.displayTitle ?? "Take")
    }

    @ToolbarContentBuilder
    private func completedTakeToolbar(for take: RecordedTakeListItem) -> some ToolbarContent {
        completedTakePlaybackToolbar(for: take)
        ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
        completedTakeActionsToolbar(for: take)
        #if os(iOS)
        ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
        iOSAppActionsToolbar()
        #endif
    }

    @ToolbarContentBuilder
    private func completedTakePlaybackToolbar(for take: RecordedTakeListItem) -> some ToolbarContent {
        let isPlaying = viewModel.isPlaying(takeID: take.id)
        let playLabel = isPlaying ? "Pause" : "Play"
        let playIcon = isPlaying ? "pause.fill" : "play.fill"
        let rewindLabel = isPlaying ? "Pause and Rewind to Beginning" : "Rewind to Beginning"

        ToolbarItemGroup(placement: completedTakeToolbarPlacement) {
            toolbarIconButton(
                rewindLabel,
                systemImage: "backward.end.fill",
                disabled: viewModel.isTakeActionInProgress
            ) {
                viewModel.rewindPlaybackToBeginning(for: take.id)
            }

            toolbarIconButton(playLabel, systemImage: playIcon, disabled: viewModel.isTakeActionInProgress) {
                viewModel.togglePlayback(for: take.id)
            }

            toolbarIconButton("Restart", systemImage: "gobackward", disabled: viewModel.isTakeActionInProgress) {
                viewModel.restartPlayback(for: take.id)
            }
        }
    }

    @ToolbarContentBuilder
    private func completedTakeActionsToolbar(for take: RecordedTakeListItem) -> some ToolbarContent {
        let splitLabel = splitTakeLabel(for: take)
        let starLabel = take.isStarred ? "Unstar" : "Star"
        let starIcon = take.isStarred ? "star.fill" : "star"

        ToolbarItemGroup(placement: completedTakeToolbarPlacement) {
            toolbarIconButton("Rename Take", systemImage: "pencil", disabled: viewModel.isTakeActionInProgress) {
                beginRename(take)
            }

            toolbarIconButton(
                splitLabel,
                systemImage: "square.split.2x1",
                disabled: !viewModel.canSplit(takeID: take.id) || viewModel.isTakeActionInProgress
            ) {
                viewModel.splitCurrentPausedTake()
            }

            toolbarIconButton(
                starLabel,
                systemImage: starIcon,
                disabled: viewModel.isTakeActionInProgress,
                foregroundStyle: take.isStarred ? .yellow : nil
            ) {
                viewModel.toggleStar(takeID: take.id)
            }

            toolbarIconButton(
                "Export .mid",
                systemImage: "square.and.arrow.up",
                disabled: viewModel.isTakeActionInProgress
            ) {
                exportTake(id: take.id)
            }

            toolbarIconButton(
                "Delete Take",
                systemImage: "trash",
                disabled: viewModel.isTakeActionInProgress,
                role: .destructive
            ) {
                pendingDeleteTakeID = take.id
            }
        }
    }

    private func toolbarIconButton(
        _ label: String,
        systemImage: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        foregroundStyle: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundStyle ?? .primary)
        }
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    private func splitTakeLabel(for take: RecordedTakeListItem) -> String {
        let canSplit = viewModel.canSplit(takeID: take.id)
        let offsetText = formatOffset(viewModel.pausedPlaybackOffset ?? 0)
        return canSplit
            ? "Split Take Here (\(offsetText))"
            : "Split Take Here"
    }

    @ViewBuilder
    private var completedTakeProgressAndErrors: some View {
        if let pendingTakeOperation = viewModel.pendingOperation {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(pendingTakeOperation.displayText)
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
    }

    private func completedTakeMetadata(for take: RecordedTakeListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                Text(viewModel.completedTakeDurationText(take))
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
            inlineLabeledValue("Events", "\(take.summary.eventCount)")
            inlineLabeledValue("Notes", "\(max(take.summary.noteOnCount, take.summary.noteOffCount))")
            inlineLabeledValue("Range", viewModel.completedTakeRangeText(take))
        }
    }

    /// Zoom controls sit below the piano roll, trailing-aligned.
    private func completedTakeZoomSliderRow(for take: RecordedTakeListItem) -> some View {
        let isZoomDisabled = take.summary.duration < 5.0
        return HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(isZoomDisabled ? .secondary : .primary)

                Slider(value: $pianoRollZoomLevel, in: 0...1)
                    .frame(width: 150)
                    .disabled(isZoomDisabled)

                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(isZoomDisabled ? .secondary : .primary)
            }
        }
    }

    private func inlineLabeledValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.headline)
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    func placeholderDetail(_ text: String) -> some View {
        Text(text)
            .font(.title3)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
    }

    func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            Text(value)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    func formatOffset(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let remaining = seconds - TimeInterval(minutes * 60)
        return String(format: "%dm %.1fs", minutes, remaining)
    }
}
