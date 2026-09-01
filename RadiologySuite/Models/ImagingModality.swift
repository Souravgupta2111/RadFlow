import Foundation

/// Single source of truth for the imaging modalities used across the app.
/// Views and filters derive their options from this catalog instead of
/// hard-coding modality strings.
enum ImagingModality: String, CaseIterable, Codable, Identifiable, Hashable {
    case xr = "XR"
    case ct = "CT"
    case mr = "MR"
    case us = "US"
    case nm = "NM"
    case fl = "FL"
    case mg = "MG"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xr: return "X-Ray"
        case .ct: return "CT Scan"
        case .mr: return "MRI"
        case .us: return "Ultrasound"
        case .nm: return "Nuclear Medicine"
        case .fl: return "Fluoroscopy"
        case .mg: return "Mammography"
        }
    }

    var symbol: String {
        switch self {
        case .xr: return "rays"
        case .ct: return "circle.grid.cross"
        case .mr: return "wave.3.right"
        case .us: return "dot.radiowaves.left.and.right"
        case .nm: return "atom"
        case .fl: return "camera.viewfinder"
        case .mg: return "rectangle.compress.vertical"
        }
    }
}
