//
//  KeyboardPresence.swift
//  Shared
//
//  Lets the containing app tell the user whether the keyboard is actually installed and
//  whether Full Access is on.
//
//  There is no public API to ask "is my keyboard extension enabled?". The common hack
//  reads a private identifier off UITextInputMode via KVC, which is a review risk. This
//  does it the honest way instead: the keyboard writes a heartbeat into the App Group
//  every time it loads, and the app reads it back. If the app can see a heartbeat, the
//  keyboard has run - which means it is installed AND Full Access is on (without Full
//  Access the extension cannot reach the shared container at all).
//

import Foundation

enum KeyboardPresence {

    private enum Key {
        static let lastSeen = "keyboardLastSeenAt"
        static let lastSeenHadFullAccess = "keyboardLastSeenHadFullAccess"
    }

    private static var defaults: UserDefaults { AppConstants.sharedDefaults }

    /// Called from the keyboard extension on load.
    static func recordHeartbeat(hasFullAccess: Bool) {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.lastSeen)
        defaults.set(hasFullAccess, forKey: Key.lastSeenHadFullAccess)
    }

    /// When the keyboard last reported in, if ever.
    static var lastSeen: Date? {
        let stamp = defaults.double(forKey: Key.lastSeen)
        guard stamp > 0 else { return nil }
        return Date(timeIntervalSince1970: stamp)
    }

    /// True once the keyboard has successfully written to the shared container.
    /// This can only happen with Full Access granted, so it doubles as the Full Access
    /// check.
    static var hasEverRunWithFullAccess: Bool {
        lastSeen != nil && defaults.bool(forKey: Key.lastSeenHadFullAccess)
    }

    /// Human-readable status for the Setup screen.
    static var statusDescription: String {
        guard let lastSeen else {
            return "Not detected yet. Add the keyboard, switch to it once, then come back."
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last active \(formatter.localizedString(for: lastSeen, relativeTo: Date()))."
    }
}
