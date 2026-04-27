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
    private var labelFont: Font {
        .system(size: 15, weight: context.labelWeight)
    }

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
        HStack(spacing: 8) {
            if let systemImage = context.systemImage {
                Image(systemName: systemImage)
                    .font(labelFont)
            }
            Text(context.label)
                .font(labelFont)
        }
        .frame(width: context.contentWidth, height: context.contentHeight)
        .foregroundStyle(labelColor)
    }

    @ViewBuilder
    private func chrome<Content: View>(_ button: Content) -> some View {
        if let backgroundColor = context.backgroundColor {
            if #available(iOS 26.0, macOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
                    .tint(backgroundColor)
                    .controlSize(context.size)
            } else {
                button
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .tint(backgroundColor).controlSize(context.size)
            }
        } else if isDestructive {
            if #available(iOS 26.0, macOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .controlSize(context.size)
            } else {
                button
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .tint(.red)
                    .controlSize(context.size)
            }
        } else {
            if #available(iOS 26.0, macOS 26.0, *) {
                button
                    .buttonStyle(.glassProminent)
                    .controlSize(context.size)
            } else {
                button
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    .controlSize(context.size)
            }
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
