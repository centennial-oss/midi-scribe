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

struct OnboardingScreenshotPaneView: View {

    @Environment(\.colorScheme) private var colorScheme

    let content: OnboardingScreenshotContent

    // Measured rendered sizes for each annotation, keyed by annotation ID.
    // Starts empty so tooltips are initially invisible; populated after the
    // first layout pass and used to compute caret-tip → center offsets.
    @State private var tooltipSizes: [String: CGSize] = [:]

    #if DEBUG
    @State private var isShowingDebugUndimmedZones = false
    #endif

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
                    let knownSize = tooltipSizes[annotation.id]
                    OnboardingTooltipView(
                        label: annotation.label,
                        caretPosition: annotation.caretPosition,
                        avoidsLineWrapping: annotation.avoidsLineWrapping
                    )
                    .frame(
                        maxWidth: annotation.avoidsLineWrapping ? nil : tooltipWidth(for: containerSize),
                        alignment: tooltipFrameAlignment(for: annotation.caretPosition)
                    )
                    // Measure the rendered tooltip size on the first (invisible) pass.
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: TooltipSizePreferenceKey.self,
                                    value: [annotation.id: geo.size]
                                )
                        }
                    )
                    // Stay invisible until we have a real measurement so there
                    // is no flash of a mis-positioned tooltip.
                    .opacity(knownSize != nil ? 1 : 0)
                    .animation(.easeIn(duration: 0.12), value: knownSize != nil)
                    .position(
                        annotationPosition(
                            annotation,
                            tooltipSize: knownSize ?? .zero,
                            imageRect: imageRect,
                            originalSize: originalSize
                        )
                    )
                }
                #if DEBUG
                if isShowingDebugUndimmedZones {
                    DebugUndimmedZoneOverlay(
                        imageRect: imageRect,
                        originalSize: originalSize,
                        zones: content.undimmedZones
                    )
                }
                #endif
            }
            .onPreferenceChange(TooltipSizePreferenceKey.self) { sizes in
                for (id, size) in sizes where tooltipSizes[id] != size {
                    tooltipSizes[id] = size
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        Color.secondary,
                        style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                    )
            }
            #if DEBUG
            .modifier(
                OnboardingImageClickLogger(
                    assetName: content.assetName,
                    imageRect: imageRect,
                    originalSize: originalSize
                )
            )
            .overlay {
                DebugUndimmedZoneGestureOverlay(isActive: $isShowingDebugUndimmedZones)
            }
            #endif
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
        tooltipSize: CGSize,
        imageRect: CGRect,
        originalSize: CGSize
    ) -> CGPoint {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return CGPoint(x: imageRect.midX, y: imageRect.midY)
        }

        // Convert the caret-tip coordinate from image-space to container-space.
        let tipX = imageRect.minX + (annotation.sourceX / originalSize.width) * imageRect.width
        let tipY = imageRect.minY + (annotation.sourceY / originalSize.height) * imageRect.height

        // .position() sets the *center* of the view, so offset from the tip
        // to the center based on which edge the caret is on.
        switch annotation.caretPosition {
        case .none:
            // Centered on the tip.
            return CGPoint(x: tipX, y: tipY)
        case .top:
            // Tip is at top-center; bubble body hangs below.
            return CGPoint(x: tipX, y: tipY + tooltipSize.height / 2)
        case .bottom:
            // Tip is at bottom-center; bubble body sits above.
            return CGPoint(x: tipX, y: tipY - tooltipSize.height / 2)
        case .left:
            // Tip is at left-midY; bubble body extends to the right.
            return CGPoint(x: tipX + tooltipSize.width / 2, y: tipY)
        case .right:
            // Tip is at right-midY; bubble body extends to the left.
            return CGPoint(x: tipX - tooltipSize.width / 2, y: tipY)
        }
    }

    private func tooltipFrameAlignment(for caretPosition: OnboardingCaretPosition) -> Alignment {
        switch caretPosition {
        case .left: return .leading
        case .right: return .trailing
        case .top, .bottom, .none: return .center
        }
    }

    private func tooltipWidth(for containerSize: CGSize) -> CGFloat {
        min(max(containerSize.width * 0.28, 190), 300)
    }
}

struct DimOverlayWithCutouts: View {
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
                with: .color(.black.opacity(0.55)),
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

struct OnboardingScreenshotImage: View {
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
