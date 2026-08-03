//
//  AppConstants.swift
//  Shared between GiftKey (app) and GiftKeyKeyboard (extension)
//
//  SINGLE PLACE TO CHANGE IDENTIFIERS.
//  If you rename the app or change your team, edit the values here AND the
//  matching values in:
//    - project.yml                       (PRODUCT_BUNDLE_IDENTIFIER, DEVELOPMENT_TEAM)
//    - GiftKey/GiftKey.entitlements      (App Group)
//    - GiftKeyKeyboard/GiftKeyKeyboard.entitlements (App Group)
//    - GiftKey/Info.plist                (CFBundleURLSchemes)
//  See README.md > "Renaming / re-signing".
//

import Foundation

enum AppConstants {

    // MARK: - Identifiers

    /// Reverse-DNS prefix owned by your Apple Developer account.
    /// PLACEHOLDER - replace with e.g. "au.com.ryderwear".
    static let bundleIDPrefix = "com.PLACEHOLDER"

    /// Containing app bundle identifier.
    static let appBundleID = "\(bundleIDPrefix).giftkey"

    /// Keyboard extension bundle identifier. Must be prefixed by `appBundleID`.
    static let keyboardBundleID = "\(appBundleID).keyboard"

    /// App Group shared by both targets. Must be registered on the developer portal.
    /// PLACEHOLDER - replace the prefix to match `bundleIDPrefix`.
    static let appGroupID = "group.com.PLACEHOLDER.giftkey"

    // MARK: - URL scheme (Path B handoff)

    static let urlScheme = "giftkey"

    /// Opened by the keyboard to launch the containing app straight into the scanner.
    static var scanURL: URL { URL(string: "\(urlScheme)://scan")! }

    // MARK: - Display

    static let displayName = "GiftKey"

    /// Path the user must follow to grant Full Access. Shown verbatim in-keyboard.
    static let fullAccessPath =
        "Settings > General > Keyboard > Keyboards > \(displayName) > Allow Full Access"

    // MARK: - Shared defaults

    /// Shared UserDefaults suite. Falls back to `.standard` only if the App Group is
    /// misconfigured, so the UI still works during development instead of crashing.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// True when the App Group is actually wired up. Surfaced in the Setup screen.
    static var appGroupIsConfigured: Bool {
        UserDefaults(suiteName: appGroupID) != nil
    }
}
