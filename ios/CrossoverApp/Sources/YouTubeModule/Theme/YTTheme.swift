import SwiftUI

#if canImport(UIKit)
import UIKit
import CoreText
#endif

// MARK: - 0. Resource Bundle Resolver (Supports both SwiftPM/xtool Bundle.module and Xcode Bundle.main)
public enum YTResourceBundle {
    public static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        if let url = Bundle.main.url(forResource: "YouTubeClone_YouTubeClone", withExtension: "bundle"),
           let b = Bundle(url: url) {
            return b
        }
        return Bundle.main
        #endif
    }

    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        if let u = bundle.url(forResource: name, withExtension: ext) {
            return u
        }
        if let u = bundle.url(forResource: name, withExtension: ext, subdirectory: "Fonts") {
            return u
        }
        if let u = bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/Fonts") {
            return u
        }
        if let u = Bundle.main.url(forResource: name, withExtension: ext) {
            return u
        }
        return nil
    }
}

// MARK: - 1. Custom Font Loader (Registers Bundled YouTube Sans & Google Sans Fonts)
public enum YTFontManager {
    private static var didRegister = false

    public static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        #if canImport(UIKit)
        let fontFiles = [
            "YTSans-Bold.otf",
            "YTSans-Medium.otf",
            "YouTubeSans-Light.nohints.ttf",
            "YouTubeSans-Regular.nohints.ttf",
            "YouTubeSans-Medium.nohints.ttf",
            "YouTubeSans-SemiBold.nohints.ttf",
            "YouTubeSans-Bold.nohints.ttf",
            "YouTubeSans-ExtraBold.nohints.ttf",
            "YouTubeSans-Black.nohints.ttf",
            "GoogleSans-Regular.nohints.ttf",
            "GoogleSans-Medium.nohints.ttf",
            "GoogleSans-Bold.nohints.ttf",
            "Roboto-Black.ttf"
        ]
        for file in fontFiles {
            let comps = file.split(separator: ".")
            guard comps.count >= 2 else { continue }
            let ext = String(comps.last!)
            let name = comps.dropLast().joined(separator: ".")
            if let url = YTResourceBundle.url(forResource: name, withExtension: ext) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        #endif
    }

    public static func youtubeSans(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        registerBundledFonts()
        #if canImport(UIKit)
        let fontName: String
        switch weight {
        case .black, .heavy, .bold:
            fontName = "YouTubeSans-Bold"
        case .semibold:
            fontName = "YouTubeSans-SemiBold"
        case .medium:
            fontName = "YouTubeSans-Medium"
        default:
            fontName = "YouTubeSans-Regular"
        }
        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size)
        }
        #endif
        return .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - 2. Exact YouTube Color Tokens (Programmatic Dynamic UIColor -> Guaranteed Never Nil/Black!)
public enum YTTheme {
    private static func dynamicColor(lightHex: String, darkHex: String) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? uiColor(hex: darkHex) : uiColor(hex: lightHex)
        })
        #else
        return color(hex: lightHex)
        #endif
    }

    #if canImport(UIKit)
    private static func uiColor(hex: String, alpha: CGFloat = 1.0) -> UIColor {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        return UIColor(red: r, green: g, blue: b, alpha: alpha)
    }
    #endif

    public static let backgroundPrimary = dynamicColor(lightHex: "#FFFFFF", darkHex: "#0F0F0F")
    public static let backgroundSecondary = dynamicColor(lightHex: "#F2F2F2", darkHex: "#272727")
    public static let backgroundGrouped = dynamicColor(lightHex: "#F1F1F1", darkHex: "#181818")
    public static let textPrimary = dynamicColor(lightHex: "#0F0F0F", darkHex: "#F1F1F1")
    public static let textSecondary = dynamicColor(lightHex: "#606060", darkHex: "#AAAAAA")
    public static let textDisabled = dynamicColor(lightHex: "#909090", darkHex: "#717171")
    public static let chipSelectedBackground = dynamicColor(lightHex: "#606060", darkHex: "#F1F1F1")
    public static let chipSelectedText = dynamicColor(lightHex: "#FFFFFF", darkHex: "#0F0F0F")
    public static let brandRed = dynamicColor(lightHex: "#FF0000", darkHex: "#FF0033")
    public static let subscribeRed = dynamicColor(lightHex: "#CC0000", darkHex: "#FF0000")
    public static let callToActionBlue = dynamicColor(lightHex: "#065FD4", darkHex: "#3EA6FF")
    public static let separator = dynamicColor(lightHex: "#E5E5E5", darkHex: "#272727")
    public static let snackbarBackground = dynamicColor(lightHex: "#212121", darkHex: "#323232")

    // Exact hex helper
    public static func color(hex: String, opacity: Double = 1.0) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: UInt64
        switch clean.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (128, 128, 128)
        }
        return Color(.sRGB, red: Double(r) / 255.0, green: Double(g) / 255.0, blue: Double(b) / 255.0, opacity: opacity)
    }

    // "New to you" signature gradient border (Teal -> Purple -> Magenta)
    public static let newToYouGradient = LinearGradient(
        colors: [
            color(hex: "#00786C"),
            color(hex: "#7F0E7F"),
            color(hex: "#C80064")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Cairo signature progress bar gradient (Red -> Magenta)
    public static let cairoProgressGradient = LinearGradient(
        colors: [
            color(hex: "#FF0000"),
            color(hex: "#FF0033"),
            color(hex: "#FF2985")
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - 3. Asset Icon Helper (Loads from YTResourceBundle.bundle + SF Symbol Fallback)
public struct YTIcon: View {
    public let name: String
    public let fallbackSystemName: String
    public var size: CGFloat = 24
    public var renderOriginal: Bool = false

    public init(_ name: String, fallback: String = "circle", size: CGFloat = 24, renderOriginal: Bool = false) {
        self.name = name
        self.fallbackSystemName = fallback
        self.size = size
        self.renderOriginal = renderOriginal
    }

    public var body: some View {
        #if canImport(UIKit)
        if let uiImg = UIImage(named: name, in: YTResourceBundle.bundle, compatibleWith: nil) ?? UIImage(named: name) {
            Image(uiImage: uiImg)
                .renderingMode(renderOriginal ? .original : .template)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemName)
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
        #else
        Image(systemName: fallbackSystemName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
        #endif
    }
}

// MARK: - 4. YouTube Wordmark Header Logo (Standard "YouTube" or "YouTube Premium")
public struct YTWordmarkLogoView: View {
    public var isPremium: Bool = true

    public init(isPremium: Bool = true) {
        self.isPremium = isPremium
    }

    public var body: some View {
        HStack(spacing: 4) {
            // Official Red YouTube Play Pill
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                    .frame(width: 29, height: 20)
                TrianglePlayShape()
                    .fill(Color.white)
                    .frame(width: 8, height: 9)
                    .offset(x: 1)
            }
            Text(isPremium ? "Premium" : "YouTube")
                .font(YTFontManager.youtubeSans(size: 21, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(YTTheme.textPrimary)
        }
    }
}

public struct TrianglePlayShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - 5. Official YouTube Shorts Red Lightning/Play Icon
public struct YTShortsLogoIcon: View {
    public var size: CGFloat = 22

    public init(size: CGFloat = 22) {
        self.size = size
    }

    public var body: some View {
        #if canImport(UIKit)
        if let uiImg = UIImage(named: "youtube_shorts_24", in: YTResourceBundle.bundle, compatibleWith: nil)
            ?? UIImage(named: "youtube_shorts_cairo_24pt", in: YTResourceBundle.bundle, compatibleWith: nil) {
            Image(uiImage: uiImg)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            fallbackShortsIcon
        }
        #else
        fallbackShortsIcon
        #endif
    }

    private var fallbackShortsIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color(red: 1.0, green: 0.0, blue: 0.0))
                .frame(width: size * 0.78, height: size * 0.95)
                .rotationEffect(.degrees(15))
            TrianglePlayShape()
                .fill(Color.white)
                .frame(width: size * 0.32, height: size * 0.36)
                .offset(x: 0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 6. Skeleton Loading Shimmer Effect (`skeletonloading.json` equivalent)
public struct YTShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    public func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.0),
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: phase * geo.size.width * 1.5)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

public extension View {
    func ytShimmer() -> some View {
        modifier(YTShimmerModifier())
    }
}

// MARK: - 7. Video Card Skeleton Placeholder (Ghost Card)
public struct YTVideoCardSkeletonView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Rectangle()
                .fill(YTTheme.backgroundSecondary)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .ytShimmer()

            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(YTTheme.backgroundSecondary)
                    .frame(width: 36, height: 36)
                    .ytShimmer()

                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(YTTheme.backgroundSecondary)
                        .frame(height: 16)
                        .ytShimmer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(YTTheme.backgroundSecondary)
                        .frame(width: 220, height: 14)
                        .ytShimmer()
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 16)
    }
}
