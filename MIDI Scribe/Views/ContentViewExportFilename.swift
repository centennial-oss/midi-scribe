//
//  ContentView+ExportFilename.swift
//  MIDI Scribe
//

import Foundation

extension ContentView {
    func suggestedExportFilename(from takeName: String) -> String {
        let lowercasedName = takeName.lowercased()
        if lowercasedName.hasSuffix(".mid") || lowercasedName.hasSuffix(".midi") {
            return takeName
        }
        return "\(takeName).mid"
    }
}
