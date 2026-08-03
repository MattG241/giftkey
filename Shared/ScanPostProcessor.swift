//
//  ScanPostProcessor.swift
//  Shared
//
//  The ordered post-processing pipeline applied to every decoded barcode before it is
//  typed into the host app. Pure value-in / value-out, no UIKit, no I/O - so it is
//  cheap to run inside the memory-constrained keyboard extension and trivial to unit
//  test.
//
//  Order (matches the settings screen top to bottom):
//    1. Trim whitespace + strip control characters      (always on)
//    2. Strip EAN/UPC check digit                       (optional)
//    3. UPC-A <-> EAN-13 conversion                     (optional)
//    4. Regex find and replace                          (optional)
//    5. Prefix and suffix strings                       (optional)
//    6. Validation filter                               (optional)
//    7. Suffix keystroke / batch separator              (optional)
//
//  Note on ordering: the spec lists the suffix keystroke before validation. Validation
//  runs first here deliberately - validating a code that already has "\n" glued to the
//  end would make every pattern need a trailing "\n?", which is a footgun. The
//  keystroke is transport, not part of the code.
//

import Foundation

// MARK: - Configuration

/// Immutable snapshot of the pipeline settings, taken at scan time.
struct PipelineConfiguration {
    var stripCheckDigit: Bool = false
    var gtinConversion: GTINConversion = .off
    var regexEnabled: Bool = false
    var regexPattern: String = ""
    var regexTemplate: String = ""
    var prefix: String = ""
    var suffix: String = ""
    var suffixKeystroke: SuffixKeystroke = .none
    /// Empty means no validation.
    var validationPattern: String = ""
    var batchMode: Bool = false
    var batchSeparator: BatchSeparator = .newline
}

// MARK: - Result

enum ScanRejection: Equatable {
    case emptyAfterProcessing
    case failedValidation(pattern: String)
    case invalidValidationPattern

    /// Short message shown in the keyboard's error banner.
    var message: String {
        switch self {
        case .emptyAfterProcessing:
            return "Nothing left after processing"
        case .failedValidation:
            return "Code rejected by filter"
        case .invalidValidationPattern:
            return "Validation regex is invalid"
        }
    }
}

enum ScanOutcome: Equatable {
    /// `code` is the validated payload; `textToInsert` includes any trailing
    /// keystroke or batch separator.
    case accepted(code: String, textToInsert: String)
    case rejected(ScanRejection)
}

// MARK: - Processor

enum ScanPostProcessor {

    /// Runs the full pipeline.
    ///
    /// - Parameters:
    ///   - raw: the decoded barcode string, exactly as AVFoundation/Vision reported it.
    ///   - symbology: used to decide whether check-digit stripping applies.
    ///   - config: snapshot of the user's settings.
    static func process(raw: String,
                        symbology: BarcodeSymbology?,
                        config: PipelineConfiguration) -> ScanOutcome {

        // 1. Trim whitespace and strip control characters. Always on.
        var value = sanitize(raw)

        // 2. Strip EAN/UPC check digit.
        if config.stripCheckDigit {
            value = strippingCheckDigit(value, symbology: symbology)
        }

        // 3. UPC-A <-> EAN-13.
        value = converting(value, using: config.gtinConversion)

        // 4. Regex find and replace.
        if config.regexEnabled, !config.regexPattern.isEmpty {
            value = replacing(value,
                              pattern: config.regexPattern,
                              template: config.regexTemplate)
        }

        // 5. Prefix and suffix strings.
        value = config.prefix + value + config.suffix

        guard !value.isEmpty else {
            return .rejected(.emptyAfterProcessing)
        }

        // 6. Validation filter.
        if !config.validationPattern.trimmingCharacters(in: .whitespaces).isEmpty {
            switch matchesFully(value, pattern: config.validationPattern) {
            case .some(true):
                break
            case .some(false):
                return .rejected(.failedValidation(pattern: config.validationPattern))
            case .none:
                return .rejected(.invalidValidationPattern)
            }
        }

        // 7. Trailing keystroke. In batch mode the separator takes over so codes stack
        //    up correctly in the destination field.
        let trailer = config.batchMode
            ? config.batchSeparator.characters
            : config.suffixKeystroke.characters

        return .accepted(code: value, textToInsert: value + trailer)
    }

    // MARK: - Step 1

    /// Trims surrounding whitespace/newlines and removes any control characters that
    /// some symbologies (Code 128 FNC codes, Codabar start/stop) can smuggle in.
    static func sanitize(_ input: String) -> String {
        let withoutControls = input.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        return String(String.UnicodeScalarView(withoutControls))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Step 2

    /// Drops the trailing check digit for EAN/UPC payloads.
    ///
    /// Applied when the symbology is in the EAN/UPC family, or - when the symbology is
    /// unknown (Path B / Vision fallback) - when the payload looks like a GTIN
    /// (all digits, 8 / 12 / 13 / 14 long).
    static func strippingCheckDigit(_ input: String,
                                    symbology: BarcodeSymbology?) -> String {
        let looksLikeGTIN = input.allSatisfy(\.isNumber)
            && [8, 12, 13, 14].contains(input.count)

        let applies = symbology?.isEANUPCFamily ?? looksLikeGTIN
        guard applies, input.count > 1, input.allSatisfy(\.isNumber) else { return input }

        return String(input.dropLast())
    }

    // MARK: - Step 3

    /// AVFoundation reports UPC-A as a 13-character EAN-13 with a leading zero, so both
    /// directions are a leading-zero add/remove.
    static func converting(_ input: String, using conversion: GTINConversion) -> String {
        guard input.allSatisfy(\.isNumber) else { return input }

        switch conversion {
        case .off:
            return input
        case .upcaToEAN13:
            // 12-digit UPC-A becomes a 13-digit EAN-13.
            return input.count == 12 ? "0" + input : input
        case .ean13ToUPCA:
            // 13-digit EAN-13 in the "0" prefix range is a UPC-A.
            return (input.count == 13 && input.hasPrefix("0")) ? String(input.dropFirst()) : input
        }
    }

    // MARK: - Step 4

    /// Single find-and-replace rule. An invalid pattern is a no-op rather than a crash;
    /// SettingsView validates the pattern as the user types so this rarely bites.
    static func replacing(_ input: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        return regex.stringByReplacingMatches(in: input,
                                              options: [],
                                              range: range,
                                              withTemplate: template)
    }

    // MARK: - Step 6

    /// Whole-string match. Returns nil when the pattern itself does not compile.
    static func matchesFully(_ input: String, pattern: String) -> Bool? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(input.startIndex..., in: input)
        guard let match = regex.firstMatch(in: input, options: [], range: range) else {
            return false
        }
        // Require the match to cover the entire string even if the author omitted ^ and $.
        return match.range == range
    }

    /// Used by SettingsView to show live "invalid pattern" feedback.
    static func isValidRegex(_ pattern: String) -> Bool {
        pattern.isEmpty || (try? NSRegularExpression(pattern: pattern)) != nil
    }
}
