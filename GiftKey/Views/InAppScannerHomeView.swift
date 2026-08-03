//
//  InAppScannerHomeView.swift
//  GiftKey
//
//  The Scan tab. Two jobs:
//
//    1. Path B endpoint. When the keyboard opens giftkey://scan we present the scanner
//       immediately, write the result into the App Group, and tell the user to switch
//       back to the field they were editing.
//
//    2. Standalone scan-and-copy for people who just want a code on the clipboard.
//

import SwiftUI
import UIKit

struct InAppScannerHomeView: View {

    @EnvironmentObject private var settings: SettingsStore

    /// Freshly minted by the app each time the keyboard opens `giftkey://scan`.
    /// Nil when the user simply tapped into this tab themselves.
    let scanRequest: UUID?

    @State private var showScanner = false
    @State private var lastRaw: String?
    @State private var lastSymbology: BarcodeSymbology?
    @State private var lastOutcome: ScanOutcome?
    @State private var didCopy = false

    /// The last request we acted on, so one request opens the scanner exactly once.
    @State private var handledRequest: UUID?
    /// True once this tab has served at least one keyboard handoff.
    @State private var isHandoffSession = false

    var body: some View {
        NavigationStack {
            List {
                if isHandoffSession {
                    handoffSection
                }
                scanSection
                if lastRaw != nil {
                    resultSection
                }
                privacySection
            }
            .navigationTitle("Scan")
            .fullScreenCover(isPresented: $showScanner) {
                ScannerScreen(
                    continuous: settings.batchMode,
                    onScan: handleScan,
                    onClose: { showScanner = false }
                )
                .environmentObject(settings)
            }
            // Cold launch from the keyboard.
            .onAppear { presentScannerIfRequested() }
            // Warm re-entry: the app was already running and the keyboard asked again.
            .onChange(of: scanRequest) { _ in presentScannerIfRequested() }
        }
    }

    // MARK: - Sections

    private var handoffSection: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Handoff mode")
                        .font(.headline)
                    Text(lastRaw == nil
                         ? "Scan a code, then tap the back arrow at the top left of the screen. The GiftKey keyboard types it as soon as you land."
                         : "Code ready. Tap the back arrow at the top left to return - GiftKey types it the moment the keyboard appears.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(Color.accentColor)
            }

            if lastRaw != nil {
                Text("The code expires in \(Int(ScanHandoff.expiry)) seconds for your safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scanSection: some View {
        Section {
            Button {
                showScanner = true
            } label: {
                Label("Scan a barcode", systemImage: "barcode.viewfinder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        Section {
            LabeledContent("Raw") {
                Text(lastRaw ?? "")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            if let symbology = lastSymbology {
                LabeledContent("Type", value: symbology.displayName)
            }

            if let outcome = lastOutcome {
                switch outcome {
                case .accepted(let code, _):
                    LabeledContent("Processed") {
                        Text(code)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    Button {
                        UIPasteboard.general.string = code
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { didCopy = false }
                    } label: {
                        Label(didCopy ? "Copied" : "Copy to clipboard",
                              systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                case .rejected(let rejection):
                    Label(rejection.message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text("The keyboard would refuse to type this. Change the validation filter in Settings if that is wrong.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Last scan")
        }
    }

    private var privacySection: some View {
        Section {
            Label("Scans are processed on device. Nothing is stored or transmitted.",
                  systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Handling

    /// Opens the scanner for a request we have not served yet. Safe to call repeatedly.
    private func presentScannerIfRequested() {
        guard let scanRequest, scanRequest != handledRequest else { return }
        handledRequest = scanRequest
        isHandoffSession = true

        // Clear the previous round trip so the banner does not claim a stale code is
        // waiting to be typed.
        lastRaw = nil
        lastSymbology = nil
        lastOutcome = nil

        showScanner = true
    }

    private func handleScan(raw: String, symbology: BarcodeSymbology?) {
        lastRaw = raw
        lastSymbology = symbology
        lastOutcome = ScanPostProcessor.process(raw: raw,
                                                symbology: symbology,
                                                config: settings.pipelineConfiguration)

        // Publish to the App Group for the keyboard to pick up. In batch mode codes
        // accumulate so the whole stack is typed on return; otherwise each scan replaces
        // the last. The keyboard consumes it once and it expires after 60 seconds, so an
        // unused handoff cannot surprise anyone later.
        if settings.batchMode {
            ScanHandoffStore.append(raw: raw, symbology: symbology)
        } else {
            ScanHandoffStore.write(raw: raw, symbology: symbology)
        }

        Feedback.success(beep: settings.beepOnScan, haptic: settings.hapticOnScan)

        if !settings.batchMode {
            showScanner = false
        }
    }
}
