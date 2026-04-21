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

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                onboardingHeader

                TabView(selection: $selection) {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                        PhoneWelcomePaneCard(pane: pane)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                onboardingFooter
            }
            .padding(16)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    BasicButton(
                        context: BasicButtonContext(
                            action: onClose,
                            label: selection == panes.count - 1 ? kind.primaryButtonTitle : "Skip"
                        )
                    )
                }
            }
        }
        .presentationDetents([.large])
    }

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kind.title)
                .font(.title2.weight(.semibold))
            Text(kind.subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onboardingFooter: some View {
        HStack {
            if selection > 0 {
                Button("Back") {
                    selection -= 1
                }
            }

            Spacer()

            BasicButton(
                context: BasicButtonContext(
                    action: advanceOrClose,
                    label: selection == panes.count - 1 ? kind.primaryButtonTitle : "Next"
                )
            )
        }
    }

    private func advanceOrClose() {
        if selection < panes.count - 1 {
            selection += 1
        } else {
            onClose()
        }
    }
}

#endif

#if os(iOS)

private struct PhoneWelcomePaneCard: View {
    let pane: OnboardingPane

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OnboardingPaneText(pane: pane)
                OnboardingScreenshotPlaceholder(
                    pane: pane,
                    platformLabel: "iPhone Landscape Screenshot",
                    assetHint: "Onboarding/iPhone/\(pane.screenshotSlot.rawValue)"
                )
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

#endif
