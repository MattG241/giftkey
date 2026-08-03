//
//  CameraController.swift
//  Shared
//
//  Thin, memory-conscious wrapper around AVCaptureSession + AVCaptureMetadataOutput.
//
//  Used by the containing app whenever VisionKit's DataScannerViewController is
//  unavailable on the device (pre-A12 hardware).
//
//  This is NOT used by the keyboard extension. iOS does not permit a keyboard extension
//  to use the camera at all - a session there configures correctly and then never runs.
//  See KeyboardViewController for the full explanation.
//
//  Design rules kept from that era, still worth keeping:
//    - metadata output only. No AVCaptureVideoDataOutput, so no sample buffers are ever
//      handed to us and no frame is ever retained.
//    - configure / start on a private serial queue, never on the main thread
//    - `stop()` tears the session all the way down (inputs and outputs removed) rather
//      than just pausing it, and is called every time the scanner is hidden
//

import AVFoundation
import Foundation

protocol CameraControllerDelegate: AnyObject {
    /// Called on the main queue after debouncing.
    func cameraController(_ controller: CameraController,
                          didDecode value: String,
                          symbology: BarcodeSymbology?)
    /// Called on the main queue when the session cannot start.
    func cameraController(_ controller: CameraController,
                          didFailWith failure: CameraController.Failure)
}

final class CameraController: NSObject {

    enum Failure: Equatable {
        case permissionDenied
        case permissionUndetermined
        case noCamera
        case configurationFailed
        /// The session was built correctly but iOS never let it run.
        case sessionWouldNotStart(reason: String?)

        var message: String {
            switch self {
            case .permissionDenied:
                return "Camera access is off for \(AppConstants.displayName)."
            case .permissionUndetermined:
                return "\(AppConstants.displayName) needs camera access."
            case .noCamera:
                return "No camera available on this device."
            case .configurationFailed:
                return "Could not start the camera."
            case .sessionWouldNotStart(let reason):
                if let reason {
                    return "iOS would not start the camera here (\(reason))."
                }
                return "iOS would not start the camera."
            }
        }
    }

    /// Quality preset.
    enum Quality {
        case low   // .vga640x480
        case high  // .hd1280x720 - used in the containing app

        var preset: AVCaptureSession.Preset {
            switch self {
            case .low:  return .vga640x480
            case .high: return .hd1280x720
            }
        }
    }

    weak var delegate: CameraControllerDelegate?

    /// The layer the host view should display. Created lazily, released on `stop()`.
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    /// Called on the main queue the moment the preview layer exists.
    ///
    /// Necessary because `start()` can return before the layer is created: when camera
    /// permission has not been asked for yet, `start()` kicks off the permission prompt
    /// and re-enters asynchronously. Hosts that read `previewLayer` straight after
    /// `start()` would get nil and show a black rectangle forever.
    var onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "\(AppConstants.appBundleID).camera",
                                             qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "\(AppConstants.appBundleID).metadata",
                                              qos: .userInitiated)

    private var device: AVCaptureDevice?
    private var isRunning = false

    private let quality: Quality
    private var objectTypes: [AVMetadataObject.ObjectType]

    // MARK: - Diagnostics
    //
    // Kept because they turned a mysterious black preview into a one-line diagnosis
    // once already.

    private(set) var diagnosticInputCount = 0
    private(set) var diagnosticOutputCount = 0

    /// Why the session was interrupted, if it was.
    private(set) var lastInterruptionReason: String?
    private(set) var lastRuntimeError: String?

    var isSessionRunning: Bool { session.isRunning }

    var diagnosticSummary: String {
        let auth: String
        switch CameraController.authorizationStatus {
        case .authorized:    auth = "auth"
        case .denied:        auth = "DENIED"
        case .restricted:    auth = "RESTRICTED"
        case .notDetermined: auth = "undetermined"
        @unknown default:    auth = "?"
        }
        var summary = "\(auth) | running \(session.isRunning ? "Y" : "N") | "
                    + "in \(diagnosticInputCount) out \(diagnosticOutputCount)"
        if let lastInterruptionReason {
            summary += "\nINTERRUPTED: \(lastInterruptionReason)"
        }
        if let lastRuntimeError {
            summary += "\nERROR: \(lastRuntimeError)"
        }
        return summary
    }

    // MARK: - Session notifications

    /// Without these, a session that iOS silently refuses to run is indistinguishable
    /// from one that is merely slow to start.
    private func observeSessionNotifications() {
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(sessionWasInterrupted(_:)),
                           name: .AVCaptureSessionWasInterrupted, object: session)
        centre.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)),
                           name: .AVCaptureSessionInterruptionEnded, object: session)
        centre.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                           name: .AVCaptureSessionRuntimeError, object: session)
    }

    @objc private func sessionWasInterrupted(_ note: Notification) {
        let raw = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        let reason = raw.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))
        lastInterruptionReason = CameraController.describe(reason)
    }

    @objc private func sessionInterruptionEnded(_ note: Notification) {
        lastInterruptionReason = nil
    }

    @objc private func sessionRuntimeError(_ note: Notification) {
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        lastRuntimeError = error.map { "\($0.domain) \($0.code)" } ?? "unknown"
    }

    private static func describe(_ reason: AVCaptureSession.InterruptionReason?) -> String {
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            return "camera unavailable in background"
        case .audioDeviceInUseByAnotherClient:
            return "audio in use elsewhere"
        case .videoDeviceInUseByAnotherClient:
            return "camera in use by another app"
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "camera denied alongside host app"
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "system pressure"
        default:
            return "unknown reason"
        }
    }

    // Debounce: an identical payload seen within this window counts as one scan.
    private let debounceInterval: TimeInterval = 2.0
    private var lastValue: String?
    private var lastValueDate: Date?
    /// Set while the UI is showing its freeze-frame / success state.
    var isPaused = false

    init(quality: Quality = .low,
         objectTypes: [AVMetadataObject.ObjectType] = []) {
        self.quality = quality
        self.objectTypes = objectTypes
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Best-effort teardown if the host forgot.
        session.stopRunning()
    }

    // MARK: - Permission

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Requests access if undetermined. The completion is delivered on the main queue.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: - Lifecycle

    /// Updates the symbologies the session will report. Safe to call before `start()`.
    func setObjectTypes(_ types: [AVMetadataObject.ObjectType]) {
        objectTypes = types
        guard isRunning else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            for output in self.session.outputs {
                guard let metadata = output as? AVCaptureMetadataOutput else { continue }
                metadata.metadataObjectTypes = self.supportedTypes(from: types, on: metadata)
            }
        }
    }

    /// Builds and starts the session. Calls back on failure via the delegate.
    func start() {
        guard !isRunning else { return }

        switch CameraController.authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            CameraController.requestAccess { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.start()
                } else {
                    self.delegate?.cameraController(self, didFailWith: .permissionDenied)
                }
            }
            return
        case .denied, .restricted:
            delegate?.cameraController(self, didFailWith: .permissionDenied)
            return
        @unknown default:
            delegate?.cameraController(self, didFailWith: .permissionDenied)
            return
        }

        isRunning = true
        resetDebounce()

        // Create the preview layer on the main thread so the host can attach it
        // immediately; the session behind it configures asynchronously.
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        onPreviewLayerReady?(layer)

        lastInterruptionReason = nil
        lastRuntimeError = nil
        observeSessionNotifications()

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configureSession() else {
                self.isRunning = false
                DispatchQueue.main.async {
                    self.delegate?.cameraController(self, didFailWith: .configurationFailed)
                }
                return
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }

            // Watchdog. A session can configure perfectly - inputs and outputs all
            // attached - and still never run, because iOS declined it. Without this the
            // host sits on a black rectangle forever with no error to show the user.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self, self.isRunning, !self.session.isRunning else { return }
                self.delegate?.cameraController(
                    self,
                    didFailWith: .sessionWouldNotStart(reason: self.lastInterruptionReason)
                )
            }
        }
    }

    /// Full teardown. Called whenever the scanner UI is dismissed, the keyboard is
    /// hidden, or the app backgrounds. Releases the device and the preview layer so the
    /// extension's memory returns to idle levels.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        isPaused = false
        previewLayer = nil
        resetDebounce()
        NotificationCenter.default.removeObserver(self)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }
            self.session.commitConfiguration()
            self.setTorchInternal(on: false)
            self.device = nil
        }
    }

    // MARK: - Configuration

    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        if session.canSetSessionPreset(quality.preset) {
            session.sessionPreset = quality.preset
        }

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back)
                ?? AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.cameraController(self, didFailWith: .noCamera)
            }
            return false
        }
        device = camera

        guard let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return false }
        session.addInput(input)

        let metadata = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadata) else { return false }
        session.addOutput(metadata)
        metadata.setMetadataObjectsDelegate(self, queue: metadataQueue)
        metadata.metadataObjectTypes = supportedTypes(from: objectTypes, on: metadata)

        configureContinuousAutofocus(on: camera)

        diagnosticInputCount = session.inputs.count
        diagnosticOutputCount = session.outputs.count
        return true
    }

    /// AVFoundation throws if you request a type the output does not advertise, which
    /// varies by device. Intersect first.
    private func supportedTypes(from requested: [AVMetadataObject.ObjectType],
                                on output: AVCaptureMetadataOutput) -> [AVMetadataObject.ObjectType] {
        let available = Set(output.availableMetadataObjectTypes)
        let wanted = requested.isEmpty
            ? BarcodeSymbology.allCases.map(\.metadataObjectType)
            : requested
        let intersection = wanted.filter { available.contains($0) }
        return intersection.isEmpty ? Array(available) : intersection
    }

    private func configureContinuousAutofocus(on camera: AVCaptureDevice) {
        guard (try? camera.lockForConfiguration()) != nil else { return }
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        if camera.isExposureModeSupported(.continuousAutoExposure) {
            camera.exposureMode = .continuousAutoExposure
        }
        // Barcodes are read close up; bias autofocus accordingly where supported.
        if camera.isAutoFocusRangeRestrictionSupported {
            camera.autoFocusRangeRestriction = .near
        }
        camera.unlockForConfiguration()
    }

    // MARK: - Focus

    /// Tap-to-focus. `point` is in the preview layer's coordinate space.
    func focus(atPreviewPoint point: CGPoint) {
        guard let layer = previewLayer else { return }
        let devicePoint = layer.captureDevicePointConverted(fromLayerPoint: point)
        sessionQueue.async { [weak self] in
            guard let camera = self?.device,
                  (try? camera.lockForConfiguration()) != nil else { return }
            if camera.isFocusPointOfInterestSupported,
               camera.isFocusModeSupported(.autoFocus) {
                camera.focusPointOfInterest = devicePoint
                camera.focusMode = .autoFocus
            }
            if camera.isExposurePointOfInterestSupported,
               camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposurePointOfInterest = devicePoint
                camera.exposureMode = .continuousAutoExposure
            }
            camera.unlockForConfiguration()
        }
    }

    // MARK: - Torch

    var isTorchAvailable: Bool {
        device?.hasTorch == true && device?.isTorchAvailable == true
    }

    private(set) var isTorchOn = false

    func setTorch(on: Bool) {
        isTorchOn = on
        sessionQueue.async { [weak self] in
            self?.setTorchInternal(on: on)
        }
    }

    func toggleTorch() {
        setTorch(on: !isTorchOn)
    }

    private func setTorchInternal(on: Bool) {
        guard let camera = device, camera.hasTorch, camera.isTorchAvailable else { return }
        guard (try? camera.lockForConfiguration()) != nil else { return }
        if on {
            // Half power is plenty for a barcode at reading distance and runs cooler.
            try? camera.setTorchModeOn(level: 0.5)
        } else {
            camera.torchMode = .off
        }
        camera.unlockForConfiguration()
    }

    // MARK: - Debounce

    /// Called by the host after it finishes a success animation so the next scan of a
    /// *different* code is accepted immediately.
    func resetDebounce() {
        lastValue = nil
        lastValueDate = nil
    }

    private func shouldAccept(_ value: String) -> Bool {
        guard let previous = lastValue, let date = lastValueDate else { return true }
        guard previous == value else { return true }
        return Date().timeIntervalSince(date) > debounceInterval
    }
}

// MARK: - AVCaptureMetadataOutputObjectsDelegate

extension CameraController: AVCaptureMetadataOutputObjectsDelegate {

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !isPaused else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue,
              !value.isEmpty else { return }

        guard shouldAccept(value) else { return }
        lastValue = value
        lastValueDate = Date()

        let symbology = BarcodeSymbology(metadataObjectType: object.type)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.cameraController(self, didDecode: value, symbology: symbology)
        }
    }
}
