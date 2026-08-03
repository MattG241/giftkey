//
//  ScannerRepresentables.swift
//  GiftKey (containing app only)
//
//  Two interchangeable scanning engines for the full-screen in-app scanner (Path B):
//
//    1. DataScannerRepresentable  - VisionKit's DataScannerViewController. Best
//       tracking and guidance UI, but requires iOS 16 AND an A12 Bionic or newer
//       device (Neural Engine). `DataScannerViewController.isSupported` tells us.
//
//    2. AVScannerRepresentable    - the shared CameraController, at .high quality since
//       the app has no extension memory ceiling. Used on older hardware and whenever
//       VisionKit reports itself unavailable.
//
//  Both report through the same closure so the SwiftUI layer does not care which ran.
//

import AVFoundation
import SwiftUI
import UIKit
import VisionKit

// MARK: - Shared handle

/// Lets SwiftUI reach into whichever engine is running (torch, restart after a pause).
final class ScannerHandle: ObservableObject {
    @Published var isTorchOn = false
    @Published var isTorchAvailable = false

    var toggleTorch: () -> Void = {}
    var resume: () -> Void = {}
}

// MARK: - VisionKit engine

struct DataScannerRepresentable: UIViewControllerRepresentable {

    let symbologies: [VNBarcodeSymbology]
    let handle: ScannerHandle
    let onScan: (String, BarcodeSymbology?) -> Void

    /// True when this device can run DataScannerViewController at all.
    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator

        // Published mutations are deferred so they never land inside a SwiftUI update.
        // `handle` is captured weakly: these closures are stored on `handle` itself, so
        // a strong capture would be a retain cycle.
        DispatchQueue.main.async { [weak handle] in handle?.isTorchAvailable = true }
        handle.toggleTorch = { [weak handle] in
            // DataScannerViewController does not expose the torch, so drive the device
            // directly. Safe: it is the same AVCaptureDevice underneath.
            ScannerTorch.toggle()
            handle?.isTorchOn = ScannerTorch.isOn
        }
        handle.resume = { [weak controller] in
            try? controller?.startScanning()
        }

        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController,
                                          coordinator: Coordinator) {
        controller.stopScanning()
        ScannerTorch.setOn(false)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String, BarcodeSymbology?) -> Void
        private var lastValue: String?
        private var lastDate: Date?

        init(onScan: @escaping (String, BarcodeSymbology?) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                guard case .barcode(let barcode) = item,
                      let value = barcode.payloadStringValue,
                      !value.isEmpty else { continue }

                // Same 2 second debounce as the keyboard path.
                if let lastValue, let lastDate,
                   lastValue == value,
                   Date().timeIntervalSince(lastDate) <= 2.0 {
                    continue
                }
                lastValue = value
                lastDate = Date()

                let symbology = BarcodeSymbology(visionSymbology: barcode.observation.symbology)
                onScan(value, symbology)
                return
            }
        }
    }
}

// MARK: - AVFoundation fallback engine

struct AVScannerRepresentable: UIViewControllerRepresentable {

    let objectTypes: [AVMetadataObject.ObjectType]
    let handle: ScannerHandle
    let onScan: (String, BarcodeSymbology?) -> Void
    let onFailure: (CameraController.Failure) -> Void

    func makeUIViewController(context: Context) -> AVScannerViewController {
        let controller = AVScannerViewController(objectTypes: objectTypes)
        controller.onScan = onScan
        controller.onFailure = onFailure

        // Weak captures - see the note in DataScannerRepresentable.
        handle.toggleTorch = { [weak controller, weak handle] in
            controller?.camera.toggleTorch()
            handle?.isTorchOn = controller?.camera.isTorchOn ?? false
        }
        handle.resume = { [weak controller] in
            controller?.camera.isPaused = false
            controller?.camera.resetDebounce()
        }
        return controller
    }

    func updateUIViewController(_ controller: AVScannerViewController, context: Context) {
        let available = controller.camera.isTorchAvailable
        guard handle.isTorchAvailable != available else { return }
        DispatchQueue.main.async { [weak handle] in handle?.isTorchAvailable = available }
    }
}

/// Minimal full-screen preview host for the fallback engine.
final class AVScannerViewController: UIViewController {

    let camera: CameraController
    var onScan: ((String, BarcodeSymbology?) -> Void)?
    var onFailure: ((CameraController.Failure) -> Void)?

    private let focusIndicator = UIView()

    init(objectTypes: [AVMetadataObject.ObjectType]) {
        camera = CameraController(quality: .high, objectTypes: objectTypes)
        super.init(nibName: nil, bundle: nil)
        camera.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        focusIndicator.layer.borderColor = UIColor.systemYellow.cgColor
        focusIndicator.layer.borderWidth = 1.5
        focusIndicator.layer.cornerRadius = 4
        focusIndicator.frame = CGRect(x: 0, y: 0, width: 72, height: 72)
        focusIndicator.alpha = 0
        view.addSubview(focusIndicator)

        view.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        )

        // Attach on the callback rather than reading `previewLayer` after start(): on a
        // first run the layer only exists once the permission prompt is answered.
        camera.onPreviewLayerReady = { [weak self] layer in
            guard let self else { return }
            layer.frame = self.view.bounds
            self.view.layer.insertSublayer(layer, at: 0)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        camera.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.setTorch(on: false)
        camera.stop()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        camera.previewLayer?.frame = view.bounds
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        camera.focus(atPreviewPoint: point)

        focusIndicator.center = point
        focusIndicator.alpha = 1
        focusIndicator.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
        UIView.animate(withDuration: 0.25, animations: {
            self.focusIndicator.transform = .identity
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.4) { self.focusIndicator.alpha = 0 }
        })
    }
}

extension AVScannerViewController: CameraControllerDelegate {
    func cameraController(_ controller: CameraController,
                          didDecode value: String,
                          symbology: BarcodeSymbology?) {
        onScan?(value, symbology)
    }

    func cameraController(_ controller: CameraController,
                          didFailWith failure: CameraController.Failure) {
        onFailure?(failure)
    }
}

// MARK: - Torch helper for the VisionKit path

/// DataScannerViewController owns its capture session privately, so the torch is driven
/// straight off the default video device.
enum ScannerTorch {

    private(set) static var isOn = false

    static func toggle() { setOn(!isOn) }

    static func setOn(_ on: Bool) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              device.hasTorch, device.isTorchAvailable,
              (try? device.lockForConfiguration()) != nil else { return }
        if on {
            try? device.setTorchModeOn(level: 0.5)
        } else {
            device.torchMode = .off
        }
        device.unlockForConfiguration()
        isOn = on
    }
}
