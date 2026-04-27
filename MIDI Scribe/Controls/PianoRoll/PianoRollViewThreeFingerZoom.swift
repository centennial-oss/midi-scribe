import SwiftUI

extension PianoRollView {
    private static let threeFingerSwipeZoomSensitivity: CGFloat = 0.0035
    private static let zoomSliderCurveBase: CGFloat = 9.0

    func handleThreeFingerSwipeZoom(deltaX: CGFloat) {
        guard !isLive else { return }
        guard deltaX.isFinite, deltaX != 0 else { return }

        let sliderDelta = deltaX * Self.threeFingerSwipeZoomSensitivity
        let currentSliderValue = sliderValue(forZoomLevel: zoomLevel)
        let nextSliderValue = max(0.0, min(1.0, currentSliderValue + sliderDelta))
        let nextZoom = zoomLevel(forSliderValue: nextSliderValue)
        #if DEBUG
        NSLog(
            "[PianoRollThreeFingerZoom] deltaX=%.4f sliderDelta=%.5f slider=%.5f->%.5f zoom=%.5f->%.5f",
            deltaX,
            sliderDelta,
            currentSliderValue,
            nextSliderValue,
            zoomLevel,
            nextZoom
        )
        #endif
        guard nextZoom != zoomLevel else { return }
        zoomLevel = nextZoom
    }

    func sliderValue(forZoomLevel zoomLevel: CGFloat) -> CGFloat {
        let clampedZoom = max(0.0, min(1.0, zoomLevel))
        let base = Self.zoomSliderCurveBase
        return log(1.0 + (base - 1.0) * clampedZoom) / log(base)
    }

    func zoomLevel(forSliderValue sliderValue: CGFloat) -> CGFloat {
        let clampedSliderValue = max(0.0, min(1.0, sliderValue))
        let base = Self.zoomSliderCurveBase
        return (pow(base, clampedSliderValue) - 1.0) / (base - 1.0)
    }
}
