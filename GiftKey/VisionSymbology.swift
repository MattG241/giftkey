//
//  VisionSymbology.swift
//  GiftKey (containing app only)
//
//  Bridges BarcodeSymbology to Vision/VisionKit. Deliberately NOT in Shared: the
//  keyboard extension has no reason to link Vision, and every framework the extension
//  loads eats into its ~60-70 MB ceiling.
//

import Vision

extension BarcodeSymbology {

    var visionSymbology: VNBarcodeSymbology {
        switch self {
        case .code128:         return .code128
        case .code39:          return .code39
        case .code93:          return .code93
        case .ean13:           return .ean13
        case .ean8:            return .ean8
        case .upce:            return .upce
        case .itf14:           return .itf14
        case .interleaved2of5: return .i2of5
        case .codabar:         return .codabar
        case .qr:              return .qr
        case .dataMatrix:      return .dataMatrix
        case .pdf417:          return .pdf417
        case .aztec:           return .aztec
        }
    }

    init?(visionSymbology: VNBarcodeSymbology) {
        // i2of5Checksum and upce variants collapse onto the nearest case we model.
        switch visionSymbology {
        case .code128:                 self = .code128
        case .code39, .code39Checksum,
             .code39FullASCII,
             .code39FullASCIIChecksum: self = .code39
        case .code93, .code93i:        self = .code93
        case .ean13:                   self = .ean13
        case .ean8:                    self = .ean8
        case .upce:                    self = .upce
        case .itf14:                   self = .itf14
        case .i2of5, .i2of5Checksum:   self = .interleaved2of5
        case .codabar:                 self = .codabar
        case .qr:                      self = .qr
        case .dataMatrix:              self = .dataMatrix
        case .pdf417:                  self = .pdf417
        case .aztec:                   self = .aztec
        default:                       return nil
        }
    }
}

extension SettingsStore {
    /// Symbologies to hand to DataScannerViewController.
    var enabledVisionSymbologies: [VNBarcodeSymbology] {
        let enabled = enabledSymbologies
        let source = enabled.isEmpty ? Set(BarcodeSymbology.allCases) : enabled
        return source.map(\.visionSymbology)
    }
}
