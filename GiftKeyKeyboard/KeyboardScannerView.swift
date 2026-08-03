//
//  KeyboardScannerView.swift
//  GiftKeyKeyboard
//
//  The in-keyboard live camera view (Path A). Hosts the preview layer, draws the
//  targeting reticle, and offers torch / cancel / batch counter controls.
//
//  This view never touches AVCaptureSession itself - the controller owns that - so the
//  session can be torn down independently of the view hierarchy.
//

import AVFoundation
import UIKit

protocol KeyboardScannerViewDelegate: AnyObject {
    func scannerViewDidTapCancel(_ view: KeyboardScannerView)
    func scannerViewDidTapTorch(_ view: KeyboardScannerView)
    func scannerView(_ view: KeyboardScannerView, didTapToFocusAt point: CGPoint)
}

final class KeyboardScannerView: UIView {

    weak var delegate: KeyboardScannerViewDelegate?

    private let previewContainer = UIView()
    private let dimmingLayer = CAShapeLayer()
    private let reticleLayer = CAShapeLayer()
    private let successOverlay = UIView()
    private let focusIndicator = UIView()

    private let cancelButton = KeyButton(style: .standard,
                                         title: "Cancel",
                                         accessibilityLabel: "Cancel scanning")
    private let torchButton = KeyButton(style: .standard,
                                        systemImage: "flashlight.off.fill",
                                        accessibilityLabel: "Torch")
    private let counterLabel = UILabel()
    private let messageLabel = UILabel()

    private var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    private func buildLayout() {
        previewContainer.backgroundColor = .black
        previewContainer.layer.cornerRadius = 10
        previewContainer.layer.cornerCurve = .continuous
        previewContainer.clipsToBounds = true
        previewContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(previewContainer)

        dimmingLayer.fillRule = .evenOdd
        dimmingLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        previewContainer.layer.addSublayer(dimmingLayer)

        reticleLayer.fillColor = UIColor.clear.cgColor
        reticleLayer.strokeColor = UIColor.systemYellow.cgColor
        reticleLayer.lineWidth = 2
        reticleLayer.lineCap = .round
        previewContainer.layer.addSublayer(reticleLayer)

        successOverlay.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.35)
        successOverlay.alpha = 0
        successOverlay.isUserInteractionEnabled = false
        successOverlay.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(successOverlay)

        focusIndicator.layer.borderColor = UIColor.systemYellow.cgColor
        focusIndicator.layer.borderWidth = 1.5
        focusIndicator.layer.cornerRadius = 4
        focusIndicator.alpha = 0
        focusIndicator.isUserInteractionEnabled = false
        focusIndicator.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        previewContainer.addSubview(focusIndicator)

        messageLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.layer.shadowOpacity = 0.8
        messageLabel.layer.shadowRadius = 3
        messageLabel.layer.shadowOffset = .zero
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        previewContainer.addSubview(messageLabel)

        counterLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        counterLabel.textColor = .secondaryLabel
        counterLabel.textAlignment = .center
        counterLabel.isHidden = true

        torchButton.addTarget(self, action: #selector(tapTorch), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)

        let controls = UIStackView(arrangedSubviews: [torchButton, counterLabel, cancelButton])
        controls.axis = .horizontal
        controls.spacing = 8
        controls.distribution = .fillEqually
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controls)

        NSLayoutConstraint.activate([
            previewContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            previewContainer.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 8),
            previewContainer.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -8),

            controls.topAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),
            controls.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -6),
            controls.heightAnchor.constraint(equalToConstant: 44),

            successOverlay.topAnchor.constraint(equalTo: previewContainer.topAnchor),
            successOverlay.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor),
            successOverlay.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor),
            successOverlay.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: previewContainer.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: previewContainer.trailingAnchor, constant: -12),
            messageLabel.bottomAnchor.constraint(equalTo: previewContainer.bottomAnchor, constant: -10),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        previewContainer.addGestureRecognizer(tap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Keep CALayer geometry in sync without implicit animations.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer?.frame = previewContainer.bounds
        previewLayer?.connection?.videoOrientation = currentVideoOrientation()

        let bounds = previewContainer.bounds
        let reticle = reticleRect(in: bounds)

        let path = UIBezierPath(rect: bounds)
        path.append(UIBezierPath(roundedRect: reticle, cornerRadius: 8))
        dimmingLayer.frame = bounds
        dimmingLayer.path = path.cgPath

        reticleLayer.frame = bounds
        reticleLayer.path = cornerBracketPath(for: reticle).cgPath

        CATransaction.commit()
    }

    /// A wide, short window - 1D retail barcodes are much wider than they are tall.
    private func reticleRect(in bounds: CGRect) -> CGRect {
        let width = bounds.width * 0.82
        let height = min(bounds.height * 0.55, width * 0.45)
        return CGRect(x: bounds.midX - width / 2,
                      y: bounds.midY - height / 2,
                      width: width,
                      height: height)
    }

    /// Four corner brackets rather than a full rectangle - reads as a target, and does
    /// not visually compete with the barcode itself.
    private func cornerBracketPath(for rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let length = min(rect.width, rect.height) * 0.22

        // Top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        // Top-right
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        // Bottom-right
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        // Bottom-left
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }

    private func currentVideoOrientation() -> AVCaptureVideoOrientation {
        guard let orientation = window?.windowScene?.interfaceOrientation else {
            return .portrait
        }
        switch orientation {
        case .landscapeLeft:      return .landscapeLeft
        case .landscapeRight:     return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default:                  return .portrait
        }
    }

    // MARK: - Preview layer

    func attach(previewLayer layer: AVCaptureVideoPreviewLayer) {
        detachPreviewLayer()
        previewLayer = layer
        layer.frame = previewContainer.bounds
        // Insert below the dimming/reticle layers so the reticle stays on top.
        previewContainer.layer.insertSublayer(layer, at: 0)
        setNeedsLayout()
    }

    /// Removes the preview layer so nothing keeps the capture session alive.
    func detachPreviewLayer() {
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    // MARK: - State

    func setTorchOn(_ on: Bool, available: Bool) {
        torchButton.isEnabled = available
        torchButton.alpha = available ? 1 : 0.4
        var config = torchButton.configuration
        config?.image = UIImage(systemName: on ? "flashlight.on.fill" : "flashlight.off.fill")
        config?.baseForegroundColor = on ? .systemYellow : .label
        torchButton.configuration = config
    }

    /// Batch-mode counter. Pass nil to hide.
    func setCounter(_ count: Int?) {
        guard let count else {
            counterLabel.isHidden = true
            return
        }
        counterLabel.isHidden = false
        counterLabel.text = "\(count) scanned"
    }

    /// Transient message drawn over the preview (e.g. the rejection reason).
    func setMessage(_ text: String?, isError: Bool) {
        messageLabel.text = text
        messageLabel.textColor = isError ? .systemRed : .white
        messageLabel.isHidden = (text == nil)
    }

    // MARK: - Feedback

    /// Brief green flash acting as the "frozen frame" confirmation.
    func flashSuccess(completion: @escaping () -> Void) {
        successOverlay.alpha = 0
        UIView.animate(withDuration: 0.08, animations: {
            self.successOverlay.alpha = 1
        }, completion: { _ in
            UIView.animate(withDuration: 0.22, delay: 0.12, options: [], animations: {
                self.successOverlay.alpha = 0
            }, completion: { _ in
                completion()
            })
        })
    }

    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -12, 10, -8, 6, -3, 0]
        animation.duration = 0.4
        animation.isAdditive = true
        previewContainer.layer.add(animation, forKey: "shake")
    }

    // MARK: - Actions

    @objc private func tapTorch() {
        delegate?.scannerViewDidTapTorch(self)
    }

    @objc private func tapCancel() {
        delegate?.scannerViewDidTapCancel(self)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewContainer)
        showFocusIndicator(at: point)
        delegate?.scannerView(self, didTapToFocusAt: point)
    }

    private func showFocusIndicator(at point: CGPoint) {
        focusIndicator.center = point
        focusIndicator.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
        focusIndicator.alpha = 1
        UIView.animate(withDuration: 0.25, animations: {
            self.focusIndicator.transform = .identity
        }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 0.4, options: [], animations: {
                self.focusIndicator.alpha = 0
            })
        })
    }
}
