//
//  HelpView.swift
//  MIDI Scribe
//

import SwiftUI

struct HelpView: View {
    let onClose: () -> Void

    var body: some View {
        WelcomeSheetFlow(kind: .help, onClose: onClose)
    }
}

#Preview {
    HelpView {}
}
