//
//  SettingsView.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void
    /// Invoked from **iPhone** “Load Sample Takes…” only (no menu bar on phone).
    let onLoadSampleTakes: () -> Void

    @State private var isConfirmingEraseAll = false
    @State private var isConfirmingResetPreferences = false
    @State private var alertState: SettingsAlertState?
    @State private var isErasing = false

    private let allowedDelayValues: [Double] =
        [1, 3, 5] + Array(stride(from: 10, through: 600, by: 10)).map(Double.init)

    var body: some View {
        NavigationStack {
            Form {
                Picker("MIDI Input Channel", selection: $settings.monitoredMIDIChannel) {
                    Text("All Channels").tag(AppSettings.midiChannelAllValue)
                    ForEach(1...16, id: \.self) { channel in
                        Text("Channel \(channel)").tag(channel)
                    }
                }

                HStack {
                    Text("End Take when Idle For")
                    Spacer()
#if os(macOS)
                    DiscreteSettingsSlider(
                        value: newTakeDelaySliderValue,
                        range: 0...Double(allowedDelayValues.count - 1)
                    )
                    .frame(maxWidth: 175)
#else
                    Slider(value: newTakeDelaySliderValue, in: 0...Double(allowedDelayValues.count - 1), step: 1)
                        .frame(maxWidth: 175)
#endif
                    Text(formattedDelay(settings.newTakePauseSeconds))
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }

                Stepper(value: $settings.recentTakesShownInMenus, in: 1...99) {
                    HStack {
                        Text("# Recent Takes to Keep")
                        Spacer()
                        Text("\(settings.recentTakesShownInMenus)")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Playback Instrument", selection: $settings.speakerOutputProgram) {
                    ForEach(GeneralMIDI.programs) { program in
                        Text(program.name).tag(program.program)
                    }
                }

                Section("Demo Data") {
                    Button {
                        onLoadSampleTakes()
                    } label: {
                        HStack(spacing: 8) {
                            if appState.isLoadingSampleTakes {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading…")
                            } else {
                                Text("Load Sample Takes")
                            }
                        }
                    }
                    .disabled(appState.isLoadingSampleTakes)
                    Text("Adds several public-domain songs to your Recent Takes list.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Danger Zone") {
                    Button("Reset All Preferences", role: .destructive) {
                        isConfirmingResetPreferences = true
                    }

                    HStack {
                        Button("Erase All Takes + Reset Preferences", role: .destructive) {
                            isConfirmingEraseAll = true
                        }
                        .disabled(isErasing)

                        if isErasing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Erasing…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: onClose)
                }
            }
            .alert("Erase All Data?", isPresented: $isConfirmingEraseAll) {
                Button("Yes, I Understand", role: .destructive) {
                    eraseAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This will permanently delete every recorded take and all of their MIDI events. "
                        + "This action cannot be undone."
                )
            }
            .alert("Reset All Preferences?", isPresented: $isConfirmingResetPreferences) {
                Button("Reset", role: .destructive) {
                    settings.resetAllPreferences()
                    alertState = .preferencesReset
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear all saved preferences and restore defaults.")
            }
            .alert(item: $alertState) { state in
                switch state {
                case .sampleTakesLoaded(let count):
                    return Alert(
                        title: Text("Sample Takes Loaded"),
                        message: Text("Added \(count) sample take\(count == 1 ? "" : "s") to Recent Takes."),
                        dismissButton: .default(Text("OK"))
                    )
                case .sampleTakesFailed(let message):
                    return Alert(
                        title: Text("Unable to Load Sample Takes"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                case .eraseAllSucceeded:
                    return Alert(
                        title: Text("Data Erased"),
                        message: Text("All save data erased. MIDI Scribe has been reset."),
                        dismissButton: .default(Text("OK"))
                    )
                case .eraseAllFailed(let message):
                    return Alert(
                        title: Text("Erase Failed"),
                        message: Text(message),
                        dismissButton: .default(Text("OK"))
                    )
                case .preferencesReset:
                    return Alert(
                        title: Text("Preferences Reset"),
                        message: Text("All saved preferences were reset to defaults."),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
            .onChange(of: appState.sampleTakeLoadResult) { _, result in
                guard let result else { return }
                switch result {
                case .success(let count):
                    alertState = .sampleTakesLoaded(count: count)
                case .failure(let message):
                    alertState = .sampleTakesFailed(message: message)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 280)
    }

    private func eraseAllData() {
        guard !isErasing else { return }
        isErasing = true

        let container = modelContext.container
        Task {
            let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                do {
                    // Use store-level bulk delete on the parent model only.
                    // Deleting child rows directly can violate the mandatory
                    // inverse constraint on StoredMIDIEvent.take.
                    try context.delete(model: StoredTake.self)
                    try context.save()
                    return .success(())
                } catch {
                    return .failure(error)
                }
            }.value

            isErasing = false
            switch result {
            case .success:
                settings.resetAllPreferences()
                appState.requestDataReset()
                alertState = .eraseAllSucceeded
            case .failure(let error):
                alertState = .eraseAllFailed(message: "Failed to erase: \(error.localizedDescription)")
            }
        }
    }

    private func formattedDelay(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return "\(minutes)m \(remainingSeconds)s"
    }

    private var newTakeDelaySliderValue: Binding<Double> {
        Binding(
            get: {
                Double(delayIndex(for: settings.newTakePauseSeconds))
            },
            set: { newValue in
                let index = min(max(Int(newValue.rounded()), 0), allowedDelayValues.count - 1)
                settings.newTakePauseSeconds = allowedDelayValues[index]
            }
        )
    }

    private func delayIndex(for seconds: Double) -> Int {
        let closest = allowedDelayValues.enumerated().min { lhs, rhs in
            abs(lhs.element - seconds) < abs(rhs.element - seconds)
        }
        return closest?.offset ?? 0
    }
}

private enum SettingsAlertState: Identifiable {
    case sampleTakesLoaded(count: Int)
    case sampleTakesFailed(message: String)
    case eraseAllSucceeded
    case eraseAllFailed(message: String)
    case preferencesReset

    var id: String {
        switch self {
        case .sampleTakesLoaded(let count):
            return "sample-loaded-\(count)"
        case .sampleTakesFailed(let message):
            return "sample-failed-\(message)"
        case .eraseAllSucceeded:
            return "erase-succeeded"
        case .eraseAllFailed(let message):
            return "erase-failed-\(message)"
        case .preferencesReset:
            return "preferences-reset"
        }
    }
}

#if os(macOS)
private struct DiscreteSettingsSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        if nsView.doubleValue != value {
            nsView.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        private var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc
        func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue.rounded()
        }
    }
}
#endif
