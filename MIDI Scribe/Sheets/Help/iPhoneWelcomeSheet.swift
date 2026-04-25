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
            .padding(.bottom, -12)
            .padding(.top, 48)
        }
        .overlay(alignment: .top) {
            footer
                .padding(.horizontal, 8)
                .padding(.top, 8)
        }
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
                .padding(.top, 14)
            }
        }
        .presentationDetents([.large])
    }

    private var footer: some View {
        ZStack {
            paneTitle
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
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
        selection < panes.count - 1 &&
        !(selectedPane?.hideCloseButton ?? false)
    }

    private var shouldShowPrimaryAction: Bool {
        kind == .welcome && selection == panes.count - 1
    }
}

#endif
