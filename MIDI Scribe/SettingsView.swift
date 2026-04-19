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
#if os(iOS)
import UIKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void
    /// Invoked from **iPhone** “Load Sample Takes…” only (no menu bar on phone).
    let onLoadSampleTakes: () -> Void

    @State private var isConfirmingEraseAll = false
    @State private var eraseResultMessage: String?
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

                Section("Danger Zone") {
#if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .phone {
                        Button("Load Sample Takes…") {
                            onLoadSampleTakes()
                        }
                    }
#endif
                    HStack {
                        Button("Erase All Data", role: .destructive) {
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

                    if let eraseResultMessage {
                        Text(eraseResultMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
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
                        + "MIDI Scribe will need to be quit and relaunched afterward. "
                        + "This action cannot be undone."
                )
            }
        }
        .frame(minWidth: 460, minHeight: 280)
    }

    private func eraseAllData() {
        guard !isErasing else { return }
        isErasing = true
        eraseResultMessage = nil

        let container = modelContext.container
        Task {
            let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                // Locate the underlying store file(s) from the container's
                // configuration, then delete them (plus the SQLite sidecar
                // files -shm and -wal). This is the only reliable path:
                // `delete(model:)` can fail on mandatory inverse nullify,
                // and `ModelContainer.deleteAllData()` is documented-broken.
                do {
                    let storeURL = container.configurations.first?.url
                        ?? URL.applicationSupportDirectory.appending(path: "default.store")

                    let fileManager = FileManager.default
                    let candidates = [
                        storeURL,
                        storeURL.appendingPathExtension("shm"),
                        storeURL.appendingPathExtension("wal"),
                        URL(fileURLWithPath: storeURL.path + "-shm"),
                        URL(fileURLWithPath: storeURL.path + "-wal")
                    ]
                    for url in candidates where fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                    return .success(storeURL)
                } catch {
                    return .failure(error)
                }
            }.value

            isErasing = false
            switch result {
            case .success:
                eraseResultMessage = "All data erased. Please quit and relaunch MIDI Scribe to continue."
            case .failure(let error):
                eraseResultMessage = "Failed to erase: \(error.localizedDescription)"
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
