import SwiftUI

enum SidebarLayoutDefaults {
    #if os(iOS)
    static let defaultSidebarWidth: CGFloat = 340
    #else
    static let defaultSidebarWidth: CGFloat = 300
    #endif
}
