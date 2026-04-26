//
//  AboutView.swift
//  MIDI Scribe
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct AboutView: View {
    let onClose: () -> Void

    private let appStoreReviewURL = URL(
        string: "https://apps.apple.com/us/app/\(AppIdentifier.nameSlug)/" +
            "id\(AppIdentifier.appleStoreID)?action=write-review"
    )!

    @State private var isGitHubLinkHovered = false
    @State private var isAppStoreLinkHovered = false
    @State private var didCopyBuildInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    Label(
                        "\(AppIdentifier.name) is a utility for automatically capturing and organizing practice " +
                        "Takes with your MIDI-capable musical instrument.",
                        systemImage: "music.note.tv"
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        "External MIDI-capable musical instrument is required.",
                        systemImage: "exclamationmark.triangle"
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        "\(AppIdentifier.name) is 100% private. " +
                            "It does not collect analytics or snoop on your usage. " +
                            "Nothing ever leaves your device. Period.",
                        systemImage: "shield"
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("This software is completely free and open source for you to enjoy.",
                        systemImage: "heart"
                    )
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Link(destination: appStoreReviewURL) {
                        Label("Rate \(AppIdentifier.name) on the App Store",
                        systemImage: "star.leadinghalf.filled"
                    )
                            .foregroundStyle(linkColor)
                            .underline(isAppStoreLinkHovered, color: linkColor.opacity(0.8))
                    }
                    .font(.system(size: 14))
                    #if os(macOS)
                    .onHover { isAppStoreLinkHovered = $0 }
                    #endif

                    Link(destination: AppIdentifier.repoURL) {
                        Label("GitHub: \(AppIdentifier.repoPath)",
                        systemImage: "arrow.up.right.square"
                    )
                            .foregroundStyle(linkColor)
                            .underline(isGitHubLinkHovered, color: linkColor.opacity(0.8))
                    }
                    .font(.system(size: 15))
                    #if os(macOS)
                    .onHover { isGitHubLinkHovered = $0 }
                    #endif

                    buildInfoSection

                    Text(
                        "\(AppIdentifier.name) and the \(AppIdentifier.name) logo are trademarks of " +
                            "\(AppIdentifier.copyrightHolder)\nAll rights reserved."
                    )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    BasicButton(
                        context: BasicButtonContext(
                            action: onClose,
                            label: "Close",
                            keyboardShortcut: .defaultAction
                        )
                    )
                }
            }
        }
        .frame(width: 560)
        #if os(macOS)
        .background(AboutEscapeKeyHandler(onEscape: onClose))
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            AppIconImage()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(AppIdentifier.nameTM)
                        .font(.system(size: 30, weight: .semibold))

                    Text("v" + BuildInfo.version)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Text(AppIdentifier.copyright)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buildInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Build info (copy for support)", systemImage: "doc.text")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Text(BuildInfo.copyableBlob)
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
                Spacer()
                BasicButton(
                    context: BasicButtonContext(
                        action: copyBuildInfo,
                        label: didCopyBuildInfo ? "✓ Copied" : "Copy",
                    )
                )
                .padding(.top, 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var linkColor: Color {
        #if os(macOS)
        Color(nsColor: .linkColor)
        #else
        Color(uiColor: .link)
        #endif
    }

    private func copyBuildInfo() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(BuildInfo.copyableBlob, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = BuildInfo.copyableBlob
        #endif
        didCopyBuildInfo = true
    }
}

#Preview {
    AboutView {}
}

#if os(macOS)
private struct AboutEscapeKeyHandler: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EscapeMonitorView {
        let view = EscapeMonitorView()
        view.onEscape = onEscape
        view.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: EscapeMonitorView, context: Context) {
        nsView.onEscape = onEscape
    }

    static func dismantleNSView(_ nsView: EscapeMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class EscapeMonitorView: NSView {
    var onEscape: (() -> Void)?
    private var monitor: Any?

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onEscape?()
            return nil
        }
    }

    func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}
#endif
