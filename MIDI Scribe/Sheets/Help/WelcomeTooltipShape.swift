//
//  WelcomeTooltipShape.swift
//  MIDI Scribe
//

import SwiftUI

struct OnboardingTooltipShape: InsettableShape {
    let caretPosition: OnboardingCaretPosition
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let sourceRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let bubbleRect = bubbleRect(in: sourceRect)
        let radius: CGFloat = 12
        let caretWidth: CGFloat = 18
        var path = Path()

        path.move(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY))
        addTopCaret(to: &path, sourceRect: sourceRect, bubbleRect: bubbleRect, width: caretWidth)
        path.addLine(to: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.minY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY + radius),
            control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.minY)
        )
        addRightCaret(to: &path, sourceRect: sourceRect, bubbleRect: bubbleRect, width: caretWidth)
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.maxX - radius, y: bubbleRect.maxY),
            control: CGPoint(x: bubbleRect.maxX, y: bubbleRect.maxY)
        )
        addBottomCaret(to: &path, sourceRect: sourceRect, bubbleRect: bubbleRect, width: caretWidth)
        path.addLine(to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY - radius),
            control: CGPoint(x: bubbleRect.minX, y: bubbleRect.maxY)
        )
        addLeftCaret(to: &path, sourceRect: sourceRect, bubbleRect: bubbleRect, width: caretWidth)
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: bubbleRect.minX + radius, y: bubbleRect.minY),
            control: CGPoint(x: bubbleRect.minX, y: bubbleRect.minY)
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    private func bubbleRect(in rect: CGRect) -> CGRect {
        let depth: CGFloat = 10
        switch caretPosition {
        case .top:
            return CGRect(x: rect.minX, y: rect.minY + depth, width: rect.width, height: rect.height - depth)
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - depth)
        case .left:
            return CGRect(x: rect.minX + depth, y: rect.minY, width: rect.width - depth, height: rect.height)
        case .right:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width - depth, height: rect.height)
        }
    }

    private func addTopCaret(to path: inout Path, sourceRect: CGRect, bubbleRect: CGRect, width: CGFloat) {
        guard case .top = caretPosition else { return }
        path.addLine(to: CGPoint(x: bubbleRect.midX - width / 2, y: bubbleRect.minY))
        path.addLine(to: CGPoint(x: bubbleRect.midX, y: sourceRect.minY))
        path.addLine(to: CGPoint(x: bubbleRect.midX + width / 2, y: bubbleRect.minY))
    }

    private func addRightCaret(to path: inout Path, sourceRect: CGRect, bubbleRect: CGRect, width: CGFloat) {
        guard case .right = caretPosition else { return }
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.midY - width / 2))
        path.addLine(to: CGPoint(x: sourceRect.maxX, y: bubbleRect.midY))
        path.addLine(to: CGPoint(x: bubbleRect.maxX, y: bubbleRect.midY + width / 2))
    }

    private func addBottomCaret(to path: inout Path, sourceRect: CGRect, bubbleRect: CGRect, width: CGFloat) {
        guard case .bottom = caretPosition else { return }
        path.addLine(to: CGPoint(x: bubbleRect.midX + width / 2, y: bubbleRect.maxY))
        path.addLine(to: CGPoint(x: bubbleRect.midX, y: sourceRect.maxY))
        path.addLine(to: CGPoint(x: bubbleRect.midX - width / 2, y: bubbleRect.maxY))
    }

    private func addLeftCaret(to path: inout Path, sourceRect: CGRect, bubbleRect: CGRect, width: CGFloat) {
        guard case .left = caretPosition else { return }
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.midY + width / 2))
        path.addLine(to: CGPoint(x: sourceRect.minX, y: bubbleRect.midY))
        path.addLine(to: CGPoint(x: bubbleRect.minX, y: bubbleRect.midY - width / 2))
    }
}
