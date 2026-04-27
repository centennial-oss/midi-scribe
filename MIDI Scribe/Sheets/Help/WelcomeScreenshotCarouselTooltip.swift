import SwiftUI

struct OnboardingTooltipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let caretPosition: OnboardingCaretPosition
    let avoidsLineWrapping: Bool

    var body: some View {
        Text(label)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(avoidsLineWrapping ? 1 : 4)
            .fixedSize(horizontal: avoidsLineWrapping, vertical: true)
            .padding(.leading, leadingPadding)
            .padding(.trailing, trailingPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .background {
                OnboardingTooltipShape(caretPosition: caretPosition)
                    .fill(tooltipFill)
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
            }
            .overlay {
                OnboardingTooltipShape(caretPosition: caretPosition)
                    .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private let caretDepth: CGFloat = 10

    private var leadingPadding: CGFloat {
        switch caretPosition {
        case .left:
            return horizontalBubblePadding + caretDepth
        case .right, .top, .bottom, .none:
            return 14
        }
    }

    private var trailingPadding: CGFloat {
        switch caretPosition {
        case .right:
            return horizontalBubblePadding + caretDepth
        case .left, .top, .bottom, .none:
            return 14
        }
    }

    private var topPadding: CGFloat {
        switch caretPosition {
        case .top:
            return verticalBubblePadding + caretDepth
        case .bottom:
            return verticalBubblePadding
        case .left, .right, .none:
            return 12
        }
    }

    private var bottomPadding: CGFloat {
        switch caretPosition {
        case .bottom:
            return verticalBubblePadding + caretDepth
        case .top:
            return verticalBubblePadding
        case .left, .right, .none:
            return 12
        }
    }

    private var horizontalBubblePadding: CGFloat {
        switch caretPosition {
        case .left, .right:
            return 13
        case .top, .bottom, .none:
            return 14
        }
    }

    private var verticalBubblePadding: CGFloat {
        switch caretPosition {
        case .top, .bottom:
            return 13
        case .left, .right, .none:
            return 12
        }
    }

    private var tooltipFill: AnyShapeStyle {
        colorScheme == .light ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial)
    }
}
