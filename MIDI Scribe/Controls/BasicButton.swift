//
//  BasicButton.swift
//  MIDI Scribe
//

import SwiftUI

struct BasicButton: View {
    let action: () -> Void
    let label: String
    let keyboardShortcut: KeyboardShortcut?

    init(
        action: @escaping () -> Void,
        label: String,
        keyboardShortcut: KeyboardShortcut? = nil
    ) {
        self.action = action
        self.label = label
        self.keyboardShortcut = keyboardShortcut
    }

    @ViewBuilder
    var body: some View {
        if let keyboardShortcut {
            Button(label, action: action)
                .font(.system(size: 15))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(keyboardShortcut)
        } else {
            Button(label, action: action)
                .font(.system(size: 15))
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
