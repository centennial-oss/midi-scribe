//
//  SettingsView.swift
//  MIDI Scribe
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appState: AppState
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void
    /// Invoked from **iPhone** “Load Sample Takes…” only (no menu bar on phone).
    let onLoadSampleTakes: () -> Void

    @State private var alertState: SettingsAlertState?
    @State private var isErasing = false

    private let allowedDelayValues: [Double] =
        [1, 3, 5] + Array(stride(from: 10, through: 600, by: 10)).map(Double.init)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("MIDI Input Channel", selection: $settings.monitoredMIDIChannel) {
                        Text("All Channels").tag(AppSettings.midiChannelAllValue)
                        ForEach(1...16, id: \.self) { channel in
                            Text("Channel \(channel)").tag(channel)
                        }
                    }

                    Picker("Playback Instrument", selection: $settings.speakerOutputProgram) {
                        ForEach(GeneralMIDI.programs) { program in
                            Text(program.name).tag(program.program)
                        }
                    }
                    HStack {
                        Text("End Take When Idle for")
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
                        Text(DurationFormatting.compactWholeSeconds(settings.newTakePauseSeconds))
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
                }

                TakeStartEndControlSection(settings: settings)

                Section {
                    HStack {
                        Text("Sample Take Data")
                        Spacer()
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
                    }
                    Text("Adds several public-domain classical songs to your Recent Takes list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Danger Zone")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.red)
                        HStack {
                            Button("Reset All Preferences", role: .destructive) {
                                alertState = .confirmResetPreferences
                            }
                            .disabled(isErasing)
                            Spacer()
                            Button(role: .destructive) {
                                alertState = .confirmEraseAllData
                            } label: {
                                HStack(spacing: 8) {
                                    if isErasing {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("Erasing…")
                                    } else {
                                        Text("Erase All Takes + Reset Preferences")
                                    }
                                }
                            }
                            .disabled(isErasing)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .formStyle(.grouped)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    BasicButton(context: BasicButtonContext(action: onClose, label: "Close"))
                }
            }
            .alert(item: $alertState) { state in
                switch state {
                case .confirmEraseAllData:
                    return Alert(
                        title: Text("Erase All Data?"),
                        message: Text(
                            "This will permanently delete every recorded Take and all MIDI events, "
                                + "then clear all saved preferences and restore defaults. "
                                + "This action cannot be undone."
                        ),
                        primaryButton: .destructive(Text("Erase All Data")) {
                            eraseAllData()
                        },
                        secondaryButton: .cancel()
                    )
                case .confirmResetPreferences:
                    return Alert(
                        title: Text("Reset All Preferences?"),
                        message: Text("This will clear all saved preferences and restore defaults."),
                        primaryButton: .destructive(Text("Reset")) {
                            settings.resetAllPreferences()
                            alertState = .preferencesReset
                        },
                        secondaryButton: .cancel()
                    )
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
                        message: Text("All save data erased. \(AppIdentifier.name) has been reset."),
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
        .frame(minWidth: 460)
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

private struct TakeStartEndControlSection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 24) {
                startSignalGroup
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                controlSignalGroup(
                    title: "End a Take With",
                    signals: TakeControlSignal.takeEndOptions,
                    selection: $settings.takeEndControlChanges
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var startSignalGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start a Take With")
            .font(.system(size: 14, weight: .semibold))
            Toggle(
                TakeControlSignal.notes.name,
                isOn: $settings.startTakeWithNoteEvents
            )
            .toggleStyle(CheckboxToggleStyle())
            .tint(.accentColor)

            ForEach(TakeControlSignal.takeStartOptions.filter { $0 != .notes }) { signal in
                Toggle(
                    "\(signal.name) \(signal.detail)",
                    isOn: controlSignalBinding(signal, selection: $settings.takeStartControlChanges)
                )
                .toggleStyle(CheckboxToggleStyle())
                .tint(.accentColor)
            }
        }
    }

    private func controlSignalGroup(
        title: String,
        signals: [TakeControlSignal],
        selection: Binding<Set<UInt8>>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            .font(.system(size: 14, weight: .semibold))
            .tint(.accentColor)
            ForEach(signals) { signal in
                Toggle(
                    "\(signal.name) \(signal.detail)",
                    isOn: controlSignalBinding(signal, selection: selection)
                )
                .toggleStyle(CheckboxToggleStyle())
            }
        }
    }

    private func controlSignalBinding(
        _ signal: TakeControlSignal,
        selection: Binding<Set<UInt8>>
    ) -> Binding<Bool> {
        Binding(
            get: {
                signal.controlChangeNumbers.isSubset(of: selection.wrappedValue)
            },
            set: { isSelected in
                if isSelected {
                    selection.wrappedValue.formUnion(signal.controlChangeNumbers)
                } else {
                    selection.wrappedValue.subtract(signal.controlChangeNumbers)
                }
            }
        )
    }
}

private enum SettingsAlertState: Identifiable {
    case confirmEraseAllData
    case confirmResetPreferences
    case sampleTakesLoaded(count: Int)
    case sampleTakesFailed(message: String)
    case eraseAllSucceeded
    case eraseAllFailed(message: String)
    case preferencesReset

    var id: String {
        switch self {
        case .confirmEraseAllData:
            return "confirm-erase-all-data"
        case .confirmResetPreferences:
            return "confirm-reset-preferences"
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
