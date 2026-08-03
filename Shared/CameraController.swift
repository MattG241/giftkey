//
//  CameraController.swift
//  Shared
//
//  Thin, memory-conscious wrapper around AVCaptureSession + AVCaptureMetadataOutput.
//
//  This is the Path A engine (camera running *inside* the keyboard extension) and is
//  also used by the containing app whenever VisionKit's DataScannerViewController is
//  unavailable on the device.
//
//  Keyboard extensions get roughly 60-70 MB before jetsam kills them. The rules this
//  class follows to stay well under that:
//    - lowest usable session preset (.vga640x480, .hd1280x720 as an upper bound)
//    - metadata output only. No AVCaptureVideoDataOutput, so no sample buffers are ever
//      handed to us and no frame is ever retained.
//    - configure / start on a private serial queue, never on the main thread
//    - `stop()` tears the session all the way down (inputs and outputs removed) rather
//      than just pausing it, and is called every time the scanner is hidden
//

import AVFoundation
import CoreImage
import Foundation
import QuartzCore

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
            }
        }
    }

    /// Quality preset. `.vga640x480` is plenty for 1D retail barcodes at arm's length
    /// and roughly halves the session's memory footprint versus 720p.
    enum Quality {
        case low   // .vga640x480 - default, used in the keyboard
        case high  // .hd1280x720 - used in the containing app where memory is not tight

        var preset: AVCaptureSession.Preset {
            switch self {
            case .low:  return .vga640x480
            case .high: return .hd1280x720
            }
        }
    }

    /// How the host wants the camera image delivered.
    enum PreviewMode {
        /// An `AVCaptureVideoPreviewLayer` the host adds to its view hierarchy.
        /// Cheapest and smoothest - use it anywhere it actually renders.
        case previewLayer

        /// Individual frames delivered as `CGImage`, for the host to draw into an
        /// ordinary `UIImageView`.
        ///
        /// Required inside the keyboard extension. Keyboards are hosted out-of-process
        /// and their views composite through a remote view service; hosted media layers
        /// such as AVCaptureVideoPreviewLayer frequently do not survive that boundary
        /// and render solid black even though the session beneath them is running
        /// perfectly. Drawing frames into a plain image view sidesteps it entirely.
        ///
        /// Costs more CPU and allocates a CGImage per delivered frame, so it is
        /// throttled (see `previewFrameInterval`) and late frames are discarded.
        case sampleBuffers
    }

    weak var delegate: CameraControllerDelegate?

    /// The layer the host view should display. Only produced in `.previewLayer` mode.
    /// Created lazily, released on `stop()`.
    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    /// Called on the main queue the moment the preview layer exists.
    ///
    /// Necessary because `start()` can return before the layer is created: when camera
    /// permission has not been asked for yet, `start()` kicks off the permission prompt
    /// and re-enters asynchronously. Hosts that read `previewLayer` straight after
    /// `start()` would get nil and show a black rectangle forever.
    var onPreviewLayerReady: ((AVCaptureVideoPreviewLayer) -> Void)?

    /// Delivered on the main queue in `.sampleBuffers` mode, throttled.
    var onPreviewFrame: ((CGImage) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "\(AppConstants.appBundleID).camera",
                                             qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "\(AppConstants.appBundleID).metadata",
                                              qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "\(AppConstants.appBundleID).frames",
                                           qos: .userInitiated)

    private var device: AVCaptureDevice?
    private var isRunning = false

    private let quality: Quality
    private let previewMode: PreviewMode
    private var objectTypes: [AVMetadataObject.ObjectType]

    /// ~15 fps. Plenty for aiming at a barcode, and half the conversion work of 30.
    private let previewFrameInterval: CFTimeInterval = 1.0 / 15.0
    private var lastPreviewFrameTime: CFTimeInterval = 0

    /// One context reused for every frame. Creating a CIContext per frame is the
    /// classic way to blow a keyboard extension's memory budget.
    private lazy var ciContext: CIContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Diagnostics
    //
    // Surfaced in the keyboard when Settings > Troubleshooting > Show diagnostics is on.
    // Debugging an extension without Xcode attached is otherwise near impossible.

    private(set) var diagnosticInputCount = 0
    private(set) var diagnosticOutputCount = 0
    private(set) var diagnosticFrameCount = 0

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
        return "\(auth) | running \(session.isRunning ? "Y" : "N") | "
             + "in \(diagnosticInputCount) out \(diagnosticOutputCount) | "
             + "frames \(diagnosticFrameCount)"
    }

    // Debounce: an identical payload seen within this window counts as one scan.
    private let debounceInterval: TimeInterval = 2.0
    private var lastValue: String?
    private var lastValueDate: Date?
    /// Set while the UI is showing its freeze-frame / success state.
    var isPaused = false

    init(quality: Quality = .low,
         previewMode: PreviewMode = .previewLayer,
         objectTypes: [AVMetadataObject.ObjectType] = []) {
        self.quality = quality
        self.previewMode = previewMode
        self.objectTypes = objectTypes
        super.init()
    }

    deinit {
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
        diagnosticFrameCount = 0
        lastPreviewFrameTime = 0

        if previewMode == .previewLayer {
            // Create the preview layer on the main thread so the host can attach it
            // immediately; the session behind it configures asynchronously.
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer
            onPreviewLayerReady?(layer)
        }

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

        // Preview frames, only where the host cannot use a preview layer.
        if previewMode == .sampleBuffers {
            let video = AVCaptureVideoDataOutput()
            video.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            // Never queue up frames. If conversion falls behind, drop rather than
            // accumulate - a backlog of VGA buffers is exactly how an extension dies.
            video.alwaysDiscardsLateVideoFrames = true
            if session.canAddOutput(video) {
                session.addOutput(video)
                video.setSampleBufferDelegate(self, queue: frameQueue)
                if let connection = video.connection(with: .video),
                   connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }

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

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Throttle before doing any work.
        let now = CACurrentMediaTime()
        guard now - lastPreviewFrameTime >= previewFrameInterval else { return }
        lastPreviewFrameTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // The CIImage borrows the pixel buffer; createCGImage copies out of it. Nothing
        // here outlives this call, so no frame is ever retained.
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        diagnosticFrameCount += 1

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning, !self.isPaused else { return }
            self.onPreviewFrame?(cgImage)
        }
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
