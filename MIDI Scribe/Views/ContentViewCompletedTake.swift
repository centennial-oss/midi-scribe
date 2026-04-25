//
//  ContentView+CompletedTake.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    var completedTakeToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    func completedTakeDetail(for takeID: UUID) -> some View {
        VStack(spacing: 6) {
            completedTakeDetailBody(for: takeID)
        }
        .padding(.horizontal, 24)
        .padding(.top, 0)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            if let take = viewModel.recentTake(id: takeID) {
                completedTakeToolbar(for: take)
            }
        }
        .modifier(CompletedTakeSplitDialogModifier(parent: self))
        .navigationTitle(completedTakeNavigationTitle(for: takeID))
    }

    @ViewBuilder
    private func completedTakeDetailBody(for takeID: UUID) -> some View {
        if let take = viewModel.recentTake(id: takeID) {
            completedTakeProgressAndErrors
            completedTakeMetadata(for: take)
                .frame(maxWidth: .infinity, alignment: .leading)
                #if os(macOS)
                .padding(.top, 8)
                #endif
                #if os(iOS)
                .padding(completedTakePhoneBleedInsets)
                #endif
            if completedTakeReadyToRenderID == take.id,
               let fullTake = viewModel.materializedTake(id: take.id) {
                completedTakePianoRoll(fullTake: fullTake, listItem: take)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task(id: completedTakeRenderTaskID(for: take.id)) {
                        await waitForCompletedTakeDetailTransition()
                        viewModel.materializeTakeForDisplay(id: take.id)
                        completedTakeReadyToRenderID = take.id
                    }
            }
        } else {
            Text("Take not found.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func completedTakePianoRoll(
        fullTake: RecordedTake,
        listItem: RecordedTakeListItem
    ) -> some View {
        PianoRollView(
            take: fullTake,
            viewModel: viewModel,
            zoomLevel: $pianoRollZoomLevel,
            scrollToStartRequestID: pianoRollScrollToStartRequestID
        )
        .id(listItem.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #if os(iOS)
        .padding(completedTakePhoneBleedInsets)
        #endif
    }

    @ToolbarContentBuilder
    private func completedTakeToolbar(for take: RecordedTakeListItem) -> some ToolbarContent {
        #if os(iOS)
        iPhoneSidebarToggleToolbar()
        #endif
        if shouldShowCompletedTakeZoomToolbar(for: take) {
            completedTakeZoomToolbar()
            ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
        }
        completedTakePlaybackToolbar(for: take)
        #if os(iOS)
        if !hideTakeActionsToolbarOnPhone {
            ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
            completedTakeActionsToolbar(for: take)
        }
        ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
        completedTakeAppActionsToolbar()
        #else
        ToolbarSpacer(.fixed, placement: completedTakeToolbarPlacement)
        completedTakeActionsToolbar(for: take)
        #endif
    }

    @ToolbarContentBuilder
    private func completedTakeZoomToolbar() -> some ToolbarContent {
        ToolbarItem(placement: completedTakeToolbarPlacement) {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                Button {
                    isPresentingZoomPopover.toggle()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .popover(isPresented: $isPresentingZoomPopover) {
                    completedTakeZoomSliderRow()
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .frame(minWidth: 250)
                        .presentationCompactAdaptation(.popover)
                }
            } else {
                completedTakeZoomSliderRow()
            }
            #else
            completedTakeZoomSliderRow()
            #endif
        }
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
                rewindPlaybackToBeginning(for: take.id)
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
        let isPlaybackInProgress = viewModel.isPlaying(takeID: take.id)
        let actionDisabled = viewModel.isTakeActionInProgress
        let isRenameDisabled = isPlaybackInProgress || actionDisabled
        let isSplitDisabled = !viewModel.canSplit(takeID: take.id) || actionDisabled
        let isExportDisabled = isPlaybackInProgress || actionDisabled
        let isDeleteDisabled = isPlaybackInProgress || actionDisabled
        let starLabel = take.isStarred ? "Unstar" : "Star"
        let starIcon = take.isStarred ? "star.fill" : "star"
        ToolbarItemGroup(placement: completedTakeToolbarPlacement) {
            toolbarIconButton(
                "Rename Take",
                systemImage: "pencil",
                disabled: isRenameDisabled,
                foregroundStyle: isRenameDisabled ? Color.secondary : nil,
                opacity: isRenameDisabled ? 0.35 : 1
            ) {
                beginRename(take)
            }
            toolbarIconButton(
                splitTakeLabel(for: take),
                systemImage: "arrow.triangle.branch",
                disabled: isSplitDisabled,
                role: .destructive,
                foregroundStyle: isSplitDisabled ? Color.secondary : nil,
                opacity: isSplitDisabled ? 0.35 : 1
            ) {
                beginSplitTakeConfirmation(id: take.id)
            }
            toolbarIconButton(
                starLabel,
                systemImage: starIcon,
                disabled: actionDisabled,
                foregroundStyle: take.isStarred ? .yellow : nil
            ) {
                viewModel.toggleStar(takeID: take.id)
            }
            exportTakeToolbarButton(takeID: take.id, disabled: isExportDisabled)
            deleteTakeToolbarButton(takeID: take.id, disabled: isDeleteDisabled)
        }
    }

    private func exportTakeToolbarButton(takeID: UUID, disabled: Bool) -> some View {
        toolbarIconButton(
            "Export .mid",
            systemImage: "square.and.arrow.up",
            disabled: disabled,
            foregroundStyle: disabled ? Color.secondary : nil,
            opacity: disabled ? 0.35 : 1
        ) {
            exportTake(id: takeID)
        }
    }

    private func deleteTakeToolbarButton(takeID: UUID, disabled: Bool) -> some View {
        toolbarIconButton(
            "Delete Take",
            systemImage: "trash",
            disabled: disabled,
            role: .destructive,
            foregroundStyle: disabled ? Color.secondary : nil,
            opacity: disabled ? 0.35 : 1
        ) {
            beginDeleteTake(id: takeID)
        }
    }

    private func toolbarIconButton(
        _ label: String,
        systemImage: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        foregroundStyle: Color? = nil,
        opacity: Double = 1,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .foregroundStyle(foregroundStyle ?? (disabled ? Color.secondary : Color.primary))
                .opacity(opacity)
        }
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var completedTakeProgressAndErrors: some View {
        if let pendingTakeOperation = viewModel.pendingOperation,
           pendingTakeOperation.shouldDisplayProgressNotice {
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
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                Text(take.displayTitle)
                    .font(.headline)
                if !hideTakeActionsToolbarOnPhone {
                    Text("/")
                        .foregroundStyle(.secondary)
                }
            }
            if UIDevice.current.userInterfaceIdiom != .phone || !hideTakeActionsToolbarOnPhone {
                HStack(spacing: 6) {
                    Text(viewModel.completedTakeDurationText(take))
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                }
                inlineLabeledValue("Notes", "\(max(take.summary.noteOnCount, take.summary.noteOffCount))")
                inlineLabeledValue("Range", viewModel.completedTakeRangeText(take))
            }
            #else
            HStack(spacing: 6) {
                Text(viewModel.completedTakeDurationText(take))
                    .font(.takeMetadataValue)
                    .foregroundStyle(.secondary)
            }
            inlineLabeledValue("Notes", "\(max(take.summary.noteOnCount, take.summary.noteOffCount))")
            inlineLabeledValue("Range", viewModel.completedTakeRangeText(take))
            #endif
        }
    }

    private func shouldShowCompletedTakeZoomToolbar(for take: RecordedTakeListItem) -> Bool {
        guard take.summary.duration >= 5.0 else { return false }
        #if os(iOS)
        return !hideTakeActionsToolbarOnPhone
        #else
        return true
        #endif
    }

    private func completedTakeZoomSliderRow() -> some View {
        HStack(spacing: 2) {
            Image(systemName: "minus.magnifyingglass")

            Slider(value: completedTakeZoomSliderBinding, in: 0...1)
                #if os(macOS)
                .frame(minWidth: 150, maxWidth: 200)
                #else
                .frame(minWidth: 100, maxWidth: 220)
                #endif
            Image(systemName: "plus.magnifyingglass")
        }
        .padding(.horizontal, 6)
    }

    private func inlineLabeledValue(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.takeMetadataLabel)
            Text(value)
                .font(.takeMetadataValue)
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

    private func completedTakeNavigationTitle(for takeID: UUID) -> String {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            return ""
        }
        #endif
        return viewModel.recentTake(id: takeID)?.displayTitle ?? "Take"
    }

    private func completedTakeRenderTaskID(for takeID: UUID) -> String {
        "\(takeID.uuidString)-\(completedTakeRenderDelayRequestID)"
    }

    private var completedTakeZoomSliderBinding: Binding<CGFloat> {
        Binding(
            get: {
                sliderValue(for: pianoRollZoomLevel)
            },
            set: { sliderValue in
                pianoRollZoomLevel = zoomLevel(for: sliderValue)
            }
        )
    }

    private func sliderValue(for zoomLevel: CGFloat) -> CGFloat {
        let clampedZoom = max(0.0, min(1.0, zoomLevel))
        let base = completedTakeZoomSliderCurveBase
        return log(1.0 + (base - 1.0) * clampedZoom) / log(base)
    }
    private func zoomLevel(for sliderValue: CGFloat) -> CGFloat {
        let clampedSliderValue = max(0.0, min(1.0, sliderValue))
        let base = completedTakeZoomSliderCurveBase
        return (pow(base, clampedSliderValue) - 1.0) / (base - 1.0)
    }
    private var completedTakeZoomSliderCurveBase: CGFloat { 9.0 }
    private func waitForCompletedTakeDetailTransition() async {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            try? await Task.sleep(for: .milliseconds(450))
        }
        #endif
    }
}
