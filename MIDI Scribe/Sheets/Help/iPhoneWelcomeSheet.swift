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
        ZStack {
            OnboardingSwipeCarouselView(
                panes: panes,
                selection: $selection
            )
            .padding(.horizontal, 8)
            .padding(.bottom, -6)
            .padding(.top, 44)
        }
        .overlay(alignment: .top) {
            header
                .padding(.horizontal, 8)
                .padding(.top, 12)
        }
        .overlay(alignment: .topTrailing) {
            if shouldShowTopCloseButton {
                FloatingSheetCloseButton(action: onClose)
                    .padding(.trailing, -22)
                    .padding(.top, 5)
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        ZStack {
            paneTitle
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 0)
                .padding(.leading, 4)

            OnboardingPageDots(count: panes.count, selection: selection)

            if shouldShowPrimaryAction {
                BasicButton(
                    context: BasicButtonContext(
                        action: onClose,
                        label: kind.primaryButtonTitle,
                        size: .regular
                    )
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var paneTitle: some View {
        HStack {
            Text("Help")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let title = selectedPane?.title {
                Text("/")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var selectedPane: OnboardingPane? {
        guard panes.indices.contains(selection) else { return nil }
        return panes[selection]
    }

    private var shouldShowTopCloseButton: Bool {
        kind == .help &&
        !(selectedPane?.hideCloseButton ?? false)
    }

    private var shouldShowPrimaryAction: Bool {
        kind == .welcome && selection == panes.count - 1
    }
}

#endif
