//
//  CoreMIDIMonitor+Connection.swift
//  MIDI Scribe
//

import CoreMIDI
import Foundation

extension CoreMIDIMonitor {
    func reconnectSources() throws {
        guard inputPort != 0 else { return }

        var availableSources: [MIDIUniqueID: MIDIEndpointRef] = [:]

        for sourceIndex in 0 ..< MIDIGetNumberOfSources() {
            let source = MIDIGetSource(sourceIndex)
            guard source != 0, let uniqueID = uniqueID(for: source) else { continue }
            availableSources[uniqueID] = source

            if connectedSources[uniqueID] == nil {
                let connectionStatus = MIDIPortConnectSource(inputPort, source, nil)
                guard connectionStatus == noErr else {
                    throw CoreMIDIMonitorError.sourceConnection(connectionStatus, sourceIndex: Int(sourceIndex))
                }
                connectedSources[uniqueID] = source
            }
        }

        for (uniqueID, source) in connectedSources where availableSources[uniqueID] == nil {
            MIDIPortDisconnectSource(inputPort, source)
            connectedSources.removeValue(forKey: uniqueID)
        }
    }

    func uniqueID(for object: MIDIObjectRef) -> MIDIUniqueID? {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(object, kMIDIPropertyUniqueID, &value)
        guard status == noErr else { return nil }
        return value
    }

    func cleanupMIDIObjects() {
        connectedSources.removeAll()

        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }

        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }
}
