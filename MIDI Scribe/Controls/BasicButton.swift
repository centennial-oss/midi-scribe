//
//  BasicButton.swift
//  MIDI Scribe
//

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct BasicButtonContext {
    let action: () -> Void
    let label: String
    var systemImage: String?
    var role: ButtonRole?
    var keyboardShortcut: KeyboardShortcut?
    var size: ControlSize
    var labelWeight: Font.Weight
    var backgroundColor: Color?
    var foregroundColor: Color?
    var contentWidth: CGFloat?
    var contentHeight: CGFloat?

    init(
        action: @escaping () -> Void,
        label: String,
        systemImage: String? = nil,
        role: ButtonRole? = nil,
        keyboardShortcut: KeyboardShortcut? = nil,
        size: ControlSize = .large,
        labelWeight: Font.Weight = .semibold,
        backgroundColor: Color? = nil,
        foregroundColor: Color? = nil,
        contentWidth: CGFloat? = nil,
        contentHeight: CGFloat? = nil
    ) {
        self.action = action
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.keyboardShortcut = keyboardShortcut
        self.size = size
        self.labelWeight = labelWeight
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
    }
}

struct BasicButton: View {
    let context: BasicButtonContext

    private var isDestructive: Bool {
        context.role == .destructive
    }

    private var labelColor: Color {
        if let foregroundColor = context.foregroundColor {
            return foregroundColor
        }
        if context.backgroundColor != nil {
            return .primary
        }
#if os(macOS)
    return Color(nsColor: .windowBackgroundColor)
#else
    return Color(uiColor: .systemBackground)
#endif
    }

    @ViewBuilder
    private var labelContent: some View {
        Group {
            if let systemImage = context.systemImage {
                Label(context.label, systemImage: systemImage)
            } else {
                Text(context.label)
            }
        }
        .frame(width: context.contentWidth, height: context.contentHeight)
        .foregroundStyle(labelColor)
    }

    @ViewBuilder
    private func chrome<Content: View>(_ button: Content) -> some View {
        if let backgroundColor = context.backgroundColor {
            button
                .font(.system(size: 15, weight: context.labelWeight))
                .buttonStyle(.glassProminent)
                .tint(backgroundColor)
                .controlSize(context.size)
        } else if isDestructive {
            button
                .font(.system(size: 15, weight: context.labelWeight))
                .buttonStyle(.glassProminent)
                .tint(.red)
                .controlSize(context.size)
        } else {
            button
                .font(.system(size: 15, weight: context.labelWeight))
                .buttonStyle(.glassProminent)
                .controlSize(context.size)
        }
    }

    @ViewBuilder
    var body: some View {
        let action = context.action
        if let keyboardShortcut = context.keyboardShortcut {
            if let role = context.role {
                chrome(Button(role: role, action: action) { labelContent })
                    .accessibilityLabel(context.label)
                    .keyboardShortcut(keyboardShortcut)
            } else {
                chrome(Button(action: action) { labelContent })
                    .accessibilityLabel(context.label)
                    .keyboardShortcut(keyboardShortcut)
            }
        } else if let role = context.role {
            chrome(Button(role: role, action: action) { labelContent })
                .accessibilityLabel(context.label)
        } else {
            chrome(Button(action: action) { labelContent })
                .accessibilityLabel(context.label)
        }
    }
}
