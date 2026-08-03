//
//  SetupView.swift
//  GiftKey
//
//  Onboarding. Three steps, a live status indicator driven by the keyboard's App Group
//  heartbeat, and a test field so staff can prove it works before they are standing in
//  front of a customer.
//

import SwiftUI
import UIKit

struct SetupView: View {

    @EnvironmentObject private var settings: SettingsStore

    @State private var testText = ""
    @State private var keyboardDetected = KeyboardPresence.hasEverRunWithFullAccess
    @State private var statusDetail = KeyboardPresence.statusDescription
    @FocusState private var testFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                statusSection
                stepOne
                stepTwo
                stepThree
                privacyNote
            }
            .navigationTitle("Setup")
            .onAppear(perform: refreshStatus)
            // Coming back from Settings.app is the moment the status usually changes.
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                refreshStatus()
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: keyboardDetected ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(keyboardDetected ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(keyboardDetected ? "Keyboard is ready" : "Keyboard not set up yet")
                        .font(.headline)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            if !AppConstants.appGroupIsConfigured {
                Label("App Group is not configured. Settings will not reach the keyboard. See README.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var stepOne: some View {
        Section {
            StepRow(number: 1, title: "Add the GiftKey keyboard") {
                Text("Settings > General > Keyboard > Keyboards > Add New Keyboard, then choose GiftKey.")
            }
            Button {
                openAppSettings()
            } label: {
                Label("Open Settings", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("Step 1")
        }
    }

    private var stepTwo: some View {
        Section {
            StepRow(number: 2, title: "Allow Full Access") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppConstants.fullAccessPath)
                        .font(.footnote.monospaced())
                    Text("Required so the keyboard can use the camera and read your settings. GiftKey has no network code at all - nothing can leave your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Step 2")
        }
    }

    private var stepThree: some View {
        Section {
            StepRow(number: 3, title: "Test it here") {
                Text("Tap the field, press the globe key until GiftKey appears, then tap Scan.")
            }
            TextField("Scanned code appears here", text: $testText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.default)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($testFieldFocused)

            HStack {
                Button("Clear") { testText = "" }
                    .disabled(testText.isEmpty)
                Spacer()
                if !testText.isEmpty {
                    Label("\(testText.count) characters", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Button {
                settings.onboardingComplete = true
            } label: {
                Label("Mark setup complete", systemImage: "checkmark.circle")
            }
            .disabled(settings.onboardingComplete)
        } header: {
            Text("Step 3")
        } footer: {
            Text("A numeric-only field (like the Shopify POS gift card field) will show a number pad from the host app until you switch to GiftKey. That is normal.")
        }
    }

    private var privacyNote: some View {
        Section {
            Label("No scan data is stored or transmitted.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func refreshStatus() {
        keyboardDetected = KeyboardPresence.hasEverRunWithFullAccess
        statusDetail = KeyboardPresence.statusDescription
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Row

private struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                content
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
