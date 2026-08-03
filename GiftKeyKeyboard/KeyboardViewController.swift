//
//  KeyboardViewController.swift
//  GiftKeyKeyboard
//
//  The keyboard extension's principal class.
//
//  WHY THERE IS NO CAMERA IN HERE
//  ------------------------------
//  iOS does not allow a keyboard extension to use the camera. This is not a permission
//  or a Full Access gate - it is a platform restriction. Apple, on the developer forums:
//
//      "the camera is still not available to keyboard extensions. The only extension
//       you can use the camera from is an iMessage Extension."
//       https://developer.apple.com/forums/thread/681975
//
//  An AVCaptureSession here configures perfectly and then simply never runs, which
//  presents as a black preview. Every camera-based keyboard wedge on iOS works the same
//  way this one does: the keyboard opens its containing app, the app scans, and the
//  result comes back through the App Group. (The keyboard wedges that appear to scan
//  in place - Cognex, Honeywell, CodeCorp - are paired with Bluetooth hardware scanners,
//  not a camera.)
//
//  So this class is deliberately small. It types, it deletes, it opens the app, and it
//  picks up the result. No capture session, no preview, no frame handling - which also
//  means the ~60-70 MB extension memory ceiling stops being a design constraint.
//

import UIKit

final class KeyboardViewController: UIInputViewController {

    private let settings = SettingsStore()

    private var idleView: KeyboardIdleView!
    private var heightConstraint: NSLayoutConstraint?
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

        NSLayoutConstraint.activate([
            idleView.topAnchor.constraint(equalTo: view.topAnchor),
            idleView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            idleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            idleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyHeight()
        refreshIdleState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // A scan may have been produced by the app while we were away.
        consumePendingHandoffIfNeeded()
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in self.applyHeight() })
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // Also covers the case where the keyboard is already on screen when the user
        // switches back from the app.
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

    /// Keyboards pick their own height. Without a camera preview to accommodate this can
    /// stay close to a standard keyboard.
    private func applyHeight() {
        let screen = view.window?.screen.bounds ?? UIScreen.main.bounds
        let isLandscape = screen.width > screen.height
        let target: CGFloat = isLandscape ? 180 : 240
        let clamped = min(target, screen.height * 0.55)

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
        view.layoutIfNeeded()
    }

    // MARK: - Idle state

    private func refreshIdleState() {
        idleView.showsGlobeKey = needsInputModeSwitchKey

        guard hasFullAccess else {
            // Without Full Access the extension can reach neither the App Group nor the
            // containing app, so there is nothing useful to do but explain the fix.
            idleView.setScanEnabled(false)
            idleView.setStatus("Full Access is off.\n\(AppConstants.fullAccessPath)", isError: true)
            return
        }

        idleView.setScanEnabled(true)

        let preset = settings.validationPreset
        idleView.setStatus(preset.isActive ? "Filter: \(preset.name)" : nil, isError: false)
    }

    private func showIdleStatus(_ text: String, isError: Bool, resetAfter seconds: TimeInterval = 3) {
        statusResetWorkItem?.cancel()
        idleView.setStatus(text, isError: isError)

        let work = DispatchWorkItem { [weak self] in self?.refreshIdleState() }
        statusResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - Opening the app to scan

    private func launchScanner() {
        guard hasFullAccess else {
            idleView.shake()
            refreshIdleState()
            return
        }
        guard openURLFromExtension(AppConstants.scanURL) else {
            showIdleStatus("Could not open \(AppConstants.displayName). Open it from the Home Screen and scan there.",
                           isError: true, resetAfter: 6)
            return
        }
        showIdleStatus("Scan, then tap the back arrow at the top of the screen.",
                       isError: false, resetAfter: 10)
    }

    /// Keyboard extensions cannot call `UIApplication.shared.open` (unavailable in app
    /// extensions) and `extensionContext.open` is not supported for the keyboard
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

    // MARK: - Consuming the result

    /// Reads (and clears) any fresh scan the app left in the App Group.
    ///
    /// No "already checked" flag is needed: `consume()` deletes the payload as it reads
    /// it, so a given handoff can only ever be returned once no matter how often this is
    /// called. That also means a second round trip works even if the keyboard never went
    /// through a full disappear/appear cycle in between.
    private func consumePendingHandoffIfNeeded() {
        guard hasFullAccess else { return }
        guard let handoff = ScanHandoffStore.consume() else { return }

        let config = settings.pipelineConfiguration
        var inserted = 0
        var lastRejection: ScanRejection?

        for item in handoff.items {
            switch ScanPostProcessor.process(raw: item.raw,
                                             symbology: item.symbology,
                                             config: config) {
            case .accepted(_, let text):
                textDocumentProxy.insertText(text)
                inserted += 1
            case .rejected(let rejection):
                lastRejection = rejection
            }
        }

        if inserted > 0 {
            Feedback.success(beep: settings.beepOnScan, haptic: settings.hapticOnScan)
            let noun = inserted == 1 ? "code" : "codes"
            showIdleStatus("Inserted \(inserted) \(noun)", isError: false, resetAfter: 2)
        }

        if let lastRejection, inserted == 0 {
            Feedback.rejection(beep: settings.beepOnScan, haptic: settings.hapticOnScan)
            idleView.shake()
            showIdleStatus(lastRejection.message, isError: true, resetAfter: 5)
        }
    }
}

// MARK: - Key click audio

/// `UIDevice.playInputClick()` is silent unless the visible input view opts in. This is
/// the sanctioned way for a custom keyboard to produce the standard key-click sound, and
/// it still respects the user's system "Keyboard Clicks" setting.
///
/// A retroactive conformance, unavoidably: the conformance has to be on the actual
/// visible input view, which the system owns.
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
        launchScanner()
    }

    func idleViewDidTapDelete(_ view: KeyboardIdleView) {
        textDocumentProxy.deleteBackward()
    }

    func idleViewDidTapReturn(_ view: KeyboardIdleView) {
        textDocumentProxy.insertText("\n")
    }
}
