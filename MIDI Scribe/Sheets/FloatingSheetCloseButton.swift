//
//  FloatingSheetCloseButton.swift
//  MIDI Scribe
//

import SwiftUI

#if os(iOS)
struct FloatingSheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 44, height: 44)

                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.primary)
                    .padding(10)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}
#endif
