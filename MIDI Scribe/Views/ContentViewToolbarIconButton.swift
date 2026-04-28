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
            toolbarIconButtonLabel(
                label,
                systemImage: systemImage,
                disabled: disabled,
                foregroundStyle: foregroundStyle,
                opacity: opacity,
                showTextLabel: showTextLabel
            )
        }
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func toolbarIconButtonLabel(
        _ label: String,
        systemImage: String,
        disabled: Bool,
        foregroundStyle: Color?,
        opacity: Double,
        showTextLabel: Bool
    ) -> some View {
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
}
