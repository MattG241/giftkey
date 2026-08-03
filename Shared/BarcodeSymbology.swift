//
//  BarcodeSymbology.swift
//  Shared
//
//  The barcode types GiftKey can read, mapped onto AVFoundation metadata object
//  types. Each symbology is individually toggleable in Settings; all default to on.
//

import AVFoundation
import Foundation

enum BarcodeSymbology: String, CaseIterable, Identifiable, Codable {
    case code128
    case code39
    case code93
    case ean13
    case ean8
    case upce
    case itf14
    case interleaved2of5
    case codabar
    case qr
    case dataMatrix
    case pdf417
    case aztec

    var id: String { rawValue }

    /// Human label used in Settings.
    var displayName: String {
        switch self {
        case .code128:         return "Code 128"
        case .code39:          return "Code 39"
        case .code93:          return "Code 93"
        case .ean13:           return "EAN-13 / UPC-A"
        case .ean8:            return "EAN-8"
        case .upce:            return "UPC-E"
        case .itf14:           return "ITF-14"
        case .interleaved2of5: return "Interleaved 2 of 5"
        case .codabar:         return "Codabar"
        case .qr:              return "QR"
        case .dataMatrix:      return "Data Matrix"
        case .pdf417:          return "PDF417"
        case .aztec:           return "Aztec"
        }
    }

    /// Short note shown under the toggle to help retail staff decide.
    var hint: String {
        switch self {
        case .code128:         return "Most third-party gift cards"
        case .ean13:           return "Retail product barcodes"
        default:               return ""
        }
    }

    var metadataObjectType: AVMetadataObject.ObjectType {
        switch self {
        case .code128:         return .code128
        case .code39:          return .code39
        case .code93:          return .code93
        case .ean13:           return .ean13
        case .ean8:            return .ean8
        case .upce:            return .upce
        case .itf14:           return .itf14
        case .interleaved2of5: return .interleaved2of5
        case .codabar:         return .codabar
        case .qr:              return .qr
        case .dataMatrix:      return .dataMatrix
        case .pdf417:          return .pdf417
        case .aztec:           return .aztec
        }
    }

    init?(metadataObjectType: AVMetadataObject.ObjectType) {
        guard let match = BarcodeSymbology.allCases.first(where: {
            $0.metadataObjectType == metadataObjectType
        }) else { return nil }
        self = match
    }

    /// EAN/UPC family - the only symbologies where a trailing check digit is part
    /// of the decoded payload and stripping it is meaningful.
    var isEANUPCFamily: Bool {
        switch self {
        case .ean13, .ean8, .upce: return true
        default:                   return false
        }
    }
}
