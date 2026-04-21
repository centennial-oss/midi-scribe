//
//  RoundCheckbox.swift
//  MIDI Scribe
//

import SwiftUI

struct RoundCheckbox<Label: View>: View {
    let isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .imageScale(.medium)
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            label()
            Spacer(minLength: 0)
        }
    }
}

struct RoundCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            RoundCheckbox(isOn: configuration.isOn) {
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}
