//
//  WelcomeScreenshotCarousel.swift
//  MIDI Scribe
//

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct OnboardingSwipeCarouselView: View {
    let panes: [OnboardingPane]
    @Binding var selection: Int

    var body: some View {
        ZStack {
            if panes.indices.contains(selection) {
                OnboardingPaneView(
                    pane: panes[selection],
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

private struct OnboardingScreenshotPaneView: View {
    let content: OnboardingScreenshotContent

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let originalSize = content.originalSize
            let imageRect = renderedImageRect(
                containerSize: containerSize,
                originalSize: originalSize
            )

            ZStack {
                OnboardingScreenshotImage(
                    assetName: content.assetName,
                    originalSize: originalSize
                )
                .frame(width: containerSize.width, height: containerSize.height)

                if !content.undimmedZones.isEmpty {
                    DimOverlayWithCutouts(
                        imageRect: imageRect,
                        originalSize: originalSize,
                        zones: content.undimmedZones
                    )
                }

                ForEach(content.annotations) { annotation in
                    OnboardingTooltipView(
                        label: annotation.label,
                        caretPosition: annotation.caretPosition
                    )
                    .frame(maxWidth: tooltipWidth(for: containerSize))
                    .position(
                        annotationPosition(
                            annotation,
                            imageRect: imageRect,
                            originalSize: originalSize
                        )
                    )
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [2, 2])
                    )
            }
        }
    }

    private func renderedImageRect(containerSize: CGSize, originalSize: CGSize) -> CGRect {
        guard originalSize.width > 0,
              originalSize.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else {
            return CGRect(origin: .zero, size: containerSize)
        }

        let scale = max(
            containerSize.width / originalSize.width,
            containerSize.height / originalSize.height
        )
        let renderedSize = CGSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        return CGRect(
            x: (containerSize.width - renderedSize.width) / 2,
            y: (containerSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    private func annotationPosition(
        _ annotation: OnboardingAnnotation,
        imageRect: CGRect,
        originalSize: CGSize
    ) -> CGPoint {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return CGPoint(x: imageRect.midX, y: imageRect.midY)
        }

        return CGPoint(
            x: imageRect.minX + (annotation.sourceX / originalSize.width) * imageRect.width,
            y: imageRect.minY + (annotation.sourceY / originalSize.height) * imageRect.height
        )
    }

    private func tooltipWidth(for containerSize: CGSize) -> CGFloat {
        min(max(containerSize.width * 0.28, 190), 300)
    }
}

private struct DimOverlayWithCutouts: View {
    let imageRect: CGRect
    let originalSize: CGSize
    let zones: [OnboardingUndimmedZone]

    var body: some View {
        Canvas { context, size in
            var maskPath = Path(CGRect(origin: .zero, size: size))
            for zone in zones {
                maskPath.addPath(renderedZonePath(for: zone))
            }
            context.fill(
                maskPath,
                with: .color(.black.opacity(0.45)),
                style: FillStyle(eoFill: true)
            )
        }
        .allowsHitTesting(false)
    }

    private func renderedZonePath(for zone: OnboardingUndimmedZone) -> Path {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return Path()
        }
        let scaleX = imageRect.width / originalSize.width
        let scaleY = imageRect.height / originalSize.height

        switch zone {
        case let .roundedRect(centerX, centerY, width, height, cornerRadius):
            let rect = CGRect(
                x: imageRect.minX + (centerX * scaleX) - ((width * scaleX) / 2),
                y: imageRect.minY + (centerY * scaleY) - ((height * scaleY) / 2),
                width: width * scaleX,
                height: height * scaleY
            )
            return RoundedRectangle(
                cornerRadius: cornerRadius * min(scaleX, scaleY),
                style: .continuous
            )
            .path(in: rect)
        case let .circle(centerX, centerY, diameter):
            let renderedDiameter = diameter * min(scaleX, scaleY)
            let rect = CGRect(
                x: imageRect.minX + (centerX * scaleX) - (renderedDiameter / 2),
                y: imageRect.minY + (centerY * scaleY) - (renderedDiameter / 2),
                width: renderedDiameter,
                height: renderedDiameter
            )
            return Path(ellipseIn: rect)
        }
    }
}

private struct OnboardingScreenshotImage: View {
    let assetName: String
    let originalSize: CGSize

    private var aspectRatio: CGFloat {
        guard originalSize.height > 0 else { return 16 / 9 }
        return originalSize.width / originalSize.height
    }

    var body: some View {
        Group {
            if let platformImage = platformImage(named: assetName) {
                #if os(macOS)
                Image(nsImage: platformImage)
                    .resizable()
                #else
                Image(uiImage: platformImage)
                    .resizable()
                #endif
            } else {
                missingImagePlaceholder
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fill)
        .clipped()
    }

    @ViewBuilder
    private var missingImagePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.22),
                    Color.secondary.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 42, weight: .semibold))
                Text(assetName)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .foregroundStyle(.secondary)
            .padding(20)
        }
    }

    #if os(macOS)
    private func platformImage(named name: String) -> NSImage? {
        NSImage(named: NSImage.Name(name))
    }
    #else
    private func platformImage(named name: String) -> UIImage? {
        UIImage(named: name)
    }
    #endif
}

private struct OnboardingTooltipView: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let caretPosition: OnboardingCaretPosition

    var body: some View {
        Text(label)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
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

    private var horizontalPadding: CGFloat {
        switch caretPosition {
        case .left, .right:
            return 18
        case .top, .bottom, .none:
            return 14
        }
    }

    private var verticalPadding: CGFloat {
        switch caretPosition {
        case .top, .bottom:
            return 18
        case .left, .right, .none:
            return 12
        }
    }

    private var tooltipFill: AnyShapeStyle {
        colorScheme == .light ? AnyShapeStyle(Color.white) : AnyShapeStyle(.regularMaterial)
    }
}
