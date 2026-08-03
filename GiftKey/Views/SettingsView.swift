//
//  SettingsView.swift
//  GiftKey
//
//  Every setting the keyboard reads. Writes go straight to the shared App Group suite,
//  so changes take effect on the very next scan with no restart.
//
//  The live preview at the top runs the real ScanPostProcessor against a sample code so
//  the user can see exactly what will be typed before they are at the counter.
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var settings: SettingsStore

    /// Sample used by the live preview. Defaults to a plausible gift card number.
    @State private var sampleInput = "9312345678901"

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                scanModeSection
                validationSection
                pipelineSection
                batchSection
                feedbackSection
                symbologySection
                troubleshootingSection
                resetSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: - Live preview

    private var previewSection: some View {
        Section {
            TextField("Sample barcode", text: $sampleInput)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .font(.body.monospaced())

            switch previewOutcome {
            case .accepted(let code, _):
                Label {
                    Text(code.isEmpty ? "(empty)" : code)
                        .font(.body.monospaced())
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .rejected(let rejection):
                Label {
                    Text(rejection.message)
                } icon: {
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
        } header: {
            Text("Preview")
        } footer: {
            Text("What GiftKey would type for this code with your current settings.")
        }
    }

    private var previewOutcome: ScanOutcome {
        ScanPostProcessor.process(raw: sampleInput,
                                  symbology: nil,
                                  config: settings.pipelineConfiguration)
    }

    // MARK: - Scan mode

    private var scanModeSection: some View {
        Section {
            Picker("Scan mode", selection: Binding(
                get: { settings.scanMode },
                set: { settings.scanMode = $0 }
            )) {
                ForEach(ScanMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(settings.scanMode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Scan mode")
        }
    }

    // MARK: - Validation

    private var validationSection: some View {
        Section {
            Picker("Filter", selection: Binding(
                get: { settings.validationPresetID },
                set: { settings.validationPresetID = $0 }
            )) {
                ForEach(ValidationPreset.all) { preset in
                    Text(preset.name).tag(preset.id)
                }
            }

            Text(ValidationPreset.preset(withID: settings.validationPresetID).detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.validationPresetID == ValidationPreset.custom.id {
                TextField("^[0-9]{8,20}$", text: Binding(
                    get: { settings.customValidationRegex },
                    set: { settings.customValidationRegex = $0 }
                ))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                if !ScanPostProcessor.isValidRegex(settings.customValidationRegex) {
                    Label("Not a valid regular expression", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Validation filter")
        } footer: {
            Text("A scan that fails the filter is not typed at all. The keyboard shakes and buzzes instead. This is what stops a product barcode landing in a gift card field.")
        }
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        Section {
            Toggle("Strip EAN/UPC check digit", isOn: Binding(
                get: { settings.stripCheckDigit },
                set: { settings.stripCheckDigit = $0 }
            ))

            Picker("GTIN conversion", selection: Binding(
                get: { settings.gtinConversion },
                set: { settings.gtinConversion = $0 }
            )) {
                ForEach(GTINConversion.allCases) { conversion in
                    Text(conversion.displayName).tag(conversion)
                }
            }

            Toggle("Find and replace", isOn: Binding(
                get: { settings.regexEnabled },
                set: { settings.regexEnabled = $0 }
            ))

            if settings.regexEnabled {
                TextField("Find (regex)", text: Binding(
                    get: { settings.regexPattern },
                    set: { settings.regexPattern = $0 }
                ))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                TextField("Replace with (use $1 for groups)", text: Binding(
                    get: { settings.regexTemplate },
                    set: { settings.regexTemplate = $0 }
                ))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                if !ScanPostProcessor.isValidRegex(settings.regexPattern) {
                    Label("Not a valid regular expression", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            TextField("Prefix", text: Binding(
                get: { settings.prefixString },
                set: { settings.prefixString = $0 }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            TextField("Suffix", text: Binding(
                get: { settings.suffixString },
                set: { settings.suffixString = $0 }
            ))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Picker("Suffix keystroke", selection: Binding(
                get: { settings.suffixKeystroke },
                set: { settings.suffixKeystroke = $0 }
            )) {
                ForEach(SuffixKeystroke.allCases) { keystroke in
                    Text(keystroke.displayName).tag(keystroke)
                }
            }
        } header: {
            Text("Post-processing")
        } footer: {
            Text("Applied in the order shown. Whitespace and control characters are always trimmed first.")
        }
    }

    // MARK: - Batch

    private var batchSection: some View {
        Section {
            Toggle("Batch mode", isOn: Binding(
                get: { settings.batchMode },
                set: { settings.batchMode = $0 }
            ))

            if settings.batchMode {
                Picker("Separator", selection: Binding(
                    get: { settings.batchSeparator },
                    set: { settings.batchSeparator = $0 }
                )) {
                    ForEach(BatchSeparator.allCases) { separator in
                        Text(separator.displayName).tag(separator)
                    }
                }
            }
        } header: {
            Text("Batch mode")
        } footer: {
            Text("Keeps the camera running after each insert and shows a running count. The separator is typed between codes instead of the suffix keystroke.")
        }
    }

    // MARK: - Feedback

    private var feedbackSection: some View {
        Section {
            Toggle("Beep on scan", isOn: Binding(
                get: { settings.beepOnScan },
                set: { settings.beepOnScan = $0 }
            ))
            Toggle("Haptic on scan", isOn: Binding(
                get: { settings.hapticOnScan },
                set: { settings.hapticOnScan = $0 }
            ))
        } header: {
            Text("Feedback")
        } footer: {
            Text("Haptics inside the keyboard require Full Access.")
        }
    }

    // MARK: - Symbologies

    private var symbologySection: some View {
        Section {
            ForEach(BarcodeSymbology.allCases) { symbology in
                Toggle(isOn: Binding(
                    get: { settings.isEnabled(symbology) },
                    set: { settings.setEnabled($0, for: symbology) }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(symbology.displayName)
                        if !symbology.hint.isEmpty {
                            Text(symbology.hint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Barcode types")
        } footer: {
            Text("Turning off types you never use makes decoding faster and reduces misreads. At least one must stay on.")
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingSection: some View {
        Section {
            Toggle("Show diagnostics", isOn: Binding(
                get: { settings.showDiagnostics },
                set: { settings.showDiagnostics = $0 }
            ))
        } header: {
            Text("Troubleshooting")
        } footer: {
            Text("Overlays live camera state on the keyboard's preview: permission, whether the session is running, and how many frames have arrived. Turn this on if the preview is black, then read the line at the top of the preview.")
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        Section {
            Button {
                applyGiftCardDefaults()
            } label: {
                Label("Apply gift card preset", systemImage: "creditcard")
            }
        } footer: {
            Text("Sets the 8-20 digit filter, turns off all transformations, and leaves only Code 128 and EAN/UPC enabled - the setup for scanning third-party gift cards into a POS.")
        }
    }

    /// One tap to get to the configuration this app was built for.
    private func applyGiftCardDefaults() {
        settings.validationPresetID = ValidationPreset.giftCard.id
        settings.stripCheckDigit = false
        settings.gtinConversion = .off
        settings.regexEnabled = false
        settings.prefixString = ""
        settings.suffixString = ""
        settings.suffixKeystroke = .none
        settings.batchMode = false
        settings.enabledSymbologies = [.code128, .code39, .ean13, .ean8, .itf14, .interleaved2of5]
    }
}
