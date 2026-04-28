//
//  ContentViewToolbarIconButton.swift
//  MIDI Scribe
//

import SwiftUI

extension ContentView {
    func toolbarIconButton(
        _ label: String,
        systemImage: String,
        disabled: Bool,
        role: ButtonRole? = nil,
        foregroundStyle: Color? = nil,
        opacity: Double = 1,
        showTextLabel: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            if showTextLabel {
                Label(label, systemImage: systemImage)
                    .foregroundStyle(foregroundStyle ?? (disabled ? Color.secondary : Color.primary))
                    .opacity(opacity)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(foregroundStyle ?? (disabled ? Color.secondary : Color.primary))
                    .opacity(opacity)
            }
        }
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }
}
