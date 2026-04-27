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

    var body: some View {
        #if os(macOS)
        sheetContent()
            .frame(width: 750, height: 720)
        #else
        sheetContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private func sheetContent() -> some View {
        NavigationStack {
            VStack(spacing: 8) {
                onboardingHeader
                OnboardingSwipeCarouselView(
                    panes: panes,
                    selection: $selection
                )
                .aspectRatio(4 / 3, contentMode: .fit)
                .frame(maxWidth: .infinity)
                onboardingFooter
            }
            .padding(.horizontal, 20)
            .padding(.bottom, BuildInfo.isPad ? -20 : 0)
            .overlay(alignment: .topTrailing) {
                if shouldShowTopCloseButton {
                    Button {
                        onClose()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.clear)
                                .frame(width: 44, height: 44)

                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.primary)
                                .padding(10)
                                .glassEffect(.regular.interactive(), in: Circle())
                        }
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    .padding(.trailing, 20)
                }
            }
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: 14) {
            AppIconImage()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(kind.title)
                .font(.title.weight(.semibold))
            if let title = selectedPane?.title, selectedPane?.title != "" {
                Text("/")
                .font(.title)
                .foregroundStyle(.secondary)
                Text(title)
                .font(.title)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var onboardingFooter: some View {
        HStack {
            if selection > 0 {
                BasicButton(
                    context: BasicButtonContext(
                        action: goBack,
                        label: "Back",
                        size: .large
                    )
                )
            }

            Spacer()

            OnboardingPageDots(count: panes.count, selection: selection)

            Spacer()

            BasicButton(
                context: BasicButtonContext(
                    action: advanceOrClose,
                    label: selection == panes.count - 1 ? kind.primaryButtonTitle : "Next",
                    size: .large
                )
            )
        }
        .padding(.horizontal, 24)
    }

    private var shouldShowTopCloseButton: Bool {
        kind == .help &&
        selection < panes.count - 1 &&
        !(selectedPane?.hideCloseButton ?? false)
    }

    private var selectedPane: OnboardingPane? {
        guard panes.indices.contains(selection) else { return nil }
        return panes[selection]
    }

    private func goBack() {
        guard panes.indices.contains(selection),
              panes.indices.contains(selection - 1) else {
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) {
            selection -= 1
        }
    }

    private func advanceOrClose() {
        guard panes.indices.contains(selection) else {
            return
        }

        if panes.indices.contains(selection + 1) {
            withAnimation(.easeInOut(duration: 0.22)) {
                selection += 1
            }
        } else {
            onClose()
        }
    }
}
