import SwiftUI

extension Font {
    static var takeMetadataLabel: Font {
        BuildInfo.isMac ? .system(size: 16, weight: .semibold) : .headline
    }

    static var takeMetadataValue: Font {
        BuildInfo.isMac ? .system(size: 16) : .body
    }
}
