//
//  ContentView+PhoneNavigation.swift
//  MIDI Scribe
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

extension ContentView {
#if os(iOS)
    var hideTakeActionsToolbarOnPhone: Bool {
        return false
    }
#endif
}
