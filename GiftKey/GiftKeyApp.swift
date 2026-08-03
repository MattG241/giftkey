//
//  GiftKeyApp.swift
//  GiftKey
//
//  Containing app entry point.
//
//  The app exists to (a) walk the user through installing the keyboard, (b) hold the
//  settings the keyboard reads, and (c) run the Path B full-screen scanner.
//
//  There is no networking code in this target. None. That is the point.
//

import SwiftUI

@main
struct GiftKeyApp: App {

    @StateObject private var settings = SettingsStore.shared

    /// A new value is minted every time the keyboard opens `giftkey://scan`.
    ///
    /// This is an identifier rather than a Bool on purpose: the app is usually already
    /// running when the keyboard calls it (scan, switch back, scan again), and a Bool
    /// that is already `true` produces no change notification, so the second and every
    /// subsequent round trip would silently fail to open the scanner.
    @State private var scanRequest: UUID?

    var body: some Scene {
        WindowGroup {
            RootView(scanRequest: $scanRequest)
                .environmentObject(settings)
                .onOpenURL { url in
                    handle(url)
                }
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme?.lowercased() == AppConstants.urlScheme else { return }
        // giftkey://scan
        let target = url.host?.lowercased() ?? url.path.replacingOccurrences(of: "/", with: "")
        guard target == "scan" else { return }
        scanRequest = UUID()
    }
}
