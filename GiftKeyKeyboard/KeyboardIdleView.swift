//
//  KeyboardIdleView.swift
//  GiftKeyKeyboard
//
//  The keyboard's default (not-scanning) state. One huge Scan button, the standard
//  keyboard utility keys, and a status line.
//

import UIKit

protocol KeyboardIdleViewDelegate: AnyObject {
    func idleViewDidTapScan(_ view: KeyboardIdleView)
    func idleViewDidTapScanInApp(_ view: KeyboardIdleView)
    func idleViewDidTapDelete(_ view: KeyboardIdleView)
    func idleViewDidTapReturn(_ view: KeyboardIdleView)
}

final class KeyboardIdleView: UIView {

    weak var delegate: KeyboardIdleViewDelegate?

    private let scanButton: KeyButton
    private let scanInAppButton: KeyButton
    private let globeButton: KeyButton
    private let deleteButton: KeyButton
    private let returnButton: KeyButton
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()

    private let utilityRow = UIStackView()
    private var scanInAppIsVisible = false

    /// The globe key is only legal to hide when the system says so.
    var showsGlobeKey: Bool = true {
        didSet { globeButton.isHidden = !showsGlobeKey }
    }

    init(globeTarget: Any?, globeAction: Selector) {
        scanButton = KeyButton(style: .primary,
                               title: "Scan",
                               systemImage: "barcode.viewfinder",
                               accessibilityLabel: "Scan barcode")
        scanInAppButton = KeyButton(style: .standard,
                                    title: "Scan in app",
                                    systemImage: "arrow.up.forward.app")
        globeButton = KeyButton(style: .standard,
                                systemImage: "globe",
                                accessibilityLabel: "Next keyboard")
        deleteButton = KeyButton(style: .utility,
                                 systemImage: "delete.left",
                                 accessibilityLabel: "Delete")
        returnButton = KeyButton(style: .standard,
                                 title: "return",
                                 accessibilityLabel: "Return")
        super.init(frame: .zero)

        deleteButton.repeatsOnHold = true

        // The globe key must be wired to the system-provided
        // `handleInputModeList(from:with:)` so the long-press keyboard picker works.
        globeButton.addTarget(globeTarget, action: globeAction, for: .allTouchEvents)

        scanButton.addTarget(self, action: #selector(tapScan), for: .touchUpInside)
        scanInAppButton.addTarget(self, action: #selector(tapScanInApp), for: .touchUpInside)
        // .primaryActionTriggered only. UIButton already raises it on touchUpInside, and
        // KeyButton's hold-to-repeat timer raises it too - registering for both would
        // delete two characters per tap.
        deleteButton.addTarget(self, action: #selector(tapDelete), for: .primaryActionTriggered)
        returnButton.addTarget(self, action: #selector(tapReturn), for: .touchUpInside)

        buildLayout()
        setStatus(nil, isError: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    private func buildLayout() {
        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 3
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.75

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 1
        hintLabel.text = "Open \(AppConstants.displayName) to change settings"

        scanInAppButton.isHidden = true

        utilityRow.axis = .horizontal
        utilityRow.distribution = .fillEqually
        utilityRow.spacing = 8
        [globeButton, deleteButton, returnButton].forEach(utilityRow.addArrangedSubview)

        let stack = UIStackView(arrangedSubviews: [
            statusLabel,
            scanButton,
            scanInAppButton,
            utilityRow,
            hintLabel,
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),

            utilityRow.heightAnchor.constraint(equalToConstant: 46),
            scanInAppButton.heightAnchor.constraint(equalToConstant: 46),
        ])

        // The Scan button soaks up whatever vertical space is left.
        scanButton.setContentHuggingPriority(.defaultLow, for: .vertical)
        scanButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
    }

    // MARK: - State

    /// Shows or hides the Path B escape hatch.
    func setScanInAppVisible(_ visible: Bool) {
        scanInAppIsVisible = visible
        scanInAppButton.isHidden = !visible
    }

    /// Swaps the primary button between Path A and Path B behaviour.
    func setPrimaryAction(isInApp: Bool) {
        var config = scanButton.configuration
        config?.title = isInApp ? "Scan in app" : "Scan"
        config?.image = UIImage(systemName: isInApp ? "arrow.up.forward.app" : "barcode.viewfinder")
        scanButton.configuration = config
        scanButton.accessibilityLabel = isInApp ? "Scan in app" : "Scan barcode"
    }

    /// `nil` clears the line. Errors render in red.
    func setStatus(_ text: String?, isError: Bool) {
        statusLabel.text = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabel
        statusLabel.isHidden = (text == nil)
    }

    func setScanEnabled(_ enabled: Bool) {
        scanButton.isEnabled = enabled
        scanButton.alpha = enabled ? 1 : 0.5
    }

    /// Rejection feedback: a short horizontal shake on the status line and Scan button.
    func shake() {
        for target in [statusLabel, scanButton] as [UIView] {
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, -10, 9, -7, 5, -3, 0]
            animation.duration = 0.4
            animation.isAdditive = true
            target.layer.add(animation, forKey: "shake")
        }
    }

    // MARK: - Actions

    @objc private func tapScan() {
        delegate?.idleViewDidTapScan(self)
    }

    @objc private func tapScanInApp() {
        delegate?.idleViewDidTapScanInApp(self)
    }

    @objc private func tapDelete() {
        delegate?.idleViewDidTapDelete(self)
    }

    @objc private func tapReturn() {
        delegate?.idleViewDidTapReturn(self)
    }
}
