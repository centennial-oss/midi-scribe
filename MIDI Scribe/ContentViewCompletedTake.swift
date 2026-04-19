//
//  ContentView+CompletedTake.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func completedTakeDetail(for takeID: UUID) -> some View {
        VStack(spacing: 24) {
            if let take = viewModel.recentTake(id: takeID) {
                completedTakeToolbar(for: take)
                completedTakeProgressAndErrors
                takeTitleView(for: take)

                HStack(alignment: .top, spacing: 32) {
                    completedTakeMetadata(for: take)
                    Spacer()
                    // Zoom Buttons
                    let isZoomDisabled = take.summary.duration < 5.0
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

                if let fullTake = viewModel.fullTake(id: take.id) {
                    PianoRollView(take: fullTake, viewModel: viewModel, zoomLevel: $pianoRollZoomLevel)
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
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func completedTakeToolbar(for take: RecordedTakeListItem) -> some View {
        HStack(spacing: 16) {
            Button(viewModel.isPlaying(takeID: take.id) ? "Pause" : "Play") {
                viewModel.togglePlayback(for: take.id)
            }
            .disabled(viewModel.isTakeActionInProgress)

            Button("Restart") {
                viewModel.restartPlayback(for: take.id)
            }
            .disabled(viewModel.isTakeActionInProgress)

            splitTakeButton(for: take)

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
    }

    private func splitTakeButton(for take: RecordedTakeListItem) -> some View {
        let canSplit = viewModel.canSplit(takeID: take.id)
        let offsetText = formatOffset(viewModel.pausedPlaybackOffset ?? 0)
        let title = canSplit
            ? "Split Take Here (\(offsetText))"
            : "Split Take Here"
        return Button(title) {
            viewModel.splitCurrentPausedTake()
        }
        .disabled(!canSplit || viewModel.isTakeActionInProgress)
        .help("Pause playback at the point where you want to split, then click here.")
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
        HStack(alignment: .firstTextBaseline, spacing: 24) {
            inlineLabeledValue("Duration", viewModel.completedTakeDurationText(take))
            inlineLabeledValue("Events", "\(take.summary.eventCount)")
            inlineLabeledValue("Note On / Off", "\(take.summary.noteOnCount) / \(take.summary.noteOffCount)")
            inlineLabeledValue("Channels", viewModel.completedTakeChannelsText(take))
            inlineLabeledValue("Range", viewModel.completedTakeRangeText(take))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    @ViewBuilder
    func takeTitleView(for take: RecordedTakeListItem) -> some View {
        HStack {
            Text(take.displayTitle)
                .font(.title2.monospaced())
            Button("Rename") { beginRename(take) }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onTapGesture(count: 2) { beginRename(take) }
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
