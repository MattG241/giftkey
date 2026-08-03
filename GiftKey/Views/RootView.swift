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
            // Returning users land on Settings; first-timers land on Setup.
            if settings.onboardingComplete && selectedTab == .setup {
                selectedTab = .settings
            }
        }
        .onChange(of: scanRequest) { request in
            guard request != nil else { return }
            selectedTab = .scan
        }
    }
}
