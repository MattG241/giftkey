//
//  Settings.swift
//  Shared
//
//  All user settings live in the App Group's shared UserDefaults so the keyboard
//  extension and the containing app see exactly the same values.
//
//  Nothing here ever leaves the device. There is no networking code in either target.
//

import AVFoundation
import Combine
import Foundation

// MARK: - Enums

/// Which scan path the keyboard uses. Both paths are fully built.
enum ScanMode: String, CaseIterable, Identifiable, Codable {
    /// Path A - AVCaptureSession runs inside the keyboard extension.
    case inKeyboard
    /// Path B - the containing app scans and hands the result back via the App Group.
    case inApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inKeyboard: return "In keyboard"
        case .inApp:      return "In app"
        }
    }

    var explanation: String {
        switch self {
        case .inKeyboard:
            return "Camera runs inside the keyboard. Fastest, stays in the POS app. Needs Full Access."
        case .inApp:
            return "Opens GiftKey to scan, then hands the code back to the keyboard. Better on older iPhones."
        }
    }
}

/// Keystroke appended after a successful insert.
enum SuffixKeystroke: String, CaseIterable, Identifiable, Codable {
    case none
    case newline
    case tab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .newline: return "Return"
        case .tab:     return "Tab"
        }
    }

    var characters: String {
        switch self {
        case .none:    return ""
        case .newline: return "\n"
        case .tab:     return "\t"
        }
    }
}

/// Separator inserted between codes while batch mode is on.
enum BatchSeparator: String, CaseIterable, Identifiable, Codable {
    case none
    case newline
    case tab
    case comma

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:    return "None"
        case .newline: return "Return"
        case .tab:     return "Tab"
        case .comma:   return "Comma"
        }
    }

    var characters: String {
        switch self {
        case .none:    return ""
        case .newline: return "\n"
        case .tab:     return "\t"
        case .comma:   return ","
        }
    }
}

/// UPC-A <-> EAN-13 conversion. UPC-A is decoded by AVFoundation as a 13-digit
/// EAN-13 with a leading zero, so both directions are a leading-zero operation.
enum GTINConversion: String, CaseIterable, Identifiable, Codable {
    case off
    /// 12-digit UPC-A -> 13-digit EAN-13 (prepend "0").
    case upcaToEAN13
    /// 13-digit EAN-13 beginning with "0" -> 12-digit UPC-A (drop the "0").
    case ean13ToUPCA

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:         return "Off"
        case .upcaToEAN13: return "UPC-A to EAN-13"
        case .ean13ToUPCA: return "EAN-13 to UPC-A"
        }
    }
}

// MARK: - Store

/// Observable wrapper over the shared UserDefaults suite.
///
/// Properties are computed rather than `@Published` so the keyboard extension always
/// reads the latest value written by the app without needing a change notification.
/// `objectWillChange.send()` on write keeps SwiftUI bindings in the app live.
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppConstants.sharedDefaults) {
        self.defaults = defaults
        SettingsStore.registerDefaults(in: defaults)
    }

    // MARK: Keys

    private enum Key {
        static let scanMode            = "scanMode"
        static let enabledSymbologies  = "enabledSymbologies"
        static let stripCheckDigit     = "stripCheckDigit"
        static let gtinConversion      = "gtinConversion"
        static let regexEnabled        = "regexEnabled"
        static let regexPattern        = "regexPattern"
        static let regexTemplate       = "regexTemplate"
        static let prefix              = "prefixString"
        static let suffix              = "suffixString"
        static let suffixKeystroke     = "suffixKeystroke"
        static let validationPresetID  = "validationPresetID"
        static let customValidationRegex = "customValidationRegex"
        static let batchMode           = "batchMode"
        static let batchSeparator      = "batchSeparator"
        static let beepOnScan          = "beepOnScan"
        static let hapticOnScan        = "hapticOnScan"
        static let onboardingComplete  = "onboardingComplete"
        static let showDiagnostics     = "showDiagnostics"
    }

    /// Defaults applied on first launch: every symbology on, nothing else transforming.
    private static func registerDefaults(in defaults: UserDefaults) {
        defaults.register(defaults: [
            Key.scanMode: ScanMode.inKeyboard.rawValue,
            Key.enabledSymbologies: BarcodeSymbology.allCases.map(\.rawValue),
            Key.stripCheckDigit: false,
            Key.gtinConversion: GTINConversion.off.rawValue,
            Key.regexEnabled: false,
            Key.regexPattern: "",
            Key.regexTemplate: "",
            Key.prefix: "",
            Key.suffix: "",
            Key.suffixKeystroke: SuffixKeystroke.none.rawValue,
            Key.validationPresetID: ValidationPreset.off.id,
            Key.customValidationRegex: "",
            Key.batchMode: false,
            Key.batchSeparator: BatchSeparator.newline.rawValue,
            Key.beepOnScan: true,
            Key.hapticOnScan: true,
            Key.onboardingComplete: false,
            Key.showDiagnostics: false,
        ])
    }

    // MARK: Scan mode

    var scanMode: ScanMode {
        get { ScanMode(rawValue: defaults.string(forKey: Key.scanMode) ?? "") ?? .inKeyboard }
        set { write(newValue.rawValue, Key.scanMode) }
    }

    // MARK: Symbologies

    var enabledSymbologies: Set<BarcodeSymbology> {
        get {
            let raw = defaults.stringArray(forKey: Key.enabledSymbologies) ?? []
            return Set(raw.compactMap(BarcodeSymbology.init(rawValue:)))
        }
        set { write(newValue.map(\.rawValue).sorted(), Key.enabledSymbologies) }
    }

    func isEnabled(_ symbology: BarcodeSymbology) -> Bool {
        enabledSymbologies.contains(symbology)
    }

    func setEnabled(_ enabled: Bool, for symbology: BarcodeSymbology) {
        var current = enabledSymbologies
        if enabled {
            current.insert(symbology)
        } else {
            // Never allow an empty set - a keyboard that can read nothing is a bug report.
            guard current.count > 1 else { return }
            current.remove(symbology)
        }
        enabledSymbologies = current
    }

    /// Metadata object types to hand to AVCaptureMetadataOutput.
    /// Falls back to the full set if the stored set somehow ends up empty.
    var enabledMetadataObjectTypes: [AVMetadataObject.ObjectType] {
        let enabled = enabledSymbologies
        let source = enabled.isEmpty ? Set(BarcodeSymbology.allCases) : enabled
        return source.map(\.metadataObjectType)
    }

    // MARK: Post-processing

    var stripCheckDigit: Bool {
        get { defaults.bool(forKey: Key.stripCheckDigit) }
        set { write(newValue, Key.stripCheckDigit) }
    }

    var gtinConversion: GTINConversion {
        get { GTINConversion(rawValue: defaults.string(forKey: Key.gtinConversion) ?? "") ?? .off }
        set { write(newValue.rawValue, Key.gtinConversion) }
    }

    var regexEnabled: Bool {
        get { defaults.bool(forKey: Key.regexEnabled) }
        set { write(newValue, Key.regexEnabled) }
    }

    var regexPattern: String {
        get { defaults.string(forKey: Key.regexPattern) ?? "" }
        set { write(newValue, Key.regexPattern) }
    }

    var regexTemplate: String {
        get { defaults.string(forKey: Key.regexTemplate) ?? "" }
        set { write(newValue, Key.regexTemplate) }
    }

    var prefixString: String {
        get { defaults.string(forKey: Key.prefix) ?? "" }
        set { write(newValue, Key.prefix) }
    }

    var suffixString: String {
        get { defaults.string(forKey: Key.suffix) ?? "" }
        set { write(newValue, Key.suffix) }
    }

    var suffixKeystroke: SuffixKeystroke {
        get { SuffixKeystroke(rawValue: defaults.string(forKey: Key.suffixKeystroke) ?? "") ?? .none }
        set { write(newValue.rawValue, Key.suffixKeystroke) }
    }

    // MARK: Validation

    var validationPresetID: String {
        get { defaults.string(forKey: Key.validationPresetID) ?? ValidationPreset.off.id }
        set { write(newValue, Key.validationPresetID) }
    }

    var customValidationRegex: String {
        get { defaults.string(forKey: Key.customValidationRegex) ?? "" }
        set { write(newValue, Key.customValidationRegex) }
    }

    /// Resolved preset, with the custom pattern folded in when "Custom" is selected.
    var validationPreset: ValidationPreset {
        let preset = ValidationPreset.preset(withID: validationPresetID)
        guard preset.id == ValidationPreset.custom.id else { return preset }
        return ValidationPreset(id: preset.id,
                                name: preset.name,
                                detail: preset.detail,
                                pattern: customValidationRegex)
    }

    // MARK: Batch

    var batchMode: Bool {
        get { defaults.bool(forKey: Key.batchMode) }
        set { write(newValue, Key.batchMode) }
    }

    var batchSeparator: BatchSeparator {
        get { BatchSeparator(rawValue: defaults.string(forKey: Key.batchSeparator) ?? "") ?? .newline }
        set { write(newValue.rawValue, Key.batchSeparator) }
    }

    // MARK: Feedback

    var beepOnScan: Bool {
        get { defaults.bool(forKey: Key.beepOnScan) }
        set { write(newValue, Key.beepOnScan) }
    }

    var hapticOnScan: Bool {
        get { defaults.bool(forKey: Key.hapticOnScan) }
        set { write(newValue, Key.hapticOnScan) }
    }

    // MARK: Onboarding

    var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete) }
        set { write(newValue, Key.onboardingComplete) }
    }

    // MARK: Troubleshooting

    /// Overlays live camera state on the in-keyboard preview. Off by default.
    /// A keyboard extension cannot be attached to a debugger in the field, so this is
    /// the only way to tell a dead session from a compositing problem.
    var showDiagnostics: Bool {
        get { defaults.bool(forKey: Key.showDiagnostics) }
        set { write(newValue, Key.showDiagnostics) }
    }

    // MARK: Derived

    /// Snapshot handed to the post-processor so a scan is processed against a
    /// consistent set of values even if the app writes mid-scan.
    var pipelineConfiguration: PipelineConfiguration {
        PipelineConfiguration(
            stripCheckDigit: stripCheckDigit,
            gtinConversion: gtinConversion,
            regexEnabled: regexEnabled,
            regexPattern: regexPattern,
            regexTemplate: regexTemplate,
            prefix: prefixString,
            suffix: suffixString,
            suffixKeystroke: suffixKeystroke,
            validationPattern: validationPreset.pattern,
            batchMode: batchMode,
            batchSeparator: batchSeparator
        )
    }

    // MARK: Helpers

    private func write(_ value: Any?, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }
}
