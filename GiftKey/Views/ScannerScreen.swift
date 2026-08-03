//
//  ScannerScreen.swift
//  GiftKey
//
//  Full-screen scanner presented from the Scan tab. Picks the VisionKit engine when the
//  device supports it and falls back to the shared AVFoundation controller otherwise,
//  then draws one shared overlay on top of whichever ran.
//

import AVFoundation
import SwiftUI
import UIKit

struct ScannerScreen: View {

    @EnvironmentObject private var settings: SettingsStore

    /// Batch mode keeps the camera alive after each decode.
    let continuous: Bool
    let onScan: (String, BarcodeSymbology?) -> Void
    let onClose: () -> Void

    @StateObject private var handle = ScannerHandle()
    @State private var count = 0
    @State private var flash = false
    @State private var failureMessage: String?
    @State private var permissionDenied =
        CameraController.authorizationStatus == .denied
        || CameraController.authorizationStatus == .restricted

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if permissionDenied {
                permissionView
            } else {
                engine
                    .ignoresSafeArea()
                reticle
                overlay
            }

            if flash {
                Color.green.opacity(0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    // MARK: - Engine

    @ViewBuilder
    private var engine: some View {
        if DataScannerRepresentable.isAvailable {
            DataScannerRepresentable(
                symbologies: settings.enabledVisionSymbologies,
                handle: handle,
                onScan: handleScan
            )
        } else {
            AVScannerRepresentable(
                objectTypes: settings.enabledMetadataObjectTypes,
                handle: handle,
                onScan: handleScan,
                onFailure: { failure in
                    if failure == .permissionDenied {
                        permissionDenied = true
                    } else {
                        failureMessage = failure.message
                    }
                }
            )
        }
    }

    // MARK: - Overlay

    private var reticle: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.82
            let height = min(proxy.size.height * 0.30, width * 0.5)
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: width, height: height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .allowsHitTesting(false)
        }
    }

    private var overlay: some View {
        VStack {
            HStack {
                Button {
                    onClose()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Spacer()

                Button {
                    handle.toggleTorch()
                } label: {
                    Image(systemName: handle.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .frame(width: 20, height: 20)
                        .padding(12)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .foregroundStyle(handle.isTorchOn ? Color.yellow : Color.primary)
            }
            .padding()

            Spacer()

            VStack(spacing: 8) {
                if let failureMessage {
                    Text(failureMessage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.red)
                }
                if continuous {
                    Text("\(count) scanned")
                        .font(.headline)
                }
                Text(continuous
                     ? "Batch mode. Tap Close when you are done."
                     : "Line the barcode up inside the box.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding()
        }
        .tint(.white)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Camera access is off")
                .font(.title3.bold())
            Text("Turn it on in Settings > GiftKey > Camera.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
            Button("Close", action: onClose)
        }
        .padding(32)
    }

    // MARK: - Handling

    private func handleScan(_ raw: String, _ symbology: BarcodeSymbology?) {
        count += 1
        onScan(raw, symbology)

        withAnimation(.easeIn(duration: 0.08)) { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.2)) { flash = false }
            if continuous { handle.resume() }
        }
    }
}
