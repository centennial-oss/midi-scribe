//
//  AboutView.swift
//  MIDI Scribe
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MIDI Scribe"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(appName)
                    .font(.title.weight(.semibold))

                VStack(spacing: 6) {
                    Text("Version \(marketingVersion)")
                    Text("Build \(buildVersion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .font(.body.monospacedDigit())

                Text("Copyright © 2026 Centennial OSS")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("About")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
