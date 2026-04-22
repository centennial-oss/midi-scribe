//
//  iPadMacWelcomeSheet.swift
//  MIDI Scribe
//

import SwiftUI

struct IPadMacWelcomeSheet: View {
    let kind: OnboardingPresentationKind
    let panes: [OnboardingPane]
    @Binding var selection: Int
    let onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                onboardingHeader

                carouselContent

                onboardingFooter
            }
            .padding(24)
            .overlay(alignment: .topTrailing) {
                if kind == .help {
                    BasicButton(
                        context: BasicButtonContext(
                            action: onClose,
                            label: "Close",
                            systemImage: "xmark",
                            size: .regular
                        )
                    )
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 760, idealWidth: 920, minHeight: 620, idealHeight: 700)
    }

    @ViewBuilder
    private var carouselContent: some View {
        #if os(iOS)
        TabView(selection: $selection) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, pane in
                IPadMacWelcomePaneCard(pane: pane)
                    .padding(.horizontal, 2)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .interactive))
        #else
        VStack(spacing: 14) {
            if panes.indices.contains(selection) {
                IPadMacWelcomePaneCard(pane: panes[selection])
                    .padding(.horizontal, 2)
                    .id(selection)
                    .transition(.opacity)
            }

            HStack(spacing: 8) {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, _ in
                    Circle()
                        .fill(dotColor(for: index))
                        .frame(width: 8, height: 8)
                }
            }
        }
        #endif
    }

    private func dotColor(for index: Int) -> Color {
        if index == selection {
            return Color.accentColor
        } else {
            return Color.primary.opacity(0.2)
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 14) {
            AppIconImage()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title)
                    .font(.title.weight(.semibold))
                Text(kind.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
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

private struct IPadMacWelcomePaneCard: View {
    let pane: OnboardingPane

    var body: some View {
        HStack(spacing: 24) {
            OnboardingScreenshotPlaceholder(
                pane: pane,
                platformLabel: "Mac / iPad Screenshot",
                assetHint: "Onboarding/Shared/\(pane.screenshotSlot.rawValue)"
            )

            OnboardingPaneText(pane: pane)
                .frame(width: 300, alignment: .topLeading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
    }
}

struct OnboardingPaneText: View {
    let pane: OnboardingPane

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pane.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(pane.title)
                .font(.title3.weight(.semibold))

            Text(pane.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(pane.bullets, id: \.self) { bullet in
                    Label(bullet, systemImage: "circle.fill")
                        .font(.body)
                        .labelStyle(OnboardingBulletLabelStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct OnboardingScreenshotPlaceholder: View {
    let pane: OnboardingPane
    let platformLabel: String
    let assetHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.16),
                            Color.secondary.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                        .foregroundStyle(.secondary.opacity(0.45))
                }
                .overlay(alignment: .center) {
                    VStack(spacing: 10) {
                        Image(systemName: screenshotSymbol)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(platformLabel)
                            .font(.headline)
                        Text(pane.title)
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Text(assetHint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(20)
                }
                .aspectRatio(16 / 9, contentMode: .fit)

            Text("Replace this placeholder with an annotated screenshot for this pane.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var screenshotSymbol: String {
        switch pane.screenshotSlot {
        case .liveTake:
            return "record.circle"
        case .playback:
            return "play.rectangle"
        case .editing:
            return "timeline.selection"
        case .bulkEdit:
            return "square.stack.3d.up"
        case .settings:
            return "gearshape"
        }
    }
}

private struct OnboardingBulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.icon
                .font(.system(size: 7))
                .padding(.top, 6)
                .foregroundStyle(.secondary)
            configuration.title
                .foregroundStyle(.primary)
        }
    }
}
