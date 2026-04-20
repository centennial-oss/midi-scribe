import SwiftUI

extension Font {
    static var takeMetadataLabel: Font {
        #if os(macOS)
        .system(size: 16, weight: .semibold)
        #else
        .headline
        #endif
    }

    static var takeMetadataValue: Font {
        #if os(macOS)
        .system(size: 16)
        #else
        .body
        #endif
    }
}
