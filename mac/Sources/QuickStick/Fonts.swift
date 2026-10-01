import AppKit
import SwiftUI

/// The two faces the web app is set in, loaded from the bundle. Both files are
/// variable fonts, so the weight has to be dialled in on the variation axis:
/// asking for the family by name alone gets the default instance, which for
/// Doto is Black and far heavier than the 600 the titles want.
enum Fonts {
    static let displayFamily = "Doto"
    static let bodyFamily = "IBM Plex Sans"

    private static let weightAxis = 0x77676874  // 'wght'

    static func nsFont(_ family: String, size: CGFloat, weight: Int) -> NSFont {
        register()
        let attrs: [CFString: Any] = [
            kCTFontFamilyNameAttribute: family,
            kCTFontVariationAttribute: [weightAxis: weight],
        ]
        let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil) as NSFont
    }

    static func font(_ family: String, size: CGFloat, weight: Int) -> Font {
        Font(nsFont(family, size: size, weight: weight) as CTFont)
    }

    /// ATSApplicationFontsPath in Info.plist covers a normal launch; this is
    /// the path that also works when the binary runs outside a bundle. A static
    /// let is the lock: Swift runs it exactly once, whoever asks first.
    private static let registration: Void = {
        for name in ["Doto", "IBMPlexSans"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    private static func register() { _ = registration }
}

extension Color {
    /// "#RRGGBB" as the web app writes it, darkened the way the cells are:
    /// the browser paints each one under filter: brightness(0.7).
    init(hex: String, brightness: Double = 1) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255 * brightness,
            green: Double((v >> 8) & 0xFF) / 255 * brightness,
            blue: Double(v & 0xFF) / 255 * brightness
        )
    }
}
