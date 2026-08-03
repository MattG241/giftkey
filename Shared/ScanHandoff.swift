//
//  ScanHandoff.swift
//  Shared
//
//  Path B plumbing: the containing app scans, drops the result in the App Group, and
//  the keyboard picks it up when it next becomes active.
//
//  The payload is deliberately tiny and short-lived. It is written to shared
//  UserDefaults, expires after 60 seconds, and is cleared the moment the keyboard
//  consumes it. Nothing is ever persisted beyond that window and nothing leaves the
//  device.
//

import Foundation

struct ScanHandoff: Codable, Equatable {

    /// Raw decoded string, before post-processing. Processing happens in the keyboard so
    /// a settings change between scanning and inserting is honoured.
    let raw: String
    /// Symbology raw value, if the scanner reported one.
    let symbologyRawValue: String?
    /// When the scan happened.
    let timestamp: Date

    var symbology: BarcodeSymbology? {
        symbologyRawValue.flatMap(BarcodeSymbology.init(rawValue:))
    }

    /// Handoffs older than this are ignored, so a stale scan from an hour ago can never
    /// surprise a cashier by typing itself into the next field they touch.
    static let expiry: TimeInterval = 60

    var isFresh: Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age >= 0 && age <= ScanHandoff.expiry
    }
}

enum ScanHandoffStore {

    private static let key = "pendingScanHandoff"

    private static var defaults: UserDefaults { AppConstants.sharedDefaults }

    /// Called by the containing app after a successful in-app scan.
    static func write(raw: String, symbology: BarcodeSymbology?) {
        let handoff = ScanHandoff(raw: raw,
                                  symbologyRawValue: symbology?.rawValue,
                                  timestamp: Date())
        guard let data = try? JSONEncoder().encode(handoff) else { return }
        defaults.set(data, forKey: key)
    }

    /// Called by the keyboard when it becomes active. Returns a fresh handoff exactly
    /// once - it is cleared whether or not it was still fresh.
    static func consume() -> ScanHandoff? {
        guard let data = defaults.data(forKey: key) else { return nil }
        clear()
        guard let handoff = try? JSONDecoder().decode(ScanHandoff.self, from: data),
              handoff.isFresh else { return nil }
        return handoff
    }

    /// Non-destructive check, used by the app to show "switch back to your keyboard".
    static func peek() -> ScanHandoff? {
        guard let data = defaults.data(forKey: key),
              let handoff = try? JSONDecoder().decode(ScanHandoff.self, from: data),
              handoff.isFresh else { return nil }
        return handoff
    }

    static func clear() {
        defaults.removeObject(forKey: key)
    }
}
