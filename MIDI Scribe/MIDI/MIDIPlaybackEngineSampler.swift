import AudioToolbox
import AVFoundation
import Foundation

extension MIDIPlaybackEngine {
    func rebuildSampler() throws {
        let wasAttached = speakerInstrument.engine === audioEngine
        if wasAttached {
            sendAllNotesOff()
            let previous = speakerInstrument
            catchObjC("audioEngine.disconnect/detach") {
                self.audioEngine.disconnectNodeInput(previous)
                self.audioEngine.disconnectNodeOutput(previous)
                self.audioEngine.detach(previous)
            }
        }
        let soundBankURL = try resolvedSoundBankURL()
        let newInstrument = AVAudioUnitSampler()
        catchObjC("audioEngine.attach/connect") {
            self.audioEngine.attach(newInstrument)
            self.audioEngine.connect(newInstrument, to: self.audioEngine.mainMixerNode, format: nil)
        }
        let program = UInt8(clamping: speakerProgram)
        let bankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let bankLSB = UInt8(kAUSampler_DefaultBankLSB)
        #if DEBUG
        NSLog(
            "[SpeakerProgram] loadSoundBankInstrument " +
                "program=\(program) bankMSB=\(bankMSB) bankLSB=\(bankLSB) url=\(soundBankURL.lastPathComponent)"
        )
        #endif
        do {
            try newInstrument.loadSoundBankInstrument(
                at: soundBankURL,
                program: program,
                bankMSB: bankMSB,
                bankLSB: bankLSB
            )
        } catch {
            // If loading failed, don't leave `newInstrument` attached as a silent /
            // default-patch sampler (which the user perceives as "wrong bank / bank
            // 0"). Detach it and rethrow so the caller knows the rebuild failed.
            catchObjC("audioEngine.detach (failed-load cleanup)") {
                self.audioEngine.disconnectNodeInput(newInstrument)
                self.audioEngine.disconnectNodeOutput(newInstrument)
                self.audioEngine.detach(newInstrument)
            }
            #if DEBUG
            NSLog("[MIDIPlayback] loadSoundBankInstrument failed program=\(program) error=\(error)")
            #endif
            throw error
        }
        // Belt-and-suspenders: explicitly pin the current program on the new sampler.
        // `loadSoundBankInstrument` should have done this, but AUSampler has been
        // observed to reset its program to 0 after engine-configuration changes on
        // recent OSes, so we re-send the program change explicitly.
        pinProgramChange(on: newInstrument, program: program)
        speakerInstrument = newInstrument
    }

    /// Emits an explicit bank-select + program-change sequence on the given sampler
    /// so its current program cannot drift to 0 because of an internal AU reset.
    private func pinProgramChange(on sampler: AVAudioUnitMIDIInstrument, program: UInt8) {
        let bankMSB = UInt8(kAUSampler_DefaultMelodicBankMSB)
        let bankLSB = UInt8(kAUSampler_DefaultBankLSB)
        for channel in 0..<UInt8(16) {
            let controlChangeStatus: UInt8 = 0xB0 | channel
            let programChangeStatus: UInt8 = 0xC0 | channel
            catchObjC("sampler.sendMIDIEvent (pin program)") {
                sampler.sendMIDIEvent(controlChangeStatus, data1: 0, data2: bankMSB) // CC#0  bank MSB
                sampler.sendMIDIEvent(controlChangeStatus, data1: 32, data2: bankLSB) // CC#32 bank LSB
                sampler.sendMIDIEvent(programChangeStatus, data1: program, data2: 0) // program change
            }
        }
    }

    /// Rebuild / restart path used by the normal playback send. Must NOT hold
    /// `samplerLock` when called, because `rebuildSampler()` itself takes it.
    func ensureSpeakerAudioReadyOutsideLock() -> Bool {
        if speakerInstrument.engine !== audioEngine {
            do {
                try rebuildSampler()
            } catch {
                #if DEBUG
                NSLog("[MIDIPlayback] sampler rebuild failed: \(error)")
                #endif
                return false
            }
        }
        if !audioEngine.isRunning {
            var caught: NSError?
            let didSucceed = MSCatchObjCException({
                do {
                    try self.audioEngine.start()
                } catch {
                    #if DEBUG
                    NSLog("[MIDIPlayback] audio start failed: \(error)")
                    #endif
                }
            }, &caught)
            if !didSucceed {
                NSLog(
                    "[MIDIPlayback] caught audioEngine.start exception " +
                        "error=\(caught?.localizedDescription ?? "nil")"
                )
                return false
            }
        }
        return speakerInstrument.engine === audioEngine && audioEngine.isRunning
    }
}
