import Foundation
import SwiftUI

public struct BriefPalette: Sendable {
    public let name, ground, glow1, glow2, accent: String
    public static let defaults: [BriefPalette] = [
        .init(name: "Forest", ground: "1C2A19", glow1: "46663B", glow2: "6E4B2A", accent: "F7EA1B"),
        .init(name: "Dusk indigo", ground: "1B2038", glow1: "3C4A7A", glow2: "7A5C8C", accent: "F4E3B5"),
        .init(name: "Sea glass", ground: "12302F", glow1: "2F6B66", glow2: "6FA39A", accent: "F2F0D8"),
        .init(name: "Clay and ember", ground: "2E1C17", glow1: "6B3A2C", glow2: "B26A4A", accent: "FFE9C2"),
        .init(name: "Lavender mist", ground: "261F36", glow1: "5B4B80", glow2: "A58BB8", accent: "FFF1D6"),
        .init(name: "Moss and sand", ground: "26291A", glow1: "5E6B3C", glow2: "B5A06A", accent: "F7F2D0"),
        .init(name: "Slate dawn", ground: "1B2630", glow1: "3F5A6B", glow2: "C9907A", accent: "FFF0DC")
    ]
    public static func index(dayOfYear: Int, previous: Int?, pinned: Int? = nil, count: Int = 7) -> Int {
        guard count > 0 else { return 0 }
        if let pinned { return max(0, pinned) % count }
        let index = dayOfYear % count
        return index == previous ? (index + 1) % count : index
    }
    public static func luminance(_ hex: String) -> Double {
        let value = Int(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        let channels = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { value -> Double in
            let c = value / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
    public static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b); return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
extension Color {
    static func hex(_ value: String) -> Color {
        let number = Int(value.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0
        return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
}
