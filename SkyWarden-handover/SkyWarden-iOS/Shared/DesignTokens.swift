// SkyWarden — Design Tokens
// Coastal Australian sky palette

import SwiftUI

enum Sky {
    // Backgrounds
    static let navy    = Color(hex: "0B1929")   // deepest background
    static let ink     = Color(hex: "0F2740")   // nav bar
    static let surface = Color(hex: "132D4A")   // elevated surface
    static let card    = Color(hex: "1A3A5C")   // card background

    // Text
    static let white   = Color(hex: "F0F8FF")   // primary text
    static let text    = Color(hex: "C9E0F0")   // secondary text
    static let muted   = Color(hex: "7BA7C4")   // tertiary / labels
    static let horizon = Color(hex: "E8F4FD")   // near-white accents

    // Semantic
    static let amber   = Color(hex: "F5A623")   // disagreement warning
    static let amberBg = Color(hex: "3D2800")   // disagreement panel bg
    static let green   = Color(hex: "3DD68C")   // high consensus
    static let greenBg = Color(hex: "0D3325")   // consensus panel bg
    static let red     = Color(hex: "E05555")   // major disagreement

    // Data layers
    static let rain    = Color(hex: "5BA3D4")   // precipitation
    static let tide    = Color(hex: "4ECDC4")   // tide data
    static let moon    = Color(hex: "D4C47A")   // moon data
    static let uv      = Color(hex: "FF8C61")   // UV index
    static let wind    = Color(hex: "A78BFA")   // wind (comfort dial)
    static let astro   = Color(hex: "C084FC")   // astronomical events

    // Source identity colours
    static let sourceOM  = Color(hex: "5BA3D4")   // Open-Meteo
    static let sourceOW  = Color(hex: "F5A623")   // OpenWeatherMap
    static let sourceBOM = Color(hex: "3DD68C")   // BOM

    // Confidence thresholds
    static func confidenceColor(_ score: Double) -> Color {
        switch score {
        case 0.8...: return green
        case 0.5..<0.8: return amber
        default: return red
        }
    }
}

// MARK: - Color from hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Typography scale
enum SkyType {
    static let heroTemp    = Font.system(size: 80, weight: .ultraLight, design: .rounded)
    static let largeTemp   = Font.system(size: 52, weight: .thin, design: .rounded)
    static let mediumTemp  = Font.system(size: 32, weight: .light, design: .rounded)
    static let smallTemp   = Font.system(size: 20, weight: .regular, design: .rounded)
    static let sectionHead = Font.system(size: 11, weight: .semibold, design: .default)
    static let body        = Font.system(size: 14, weight: .regular, design: .default)
    static let caption     = Font.system(size: 12, weight: .regular, design: .default)
    static let micro       = Font.system(size: 10, weight: .medium, design: .default)
}
