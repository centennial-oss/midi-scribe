//
//  OnboardingCarouselViews.swift
//  MIDI Scribe
//

import SwiftUI

// Carries measured tooltip sizes keyed by annotation ID, so the parent can
// compute the correct center-from-caret-tip offset after the first layout pass.
struct TooltipSizePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGSize] = [:]
    static func reduce(value: inout [String: CGSize], nextValue: () -> [String: CGSize]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct OnboardingSwipeCarouselView: View {
    let panes: [OnboardingPane]
    @Binding var selection: Int

    var body: some View {
        ZStack {
            if panes.indices.contains(selection) {
                OnboardingPaneView(
                    pane: panes[selection]
                )
                .id(selection)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 36)
                .onEnded { value in
                    handleSwipe(width: value.translation.width)
                }
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                advance()
            case .decrement:
                goBack()
            @unknown default:
                break
            }
        }
        .animation(.easeInOut(duration: 0.22), value: selection)
    }

    private func handleSwipe(width: CGFloat) {
        guard abs(width) >= 52 else { return }
        if width < 0 {
            advance()
        } else {
            goBack()
        }
    }

    private func advance() {
        guard selection < panes.count - 1 else { return }
        selection += 1
    }

    private func goBack() {
        guard selection > 0 else { return }
        selection -= 1
    }
}

struct OnboardingPageDots: View {
    let count: Int
    let selection: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityLabel("Page \(selection + 1) of \(count)")
    }

    private func dotColor(for index: Int) -> Color {
        if index == selection {
            return Color.accentColor
        } else {
            return Color.primary.opacity(0.22)
        }
    }
}

struct OnboardingPaneView: View {
    let pane: OnboardingPane

    var body: some View {
        switch pane.content {
        case let .message(kind):
            OnboardingMessagePaneView(kind: kind)
        case let .screenshot(content):
            OnboardingScreenshotPaneView(
                content: content
            )
        }
    }
}

private struct OnboardingMessagePaneView: View {
    let kind: OnboardingMessageKind

    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 18) {
                AppIconImage()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(kind.header)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }

            if let body = kind.body {
                Text(body)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
