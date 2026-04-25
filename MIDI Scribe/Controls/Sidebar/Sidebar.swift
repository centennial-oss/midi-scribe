//
//  SidebarOverlayContainer.swift
//  TestSplitView
//
//  Created by James Ranson on 4/22/26.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
import Combine

/// `Environment(\.controlActiveState)` can miss updates (e.g. app launched
/// while backgrounded). This follows `NSApplication.shared.isActive`
/// via notifications.
final class MacApplicationIsActiveState: ObservableObject {
    static let shared = MacApplicationIsActiveState()

    @Published private(set) var isActive: Bool

    private var cancellables = Set<AnyCancellable>()

    private init() {
        isActive = NSApplication.shared.isActive
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let next = NSApplication.shared.isActive
                if next != self.isActive {
                    self.isActive = next
                }
            }
            .store(in: &cancellables)
    }
}
#endif

private struct SidebarUsesCustomLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarUsesCustomLayout: Bool {
        get { self[SidebarUsesCustomLayoutKey.self] }
        set { self[SidebarUsesCustomLayoutKey.self] = newValue }
    }
}

struct SidebarMultiSelectContext {
    let isEnabled: Bool
    let isValueSelected: (AnyHashable) -> Bool
    let isValueDisabled: (AnyHashable) -> Bool
    let toggleValue: (AnyHashable) -> Void
}

private struct SidebarMultiSelectContextKey: EnvironmentKey {
    static let defaultValue = SidebarMultiSelectContext(
        isEnabled: false,
        isValueSelected: { _ in false },
        isValueDisabled: { _ in false },
        toggleValue: { _ in }
    )
}

extension EnvironmentValues {
    var sidebarMultiSelectContext: SidebarMultiSelectContext {
        get { self[SidebarMultiSelectContextKey.self] }
        set { self[SidebarMultiSelectContextKey.self] = newValue }
    }
}

/// Invoked from `SidebarItem` after a row tap that changes the detail
/// selection (default no-op; split layout injects iPhone collapse).
private struct SidebarAfterDetailChangeRowActionKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var sidebarAfterDetailChangeRowAction: () -> Void {
        get { self[SidebarAfterDetailChangeRowActionKey.self] }
        set { self[SidebarAfterDetailChangeRowActionKey.self] = newValue }
    }
}

struct SidebarListHeader {
    let title: String
    let buttons: [SidebarButton]

    init(title: String, buttons: [SidebarButton] = []) {
        self.title = title
        self.buttons = buttons
    }
}

struct Sidebar<SidebarContent: View, DetailContent: View, UnderlayContent: View>: View {
    private let defaultSidebarWidth = SidebarLayoutDefaults.defaultSidebarWidth
    private let customSidebarTopInsetNoCustomButtons: CGFloat = 8
    /// Custom-overlay-only chrome toggle. When true, hides the custom
    /// sidebar's built-in show/hide buttons (open-row button and floating
    /// closed-state button).
    let excludesCustomSidebarToggleButtons: Bool
    let forceCustomSidebar: Bool?
    @Binding var isPresented: Bool
    @ViewBuilder let sidebar: () -> SidebarContent
    @ViewBuilder let detail: () -> DetailContent
    @ViewBuilder let underSidebarOverlay: () -> UnderlayContent
    @Environment(\.colorScheme) private var colorScheme
    @State private var splitViewColumnVisibility: NavigationSplitViewVisibility = .automatic
    /// On compact width (e.g. iPhone portrait), `columnVisibility` is ignored; this drives which column is on top.
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    #if os(iOS)
    @State var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    #endif

    init(
        isPresented: Binding<Bool>,
        excludesCustomSidebarToggleButtons: Bool = false,
        forceCustomSidebar: Bool? = nil,
        @ViewBuilder sidebar: @escaping () -> SidebarContent,
        @ViewBuilder detail: @escaping () -> DetailContent,
        @ViewBuilder underSidebarOverlay: @escaping () -> UnderlayContent
    ) {
        self._isPresented = isPresented
        self.excludesCustomSidebarToggleButtons = excludesCustomSidebarToggleButtons
        self.forceCustomSidebar = forceCustomSidebar
        self.sidebar = sidebar
        self.detail = detail
        self.underSidebarOverlay = underSidebarOverlay
    }

    var body: some View {
        #if os(iOS)
        Group {
            if shouldUseCustomSidebar {
                customOverlayLayout
            } else {
                regularSplitLayout
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateOrientation(UIDevice.current.orientation)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateOrientation(UIDevice.current.orientation)
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        #else
        regularSplitLayout
        #endif
    }

    private var customOverlayLayout: some View {
        ZStack(alignment: .topLeading) {
            detail()
                .zIndex(0)

            if isPresented {
                Color.black.opacity(0.68)
                    .ignoresSafeArea()
                    .onTapGesture {
                        toggleSidebar()
                    }
                    .transition(.opacity)
                    .zIndex(1)
            }

            underSidebarOverlay()
                .zIndex(1.5)

            ZStack(alignment: .topLeading) {
                #if os(iOS)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(customOverlaySidebarPanelFill)
                    .frame(width: defaultSidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                #endif
                VStack(alignment: .trailing, spacing: 0) {
                    if !excludesCustomSidebarToggleButtons {
                        Button {
                            toggleSidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.title3)
                                .foregroundColor(.primary)
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    ScrollView {
                        sidebar()
                            .environment(\.sidebarUsesCustomLayout, true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    #if os(iOS)
                    .scrollContentBackground(.hidden)
                    #endif
                    .frame(width: defaultSidebarWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.top, excludesCustomSidebarToggleButtons ? customSidebarTopInsetNoCustomButtons : 0)
                .frame(width: defaultSidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: defaultSidebarWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 22, x: 0, y: 10)
            .padding(.leading, 0)
            .padding(.top, 8)
            .padding(.bottom, -16)
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: isPresented ? 0 : -(defaultSidebarWidth + 100))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
            .zIndex(2)

            if !isPresented && !excludesCustomSidebarToggleButtons {
                Button {
                    toggleSidebar()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .padding(10)
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .padding(.leading, -30)
                .padding(.top, 24)
                .zIndex(3)
            }
        }
    }

    private var regularSplitLayout: some View {
        NavigationSplitView(
            columnVisibility: $splitViewColumnVisibility,
            preferredCompactColumn: $preferredCompactColumn
        ) {
            #if os(iOS)
            Group {
                if isPhone {
                    ZStack(alignment: .top) {
                        Color(uiColor: .systemBackground)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea(edges: .vertical)
                        ScrollView {
                            sidebar()
                                .environment(\.sidebarUsesCustomLayout, false)
                                .environment(
                                    \.sidebarAfterDetailChangeRowAction,
                                    collapseSplitViewSidebarForDetailChange
                                )
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        sidebar()
                            .environment(\.sidebarUsesCustomLayout, false)
                            .environment(\.sidebarAfterDetailChangeRowAction, collapseSplitViewSidebarForDetailChange)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .navigationSplitViewColumnWidth(
                min: defaultSidebarWidth,
                ideal: defaultSidebarWidth,
                max: defaultSidebarWidth
            )
            #else
            ScrollView {
                sidebar()
                    .environment(\.sidebarUsesCustomLayout, false)
                    .environment(\.sidebarAfterDetailChangeRowAction, collapseSplitViewSidebarForDetailChange)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: defaultSidebarWidth)
            #endif
        } detail: {
            detail()
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func collapseSplitViewSidebarForDetailChange() {
        #if os(iOS)
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }
        withAnimation {
            preferredCompactColumn = .detail
        }
        #endif
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isPresented.toggle()
        }
    }

    #if os(iOS)
    /// Custom landscape overlay only: dark mode uses an elevated gray so the
    /// panel reads against a black detail canvas; light mode matches the sheet.
    private var customOverlaySidebarPanelFill: Color {
        colorScheme == .dark
            ? Color(red: 0.08, green: 0.08, blue: 0.08)
            : Color(red: 0.99, green: 0.99, blue: 0.99)
    }

    var shouldUseCustomSidebar: Bool {
        if let forceCustomSidebar {
            return forceCustomSidebar
        }
        return UIDevice.current.userInterfaceIdiom == .phone && deviceOrientation.isLandscape
    }

    private func updateOrientation(_ orientation: UIDeviceOrientation) {
        guard orientation.isPortrait || orientation.isLandscape else {
            return
        }
        deviceOrientation = orientation
        if !shouldUseCustomSidebar {
            isPresented = false
        }
    }
    #endif
}

extension Sidebar where UnderlayContent == EmptyView {
    init(
        isPresented: Binding<Bool>,
        excludesCustomSidebarToggleButtons: Bool = false,
        forceCustomSidebar: Bool? = nil,
        @ViewBuilder sidebar: @escaping () -> SidebarContent,
        @ViewBuilder detail: @escaping () -> DetailContent
    ) {
        self.init(
            isPresented: isPresented,
            excludesCustomSidebarToggleButtons: excludesCustomSidebarToggleButtons,
            forceCustomSidebar: forceCustomSidebar,
            sidebar: sidebar,
            detail: detail,
            underSidebarOverlay: { EmptyView() }
        )
    }
}
