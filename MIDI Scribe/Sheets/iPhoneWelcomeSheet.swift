//
//  iPhoneWelcomeSheet.swift
//  MIDI Scribe
//

import SwiftUI

#if os(iOS)

struct PhoneWelcomeSheet: View {
    let kind: OnboardingPresentationKind
    let panes: [OnboardingPane]
    @Binding var selection: Int
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $selection) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                        PhoneWelcomePaneCard(kind: kind, pane: pane)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 8) {
                    ForEach(0..<panes.count, id: \.self) { index in
                        Circle()
                            .fill(dotColor(for: index))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if kind == .help {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary, Color(uiColor: .tertiarySystemFill))
                                .font(.title2)
                        }
                    } else if selection == panes.count - 1 {
                        BasicButton(
                            context: BasicButtonContext(
                                action: onClose,
                                label: kind.primaryButtonTitle
                            )
                        )
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func dotColor(for index: Int) -> Color {
        if index == selection {
            return Color.accentColor
        } else {
            return Color.primary.opacity(0.2)
        }
    }
}

#endif

#if os(iOS)

private struct PhoneWelcomePaneCard: View {
    let kind: OnboardingPresentationKind
    let pane: OnboardingPane

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kind.title)
                        .font(.title2.weight(.semibold))
                    Text(kind.subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)

                OnboardingPaneText(pane: pane)
                OnboardingScreenshotPlaceholder(
                    pane: pane,
                    platformLabel: "iPhone Landscape Screenshot",
                    assetHint: "Onboarding/iPhone/\(pane.screenshotSlot.rawValue)"
                )
                .scaledToFit()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

#endif
