//
//  KeyboardViewController.swift
//  GiftKeyKeyboard
//
//  The keyboard extension's principal class.
//
//  Responsibilities:
//    - own the two child views (idle / scanning) and switch between them
//    - own the CameraController and guarantee it is torn down whenever the scanner is
//      not visible (memory ceiling is ~60-70 MB for a keyboard extension)
//    - run decoded values through ScanPostProcessor and type the result via
//      textDocumentProxy
//    - Path B: launch the containing app and consume the App Group handoff on return
//    - degrade gracefully when Full Access is off or camera permission is denied
//

import AVFoundation
import UIKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - State

    private enum Mode {
        case idle
        case scanning
    }

    private var mode: Mode = .idle

    private let settings = SettingsStore()
    private var camera: CameraController?

    private var idleView: KeyboardIdleView!
    private var scannerView: KeyboardScannerView!

    private var heightConstraint: NSLayoutConstraint?

    /// Set when the in-keyboard camera fails on this device, which surfaces the
    /// "Scan in app" fallback permanently for the session.
    private var pathAFailed = false

    /// Number of codes inserted during the current batch run.
    private var batchCount = 0

    private var statusResetWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = keyboardBackgroundColor

        // Heartbeat so the containing app's Setup screen can confirm the keyboard is
        // installed and has Full Access. Writing at all proves both.
        if hasFullAccess {
            KeyboardPresence.recordHeartbeat(hasFullAccess: true)
        }

        idleView = KeyboardIdleView(globeTarget: self,
                                    globeAction: #selector(handleInputModeList(from:with:)))
        idleView.delegate = self
        idleView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(idleView)

        scannerView = KeyboardScannerView()
        scannerView.delegate = self
        scannerView.translatesAutoresizingMaskIntoConstraints = false
        scannerView.isHidden = true
        view.addSubview(scannerView)

        NSLayoutConstraint.activate([
            idleView.topAnchor.constraint(equalTo: view.topAnchor),
            idleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            idleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            idleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            scannerView.topAnchor.constraint(equalTo: view.topAnchor),
            scannerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyHeight(animated: false)
        refreshIdleState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A scan may have been produced by the containing app while we were away.
        consumePendingHandoffIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Never leave a capture session alive behind a hidden keyboard.
        stopScanning(returningToIdle: true, animated: false)
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.applyHeight(animated: false)
        })
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Under memory pressure the camera is the first thing to go. Better a message
        // than a jetsam kill that looks to the user like the keyboard "crashed".
        guard mode == .scanning else { return }
        stopScanning(returningToIdle: true, animated: true)
        showIdleStatus("Camera stopped to free memory. Tap Scan to retry.", isError: true)
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Also covers the case where the keyboard is already on screen when the user
        // switches back from the containing app.
        consumePendingHandoffIfNeeded()
    }

    // MARK: - Appearance

    private var keyboardBackgroundColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.13, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }
    }

    // MARK: - Height

    /// Keyboards are free to pick their own height. We run a little taller than a
    /// system keyboard while scanning so the preview is actually usable, and clamp to a
    /// fraction of the screen so landscape on an iPhone SE stays sane.
    private func applyHeight(animated: Bool) {
        let screenHeight = view.window?.screen.bounds.height
            ?? UIScreen.main.bounds.height
        let screenWidth = view.window?.screen.bounds.width
            ?? UIScreen.main.bounds.width
        let isLandscape = screenWidth > screenHeight

        let target: CGFloat
        switch mode {
        case .idle:
            target = isLandscape ? 200 : 258
        case .scanning:
            target = isLandscape ? 240 : 380
        }

        // Never take more than 62% of the screen.
        let clamped = min(target, screenHeight * 0.62)

        if let constraint = heightConstraint {
            constraint.constant = clamped
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: clamped)
            // 999 rather than required: the system occasionally imposes its own height
            // during rotation and a required constraint would break loudly.
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }

        guard animated else {
            view.layoutIfNeeded()
            return
        }
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    // MARK: - Idle state

    private func refreshIdleState() {
        let isInAppMode = settings.scanMode == .inApp
        idleView.showsGlobeKey = needsInputModeSwitchKey
        idleView.setPrimaryAction(isInApp: isInAppMode || pathAFailed)
        idleView.setScanInAppVisible(!isInAppMode && pathAFailed)

        if !hasFullAccess {
            // Without Full Access the extension gets neither the camera nor the App
            // Group, so there is nothing useful to do but explain the fix.
            idleView.setScanEnabled(false)
            idleView.setStatus("Full Access is off.\n\(AppConstants.fullAccessPath)", isError: true)
            return
        }

        idleView.setScanEnabled(true)

        switch CameraController.authorizationStatus {
        case .denied, .restricted:
            idleView.setStatus("Camera access is off. Settings > \(AppConstants.displayName) > Camera.",
                               isError: true)
        default:
            let preset = settings.validationPreset
            if preset.isActive {
                idleView.setStatus("Filter: \(preset.name)", isError: false)
            } else {
                idleView.setStatus(nil, isError: false)
            }
        }
    }

    private func showIdleStatus(_ text: String, isError: Bool, resetAfter seconds: TimeInterval = 3) {
        statusResetWorkItem?.cancel()
        idleView.setStatus(text, isError: isError)

        let work = DispatchWorkItem { [weak self] in self?.refreshIdleState() }
        statusResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Path A: scanning inside the keyboard

    private func startScanning() {
        guard hasFullAccess else {
            idleView.shake()
            refreshIdleState()
            return
        }

        switch CameraController.authorizationStatus {
        case .denied, .restricted:
            idleView.shake()
            showIdleStatus("Camera access is off. Enable it in Settings > \(AppConstants.displayName).",
                           isError: true, resetAfter: 5)
            return
        default:
            break
        }

        batchCount = 0
        mode = .scanning
        idleView.isHidden = true
        scannerView.isHidden = false
        scannerView.setMessage(nil, isError: false)
        scannerView.setCounter(settings.batchMode ? 0 : nil)
        applyHeight(animated: true)
        Feedback.selection()

        let controller = CameraController(quality: .low,
                                          objectTypes: settings.enabledMetadataObjectTypes)
        controller.delegate = self
        // Attach whenever the layer appears - which may be after an async permission
        // prompt rather than synchronously inside start().
        // Weak on both sides: the closure is stored *on* the controller, so a strong
        // capture of either would leak the capture session.
        controller.onPreviewLayerReady = { [weak self, weak controller] layer in
            guard let self, self.mode == .scanning else { return }
            self.scannerView.attach(previewLayer: layer)
            self.scannerView.setTorchOn(false,
                                        available: controller?.isTorchAvailable ?? false)
        }
        camera = controller
        controller.start()
    }

    private func stopScanning(returningToIdle: Bool, animated: Bool) {
        guard mode == .scanning || camera != nil else { return }

        camera?.setTorch(on: false)
        camera?.stop()
        camera = nil
        scannerView.detachPreviewLayer()

        guard returningToIdle else { return }
        mode = .idle
        scannerView.isHidden = true
        idleView.isHidden = false
        applyHeight(animated: animated)
        refreshIdleState()
    }

    // MARK: - Path B: scanning in the containing app

    private func launchContainingAppScanner() {
        guard hasFullAccess else {
            idleView.shake()
            refreshIdleState()
            return
        }
        guard openURLFromExtension(AppConstants.scanURL) else {
            showIdleStatus("Could not open \(AppConstants.displayName). Open it from the Home Screen and scan there.",
                           isError: true, resetAfter: 5)
            return
        }
        showIdleStatus("Scan in \(AppConstants.displayName), then come back here.", isError: false, resetAfter: 8)
    }

    /// Keyboard extensions cannot call `UIApplication.shared.open` (it is unavailable in
    /// app extensions) and `extensionContext.open` is not supported for the keyboard
    /// extension point. Walking the responder chain to whoever implements `openURL:` is
    /// the long-standing workaround and uses only public API.
    @discardableResult
    private func openURLFromExtension(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    /// Reads (and clears) any fresh scan the containing app left in the App Group.
    ///
    /// No "already checked" flag is needed: `consume()` deletes the payload as it reads
    /// it, so a given handoff can only ever be returned once, no matter how often this
    /// is called. That also means a second Path B round trip works even if the keyboard
    /// never went through a full disappear/appear cycle in between.
    private func consumePendingHandoffIfNeeded() {
        guard hasFullAccess else { return }
        guard let handoff = ScanHandoffStore.consume() else { return }
        handleDecoded(raw: handoff.raw, symbology: handoff.symbology, fromKeyboardCamera: false)
    }

    // MARK: - Decoding and insertion

    private func handleDecoded(raw: String,
                               symbology: BarcodeSymbology?,
                               fromKeyboardCamera: Bool) {
        let outcome = ScanPostProcessor.process(raw: raw,
                                                symbology: symbology,
                                                config: settings.pipelineConfiguration)

        switch outcome {
        case .accepted(_, let textToInsert):
            insert(textToInsert, fromKeyboardCamera: fromKeyboardCamera)

        case .rejected(let rejection):
            Feedback.rejection(beep: settings.beepOnScan, haptic: settings.hapticOnScan)
            if fromKeyboardCamera {
                scannerView.shake()
                scannerView.setMessage(rejection.message, isError: true)
                // Let the same code be re-read after the user repositions.
                camera?.resetDebounce()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard self?.mode == .scanning else { return }
                    self?.scannerView.setMessage(nil, isError: false)
                }
            } else {
                idleView.shake()
                showIdleStatus(rejection.message, isError: true, resetAfter: 4)
            }
        }
    }

    private func insert(_ text: String, fromKeyboardCamera: Bool) {
        textDocumentProxy.insertText(text)
        Feedback.success(beep: settings.beepOnScan, haptic: settings.hapticOnScan)

        guard fromKeyboardCamera else {
            showIdleStatus("Inserted", isError: false, resetAfter: 2)
            return
        }

        // Freeze the preview during the confirmation flash so a second decode of the
        // same barcode cannot slip through mid-animation.
        camera?.isPaused = true

        if settings.batchMode {
            batchCount += 1
            scannerView.setCounter(batchCount)
            scannerView.flashSuccess { [weak self] in
                guard let self, self.mode == .scanning else { return }
                self.camera?.isPaused = false
            }
        } else {
            scannerView.flashSuccess { [weak self] in
                guard let self else { return }
                self.stopScanning(returningToIdle: true, animated: true)
                self.showIdleStatus("Inserted", isError: false, resetAfter: 2)
            }
        }
    }
}

// MARK: - Key click audio

/// `UIDevice.playInputClick()` is silent unless the visible input view opts in. This is
/// the sanctioned way for a custom keyboard to produce the standard key-click sound,
/// and it still respects the user's system "Keyboard Clicks" setting.
///
/// This is a retroactive conformance: we are declaring a UIKit type's conformance to a
/// UIKit protocol, which Apple could in principle declare themselves one day. There is
/// no alternative - the conformance has to be on the actual visible input view, which
/// the system owns. `@retroactive` acknowledges it explicitly on Swift 6 toolchains and
/// silences the warning; the `#if` keeps the file compiling on Swift 5 ones.
#if compiler(>=6.0)
extension UIInputView: @retroactive UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
#else
extension UIInputView: UIInputViewAudioFeedback {
    public var enableInputClicksWhenVisible: Bool { true }
}
#endif

// MARK: - KeyboardIdleViewDelegate

extension KeyboardViewController: KeyboardIdleViewDelegate {

    func idleViewDidTapScan(_ view: KeyboardIdleView) {
        if settings.scanMode == .inApp || pathAFailed {
            launchContainingAppScanner()
        } else {
            startScanning()
        }
    }

    func idleViewDidTapScanInApp(_ view: KeyboardIdleView) {
        launchContainingAppScanner()
    }

    func idleViewDidTapDelete(_ view: KeyboardIdleView) {
        textDocumentProxy.deleteBackward()
    }

    func idleViewDidTapReturn(_ view: KeyboardIdleView) {
        textDocumentProxy.insertText("\n")
    }
}

// MARK: - KeyboardScannerViewDelegate

extension KeyboardViewController: KeyboardScannerViewDelegate {

    func scannerViewDidTapCancel(_ view: KeyboardScannerView) {
        Feedback.keyTap()
        stopScanning(returningToIdle: true, animated: true)
    }

    func scannerViewDidTapTorch(_ view: KeyboardScannerView) {
        guard let camera else { return }
        camera.toggleTorch()
        view.setTorchOn(camera.isTorchOn, available: camera.isTorchAvailable)
    }

    func scannerView(_ view: KeyboardScannerView, didTapToFocusAt point: CGPoint) {
        camera?.focus(atPreviewPoint: point)
    }
}

// MARK: - CameraControllerDelegate

extension KeyboardViewController: CameraControllerDelegate {

    func cameraController(_ controller: CameraController,
                          didDecode value: String,
                          symbology: BarcodeSymbology?) {
        guard mode == .scanning else { return }
        handleDecoded(raw: value, symbology: symbology, fromKeyboardCamera: true)
    }

    func cameraController(_ controller: CameraController,
                          didFailWith failure: CameraController.Failure) {
        // Path A is not viable here. Fall back to Path B for the rest of the session.
        switch failure {
        case .noCamera, .configurationFailed:
            pathAFailed = true
        case .permissionDenied, .permissionUndetermined:
            break
        }

        stopScanning(returningToIdle: true, animated: true)

        let suffix = pathAFailed ? " Use Scan in app instead." : ""
        showIdleStatus(failure.message + suffix, isError: true, resetAfter: 6)
    }
}
