//
//  ScanHandoff.swift
//  Shared
//
//  How a scan gets from the app to the keyboard.
//
//  iOS does not permit a keyboard extension to use the camera - confirmed by Apple:
//  "the camera is still not available to keyboard extensions. The only extension you can
//  use the camera from is an iMessage Extension."
//  (https://developer.apple.com/forums/thread/681975)
//
//  So the keyboard opens the containing app, the app scans, and the result comes back
//  through the App Group. This is the same approach every camera-based keyboard wedge on
//  iOS uses; there is no alternative.
//
//  The payload is deliberately tiny and short-lived: written to shared UserDefaults,
//  expires after 60 seconds, and cleared the moment the keyboard consumes it. Nothing is
//  persisted beyond that window and nothing leaves the device.
//

import Foundation

struct ScanHandoff: Codable, Equatable {

    /// One scanned code, before post-processing. Processing happens in the keyboard so a
    /// settings change between scanning and inserting is honoured.
    struct Item: Codable, Equatable {
        let raw: String
        let symbologyRawValue: String?

        var symbology: BarcodeSymbology? {
            symbologyRawValue.flatMap(BarcodeSymbology.init(rawValue:))
        }
    }

    /// Usually one. More than one when the user scanned a batch in the app.
    let items: [Item]
    let timestamp: Date

    /// Handoffs older than this are ignored, so a stale scan can never surprise a
    /// cashier by typing itself into the next field they touch.
    static let expiry: TimeInterval = 60

    var isFresh: Bool {
        let age = Date().timeIntervalSince(timestamp)
        return age >= 0 && age <= ScanHandoff.expiry
    }
}

enum ScanHandoffStore {

    private static let key = "pendingScanHandoff"

    private static var defaults: UserDefaults { AppConstants.sharedDefaults }

    /// Replaces any pending handoff with a single code.
    static func write(raw: String, symbology: BarcodeSymbology?) {
        write(items: [ScanHandoff.Item(raw: raw, symbologyRawValue: symbology?.rawValue)])
    }

    /// Adds a code to the pending handoff, for batch scanning in the app.
    /// Starts a fresh handoff if the existing one has expired.
    static func append(raw: String, symbology: BarcodeSymbology?) {
        let item = ScanHandoff.Item(raw: raw, symbologyRawValue: symbology?.rawValue)
        var items = peek()?.items ?? []
        items.append(item)
        write(items: items)
    }

    private static func write(items: [ScanHandoff.Item]) {
        let handoff = ScanHandoff(items: items, timestamp: Date())
        guard let data = try? JSONEncoder().encode(handoff) else { return }
        defaults.set(data, forKey: key)
    }

    /// Called by the keyboard when it becomes active. Returns a fresh handoff exactly
    /// once - it is cleared whether or not it was still fresh.
    static func consume() -> ScanHandoff? {
        guard let data = defaults.data(forKey: key) else { return nil }
        clear()
        guard let handoff = try? JSONDecoder().decode(ScanHandoff.self, from: data),
              handoff.isFresh,
              !handoff.items.isEmpty else { return nil }
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
