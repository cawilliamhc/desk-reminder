import SwiftUI

/// The design tokens, from the Practice Studio palette the mocks use.
enum Theme {
    static let background = Color(hex: 0xf5f2ed)      // sidebar, side panels
    static let surface = Color.white                   // window content
    static let ink = Color(hex: 0x241f19)
    static let muted = Color(hex: 0x6e655c)
    static let primary = Color(hex: 0x3f6b52)
    static let border = Color(hex: 0xdcd5c9)

    static let standing = Color(hex: 0x568168)         // chart-1
    static let calendar = Color(hex: 0xbc674e)         // chart-2
    static let reading = Color(hex: 0xbd9042)          // chart-3
    static let session = Color(hex: 0x5e85a1)          // chart-4
    static let lunch = Color(hex: 0x967396)            // chart-5
    static let sitting = border

    /// Headlines are GT Ultra Light, which Carl has licensed and which ships
    /// inside the bundle. New York (the system serif) stands in if the font
    /// ever fails to load, so the app never falls back to a sans-serif.
    static let headlineFontName = "GTUltra-Light"
    private static let hasGTUltra = NSFont(name: headlineFontName, size: 12) != nil

    static func headline(_ size: CGFloat) -> Font {
        hasGTUltra
            ? .custom(headlineFontName, size: size)
            : .system(size: size, design: .serif).weight(.light)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Card: white, hairline border, soft corner - the mocks' repeated shape.
    func cardStyle(padding: CGFloat = 10, radius: CGFloat = 8) -> some View {
        self.padding(padding)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Durations read as "1:48" and "46%", never "1.8 hours".
func hoursMinutes(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
}

func minutesOnly(_ seconds: TimeInterval) -> String {
    "\(Int(seconds.rounded()) / 60) min"
}


extension TimeInterval {
    /// A session that hasn't started yet contributes nothing, not a negative.
    var clampedToZero: TimeInterval { max(0, self) }
}
