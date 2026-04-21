//
//  MIDILiveNoteViewModelSettings.swift
//  MIDI Scribe
//

import Combine

extension MIDILiveNoteViewModel {
    func wirePlaybackAndSettings() {
        playbackEngineCancellable = playbackEngine.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        settings.$disableScribing
            .removeDuplicates()
            .sink { [weak self] disableScribing in
                self?.handleScribingEnabledChanged(isEnabled: !disableScribing)
            }
            .store(in: &settingsCancellables)

        settings.$selectedPlaybackTarget
            .removeDuplicates()
            .sink { [weak self] target in
                guard let self, self.selectedPlaybackTarget != target else { return }
                self.selectedPlaybackTarget = target
            }
            .store(in: &settingsCancellables)
    }
}
