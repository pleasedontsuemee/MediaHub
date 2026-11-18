import Foundation
import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Bundle Accessor for SwiftPM (`xtool`) & Xcode
public enum NFResourceBundle {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    #if canImport(UIKit)
    public static func image(named name: String) -> UIImage? {
        UIImage(named: name, in: bundle, compatibleWith: nil)
            ?? UIImage(named: name, in: Bundle.main, compatibleWith: nil)
    }
    #endif
}

// MARK: - Netflix Hawkins Design System Colors (OLED Dark)
public enum NFTheme {
    public static let backgroundPrimary = Color(red: 0.0, green: 0.0, blue: 0.0)          // #000000
    public static let backgroundSecondary = Color(red: 0.071, green: 0.071, blue: 0.071) // #121212
    public static let backgroundElevated = Color(red: 0.149, green: 0.149, blue: 0.149)  // #262626
    public static let searchBarFill = Color(red: 0.169, green: 0.169, blue: 0.169)       // #2B2B2B
    public static let netflixRed = Color(red: 0.898, green: 0.035, blue: 0.078)          // #E50914
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.702, green: 0.702, blue: 0.702)       // #B3B3B3
    public static let textMuted = Color(red: 0.549, green: 0.549, blue: 0.549)           // #8C8C8C
    public static let separator = Color.white.opacity(0.14)
    public static let accentBlue = Color(red: 0.25, green: 0.42, blue: 0.96)
    public static let tabBarHeight: CGFloat = 49

    public static func color(hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Netflix Sans Font Registration
public enum NFFontManager {
    private static var didRegister = false

    public static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true

        for (name, ext) in [("netflix-sans-core", "ttf"), ("nf-icon", "otf")] {
            if let url = NFResourceBundle.url(forResource: name, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    public static func netflixSans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}
