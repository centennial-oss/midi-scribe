//
//  SettingsView.swift
//  MIDI Scribe
//
//  Created by Codex on 3/21/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    private let allowedDelayValues: [Double] = [1, 3, 5] + Array(stride(from: 10, through: 600, by: 10)).map(Double.init)

    var body: some View {
        NavigationStack {
            Form {
                Picker("MIDI Channels", selection: $settings.monitoredMIDIChannel) {
                    Text("All Channels").tag(AppSettings.midiChannelAllValue)
                    ForEach(1...16, id: \.self) { channel in
                        Text("Channel \(channel)").tag(channel)
                    }
                }

                HStack {
                    Text("New Take Delay")
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

                Stepper(value: $settings.recentTakesShownInMenus, in: 1...25) {
                    HStack {
                        Text("Recent Takes in Menus")
                        Spacer()
                        Text("\(settings.recentTakesShownInMenus)")
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Speaker Instrument", selection: $settings.speakerOutputProgram) {
                    ForEach(GeneralMIDI.programs) { program in
                        Text(program.name).tag(program.program)
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
        }
        .frame(minWidth: 460, minHeight: 280)
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
