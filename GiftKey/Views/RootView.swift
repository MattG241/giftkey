//
//  RootView.swift
//  GiftKey
//
//  Four tabs: Setup, Scan, Settings, FAQ.
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var settings: SettingsStore

    /// Non-nil, and freshly minted, each time the keyboard asks us to scan.
    @Binding var scanRequest: UUID?

    @State private var selectedTab: Tab = .setup

    enum Tab: Hashable {
        case setup, scan, settings, faq
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SetupView()
                .tabItem { Label("Setup", systemImage: "checklist") }
                .tag(Tab.setup)

            InAppScannerHomeView(scanRequest: scanRequest)
                .tabItem { Label("Scan", systemImage: "barcode.viewfinder") }
                .tag(Tab.scan)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(Tab.settings)

            FAQView()
                .tabItem { Label("FAQ", systemImage: "questionmark.circle") }
                .tag(Tab.faq)
        }
        .onAppear {
            if let forced = RootView.screenshotTab {
                selectedTab = forced
            } else if settings.onboardingComplete && selectedTab == .setup {
                // Returning users land on Settings; first-timers land on Setup.
                selectedTab = .settings
            }
        }
        .onChange(of: scanRequest) { request in
            guard request != nil else { return }
            selectedTab = .scan
        }
    }

    // MARK: - Screenshot automation

    /// Opens a specific tab on launch, for the App Store screenshot workflow.
    ///
    /// Driven by `-GiftKeyScreenshotTab <setup|scan|settings|faq>` passed on the command
    /// line, which lands in UserDefaults' argument domain. Compiled out of release
    /// builds entirely, and even in debug it is inert unless that argument is present,
    /// so it cannot affect a real launch.
    private static var screenshotTab: Tab? {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "GiftKeyScreenshotTab") {
        case "setup":    return .setup
        case "scan":     return .scan
        case "settings": return .settings
        case "faq":      return .faq
        default:         return nil
        }
        #else
        return nil
        #endif
    }
}
