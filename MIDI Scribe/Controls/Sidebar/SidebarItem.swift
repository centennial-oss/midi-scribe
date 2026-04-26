//
//  SidebarItem.swift
//  MIDI Scribe
//
//  Created by James Ranson on 4/23/26.
//

import SwiftUI

struct SidebarItem<Value: Hashable, Content: View>: View {
    let value: Value
    let isSelected: Bool
    let allowsNestedInteractions: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarMultiSelectContext) private var multiSelectContext
    @Environment(\.sidebarAfterDetailChangeRowAction) private var afterDetailChangeRowAction
    #if os(macOS)
    @ObservedObject private var macApplicationIsActive = MacApplicationIsActiveState.shared
    #endif
    @ViewBuilder let content: () -> Content

    private var isDarkAppearance: Bool { colorScheme == .dark }

    init(
        value: Value,
        isSelected: Bool,
        allowsNestedInteractions: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.value = value
        self.isSelected = isSelected
        self.allowsNestedInteractions = allowsNestedInteractions
        self.action = action
        self.content = content
    }

    var body: some View {
        if multiSelectContext.isEnabled {
            let isDisabled = multiSelectContext.isValueDisabled(AnyHashable(value))
            Button {
                multiSelectContext.toggleValue(AnyHashable(value))
            } label: {
                Checkbox(isOn: multiSelectContext.isValueSelected(AnyHashable(value))) {
                    label
                }
                #if os(iOS)
                .padding(.vertical, 4)
                #endif
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isDisabled ? 0.45 : 1)
        } else {
            if allowsNestedInteractions {
                styledLabel
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture().onEnded {
                            let detailSelectionChanges = !isSelected
                            action()
                            if detailSelectionChanges {
                                afterDetailChangeRowAction()
                            }
                        },
                        including: .gesture
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        let detailSelectionChanges = !isSelected
                        action()
                        if detailSelectionChanges {
                            afterDetailChangeRowAction()
                        }
                    }
            } else {
                Button {
                    let detailSelectionChanges = !isSelected
                    action()
                    if detailSelectionChanges {
                        afterDetailChangeRowAction()
                    }
                } label: {
                    styledLabel
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var label: some View {
        content()
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var styledLabel: some View {
        #if os(macOS)
        label
            .padding(.vertical, 2)
            .background(
                isSelected
                    ? (macApplicationIsActive.isActive
                        ? (isDarkAppearance
                        ? Color(red: 0.16, green: 0.16, blue: 0.16)
                        : Color(red: 0.87, green: 0.87, blue: 0.87))
                        : (isDarkAppearance
                            ? Color(white: 0.27)
                            : Color(white: 0.86)))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .foregroundStyle(
                isSelected
                    ? (macApplicationIsActive.isActive
                        ? Color.accentColor
                        : (isDarkAppearance
                            ? Color(white: 0.49)
                            : Color(white: 0.58)))
                    : Color.primary
            )
        #elseif os(iOS)
        label
            .padding(.vertical, 4)
            .background(
                isSelected
                    ? (isDarkAppearance
                        ? Color(red: 0.16, green: 0.16, blue: 0.16)
                        : Color(red: 0.87, green: 0.87, blue: 0.87))
                    : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        #else
        label
            .background(
                isSelected ? Color.secondary.opacity(0.15) : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
        #endif
    }
}
