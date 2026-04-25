//
//  SidebarButton.swift
//

import SwiftUI

struct SidebarButtonContext {
    let action: () -> Void
    let accessibilityLabel: String
    var systemImage: String
    var role: ButtonRole?
    var keyboardShortcut: KeyboardShortcut?
    var size: ControlSize
    var foregroundColor: Color?

    init(
        action: @escaping () -> Void,
        accessibilityLabel: String,
        systemImage: String,
        role: ButtonRole? = nil,
        keyboardShortcut: KeyboardShortcut? = nil,
        size: ControlSize = .large,
        foregroundColor: Color? = nil
    ) {
        self.action = action
        self.accessibilityLabel = accessibilityLabel
        self.systemImage = systemImage
        self.role = role
        self.keyboardShortcut = keyboardShortcut
        self.size = size
        self.foregroundColor = foregroundColor
    }
}

struct SidebarButton: View {
    let context: SidebarButtonContext
    var isToggled = false

    private var isDestructive: Bool {
        context.role == .destructive
    }

    private var labelColor: Color {
        if isToggled {
            return .accentColor
        }
        if let foregroundColor = context.foregroundColor {
            return foregroundColor
        }
        if isDestructive {
            return .red
        }
        return .primary
    }

    @ViewBuilder
    private var labelContent: some View {
        Image(systemName: context.systemImage)
            .foregroundStyle(labelColor)
            .padding(10)
            .contentShape(.interaction, Circle())
            .glassEffect(.regular.interactive(), in: Circle())
    }

    @ViewBuilder
    private func chrome<Content: View>(_ button: Content) -> some View {
        button
            .font(.system(size: BuildInfo.isMac ? 15 : 22))
            .buttonStyle(.plain)
            .controlSize(context.size)
    }

    @ViewBuilder
    var body: some View {
        let action = context.action
        if let keyboardShortcut = context.keyboardShortcut {
            if let role = context.role {
                chrome(Button(role: role, action: action) { labelContent })
                    .accessibilityLabel(context.accessibilityLabel)
                    .keyboardShortcut(keyboardShortcut)
            } else {
                chrome(Button(action: action) { labelContent })
                    .accessibilityLabel(context.accessibilityLabel)
                    .keyboardShortcut(keyboardShortcut)
            }
        } else if let role = context.role {
            chrome(Button(role: role, action: action) { labelContent })
                .accessibilityLabel(context.accessibilityLabel)
        } else {
            chrome(Button(action: action) { labelContent })
                .accessibilityLabel(context.accessibilityLabel)
        }
    }
}
