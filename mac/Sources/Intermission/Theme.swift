import SwiftUI

/// The design tokens, from the Practice Studio palette the mocks use.
enum Theme {
    static let background = Color(hex: 0xf5f2ed)      // sidebar, side panels
    static let surface = Color.white                   // window content
    static let ink = Color(hex: 0x241f19)
    static let muted = Color(hex: 0x6e655c)
    static let primary = Color(hex: 0x3f6b52)
    static let border = Color(hex: 0xdcd5c9)

    /// The palette an intermission is coloured from.
    ///
    /// The first eight are Practice Studio's own chart tokens
    /// (client/src/index.css, light mode). The rest are new, but written to
    /// the same recipe - muted, mid-lightness, spread around the wheel - so
    /// a list of sixteen still looks like one family rather than eight
    /// tokens and eight strangers.
    static let palette: [(token: String, name: String, color: Color)] = [
        ("chart-1", "Green", Color(h: 145, s: 20, l: 42)),
        ("chart-2", "Terracotta", Color(h: 14, s: 45, l: 52)),
        ("chart-3", "Gold", Color(h: 38, s: 48, l: 50)),
        ("chart-4", "Blue", Color(h: 205, s: 26, l: 50)),
        ("chart-5", "Mauve", Color(h: 300, s: 14, l: 52)),
        ("chart-6", "Violet", Color(h: 255, s: 30, l: 55)),
        ("chart-7", "Rose", Color(h: 340, s: 40, l: 55)),
        ("chart-8", "Amber", Color(h: 28, s: 70, l: 50)),
        ("desk-1", "Teal", Color(h: 175, s: 30, l: 40)),
        ("desk-2", "Sky", Color(h: 196, s: 42, l: 60)),
        ("desk-3", "Indigo", Color(h: 232, s: 34, l: 52)),
        ("desk-4", "Plum", Color(h: 286, s: 26, l: 45)),
        ("desk-5", "Coral", Color(h: 6, s: 52, l: 62)),
        ("desk-6", "Olive", Color(h: 74, s: 32, l: 40)),
        ("desk-7", "Moss", Color(h: 112, s: 24, l: 46)),
        ("desk-8", "Clay", Color(h: 22, s: 34, l: 46)),
    ]

    static func color(token: String) -> Color {
        palette.first { $0.token == token }?.color ?? primary
    }

    static let standing = Color(hex: 0x568168)         // chart-1
    static let calendar = Color(hex: 0xbc674e)         // chart-2
    static let reading = Color(hex: 0xbd9042)          // chart-3
    static let session = Color(hex: 0x5e85a1)          // chart-4
    static let lunch = Color(hex: 0x967396)            // chart-5
    static let sitting = border
    /// The current-time line, matching Practice Studio's calendar (red-500).
    static let now = Color(hex: 0xef4444)

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
    /// The tokens are written as HSL, so they're read as HSL rather than
    /// converted by hand and drifting from the source.
    init(h: Double, s: Double, l: Double) {
        let saturation = s / 100
        let lightness = l / 100
        let c = (1 - abs(2 * lightness - 1)) * saturation
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = lightness - c / 2
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<60: (c, x, 0)
        case ..<120: (x, c, 0)
        case ..<180: (0, c, x)
        case ..<240: (0, x, c)
        case ..<300: (x, 0, c)
        default: (c, 0, x)
        }
        self.init(.sRGB, red: r + m, green: g + m, blue: b + m)
    }

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
