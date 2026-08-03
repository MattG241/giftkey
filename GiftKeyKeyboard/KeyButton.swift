//
//  KeyButton.swift
//  GiftKeyKeyboard
//
//  Keyboard key styling. Deliberately large and high-contrast: this is used one-handed,
//  at speed, by staff behind a counter.
//

import UIKit

final class KeyButton: UIButton {

    enum Style {
        /// The big blue call-to-action.
        case primary
        /// Standard light key (globe, return).
        case standard
        /// Darker utility key (delete).
        case utility
        /// Transparent, text only.
        case plain
    }

    private let style: Style

    /// Fires repeatedly while the key is held. Used by delete.
    var repeatsOnHold = false
    private var repeatTimer: Timer?

    init(style: Style,
         title: String? = nil,
         systemImage: String? = nil,
         accessibilityLabel: String? = nil) {
        self.style = style
        super.init(frame: .zero)

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.title = title
        if let systemImage {
            config.image = UIImage(systemName: systemImage)
            config.imagePlacement = .leading
            config.imagePadding = 8
        }
        config.baseBackgroundColor = Self.backgroundColor(for: style)
        config.baseForegroundColor = Self.foregroundColor(for: style)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = Self.font(for: style)
            return outgoing
        }
        config.preferredSymbolConfigurationForImage =
            UIImage.SymbolConfiguration(pointSize: style == .primary ? 22 : 17,
                                        weight: .semibold)
        configuration = config

        self.accessibilityLabel = accessibilityLabel ?? title
        layer.cornerCurve = .continuous
        addTarget(self, action: #selector(handleTouchDown), for: .touchDown)
        addTarget(self, action: #selector(handleTouchUp),
                  for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Appearance

    private static func backgroundColor(for style: Style) -> UIColor {
        switch style {
        case .primary:
            return .systemBlue
        case .standard:
            return UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(white: 0.28, alpha: 1)
                : .white }
        case .utility:
            return UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(white: 0.18, alpha: 1)
                : UIColor(white: 0.72, alpha: 1) }
        case .plain:
            return .clear
        }
    }

    private static func foregroundColor(for style: Style) -> UIColor {
        switch style {
        case .primary: return .white
        case .plain:   return .secondaryLabel
        default:       return .label
        }
    }

    private static func font(for style: Style) -> UIFont {
        switch style {
        case .primary: return .systemFont(ofSize: 22, weight: .semibold)
        case .plain:   return .systemFont(ofSize: 12, weight: .regular)
        default:       return .systemFont(ofSize: 17, weight: .medium)
        }
    }

    // MARK: - Press handling

    @objc private func handleTouchDown() {
        Feedback.keyTap()
        guard repeatsOnHold else { return }
        // Match the system keyboard: pause, then repeat.
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer?.invalidate()
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.sendActions(for: .primaryActionTriggered)
            }
        }
    }

    @objc private func handleTouchUp() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }

    deinit {
        repeatTimer?.invalidate()
    }
}
