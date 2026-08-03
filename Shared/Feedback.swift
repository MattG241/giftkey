//
//  Feedback.swift
//  Shared
//
//  Haptic and audio feedback for scan success / rejection.
//
//  Keyboard extension notes:
//    - UIFeedbackGenerator only fires from a keyboard extension when Full Access is on.
//      We attempt it regardless; iOS silently no-ops otherwise, which is fine.
//    - `UIDevice.current.playInputClick()` is the sanctioned key-click sound for
//      keyboards and respects the user's system keyboard-click setting. It is used for
//      the key buttons; the scan beep is a distinct system sound so staff can hear a
//      successful capture over a busy shop floor.
//

import AudioToolbox
import UIKit

enum Feedback {

    // Generators are created on demand and released immediately - holding them alive
    // in a keyboard extension is wasted memory.

    /// Successful decode: crisp tick plus an optional beep.
    static func success(beep: Bool, haptic: Bool) {
        if haptic {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.success)
        }
        if beep {
            // 1057 - "Tink". Short, cuts through ambient retail noise, not alarming.
            AudioServicesPlaySystemSound(1057)
        }
    }

    /// Rejected by the validation filter.
    static func rejection(beep: Bool, haptic: Bool) {
        if haptic {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        if beep {
            // 1053 - lower, clearly different from the success tone.
            AudioServicesPlaySystemSound(1053)
        }
    }

    /// Light tap for ordinary button presses inside the keyboard.
    static func keyTap() {
        UIDevice.current.playInputClick()
    }

    /// Light impact used when the scanner opens/closes.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
