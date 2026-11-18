import Foundation
import SwiftUI
import CoreText

#if canImport(UIKit)
import UIKit
#endif

public enum SPResourceBundle {
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
}

public enum SPTheme {
    public static let backgroundPrimary = Color(red: 0.071, green: 0.071, blue: 0.071)   // #121212
    public static let backgroundPureBlack = Color.black                                  // #000000
    public static let backgroundCard = Color(red: 0.094, green: 0.094, blue: 0.094)      // #181818
    public static let backgroundElevated = Color(red: 0.157, green: 0.157, blue: 0.157)  // #282828
    public static let spotifyGreen = Color(red: 0.118, green: 0.843, blue: 0.376)        // #1ED760
    public static let skyrockBlue = Color(red: 0.0, green: 0.62, blue: 0.96)
    public static let textPrimary = Color.white
    public static let textSecondary = Color(red: 0.702, green: 0.702, blue: 0.702)       // #B3B3B3
    public static let textMuted = Color(red: 0.48, green: 0.48, blue: 0.48)
    public static let separator = Color.white.opacity(0.10)
    public static let tabBarHeight: CGFloat = 52
    public static let miniPlayerHeight: CGFloat = 58
}

public enum SPFontManager {
    private static var didRegister = false

    public static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        for (name, ext) in [("SpotifyMixUI-Regular", "ttf"), ("SpotifyMixUI-Bold", "ttf")] {
            if let url = SPResourceBundle.url(forResource: name, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }

    public static func mix(_ size: CGFloat, bold: Bool = false) -> Font {
        let fontName = bold ? "SpotifyMixUI-Bold" : "SpotifyMixUI-Regular"
        #if canImport(UIKit)
        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size)
        }
        #endif
        return .system(size: size, weight: bold ? .bold : .regular)
    }
}
