//
//  ValidationPreset.swift
//  Shared
//
//  A validation preset is a named regular expression the *final* processed code must
//  match in full. If it does not match, the scan is rejected: nothing is typed, the
//  keyboard shakes, and an error haptic fires. This is the guardrail that stops a
//  product barcode landing in a gift card field.
//
//  ADDING A PRESET
//  ---------------
//  1. Add a `static let` below following the pattern of `giftCard`.
//  2. Add it to `ValidationPreset.all`.
//  That is the whole job - SettingsView renders `all` automatically and the pipeline
//  resolves by `id`, so nothing else needs to change. Keep `id` stable forever; it is
//  what gets persisted in shared UserDefaults.
//

import Foundation

struct ValidationPreset: Identifiable, Hashable {

    /// Stable identifier persisted in UserDefaults. Never change an existing value.
    let id: String
    /// Shown in the settings picker.
    let name: String
    /// One-line explanation shown under the picker.
    let detail: String
    /// ICU regular expression. Empty string means "no validation".
    let pattern: String

    // MARK: - Built-in presets

    static let off = ValidationPreset(
        id: "off",
        name: "Off",
        detail: "Insert whatever scans. No filtering.",
        pattern: ""
    )

    /// The reason this app exists: Shopify POS "Enter manually" gift card fields.
    static let giftCard = ValidationPreset(
        id: "giftcard-8-20",
        name: "Gift card (8-20 digits)",
        detail: "Only digits, 8 to 20 of them. Blocks product barcodes and QR payloads.",
        pattern: "^[0-9]{8,20}$"
    )

    static let numericAny = ValidationPreset(
        id: "numeric-any",
        name: "Digits only",
        detail: "Any length, digits only.",
        pattern: "^[0-9]+$"
    )

    static let custom = ValidationPreset(
        id: "custom",
        name: "Custom regex",
        detail: "Your own pattern. The whole code must match.",
        pattern: ""
    )

    /// Everything shown in the settings picker, in order.
    static let all: [ValidationPreset] = [off, giftCard, numericAny, custom]

    static func preset(withID id: String) -> ValidationPreset {
        all.first { $0.id == id } ?? off
    }

    /// True when this preset actually filters anything.
    var isActive: Bool {
        !pattern.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
