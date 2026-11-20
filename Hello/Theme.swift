import SwiftUI
import CoreText
import UIKit

// Design tokens for StillDay. Every colour, font, spacing, radius and size in the app comes from here.
// The rules behind these values live in README.md. Do not hard-code numbers in views.

// MARK: - Colour

enum Ink {
    static let canvas = Color(red: 0.98, green: 0.978, blue: 0.972)    // clean, barely-warm white
    static let text = Color(red: 0.16, green: 0.15, blue: 0.14)
    static let muted = Color(red: 0.52, green: 0.50, blue: 0.47)
    static let hairline = Color.black.opacity(0.06)
}

/// Colours of the pad's body beneath the top sheet.
enum PadColor {
    static let edge = Color(red: 0.965, green: 0.958, blue: 0.945)   // page edges, a touch under the paper
    static let board = Color(red: 0.84, green: 0.81, blue: 0.76)     // warm grey backing board
    static let calendarPaper = Color(red: 0.97, green: 0.95, blue: 0.91)
}

/// Glass sits on the light paper palette, including when it overlaps a busy calendar.
enum PaperGlassColor {
    static let tint = Color.white.opacity(0.76)
    static let rim = Color.white.opacity(0.86)
    static let drawer = Color(red: 0.99, green: 0.985, blue: 0.975)
    static let lensReflection = LinearGradient(colors: [.white.opacity(0.48), .white.opacity(0.10)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
    static let lensRim = LinearGradient(colors: [.white.opacity(0.95), Ink.text.opacity(0.13)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Soft craft-paper colours used by the creative shelf.
enum CraftTint {
    case mint, lavender, butter, peach

    var fill: Color {
        switch self {
        case .mint: Color(red: 0.92, green: 0.97, blue: 0.94)
        case .lavender: Color(red: 0.96, green: 0.93, blue: 0.99)
        case .butter: Color(red: 0.99, green: 0.97, blue: 0.90)
        case .peach: Color(red: 0.99, green: 0.94, blue: 0.92)
        }
    }

    var ink: Color {
        switch self {
        case .mint: Color(red: 0.42, green: 0.65, blue: 0.53)
        case .lavender: Color(red: 0.59, green: 0.52, blue: 0.75)
        case .butter: Color(red: 0.72, green: 0.60, blue: 0.28)
        case .peach: Color(red: 0.76, green: 0.49, blue: 0.43)
        }
    }

    var edge: Color { fill.mix(.black, 0.05) }

    var tilt: Double {
        switch self {
        case .mint: -3
        case .lavender: 4
        case .butter: -4
        case .peach: 3
        }
    }
}

// MARK: - Spacing (4pt grid)

enum Space {
    static let xxs: CGFloat = 4     // icon ↔ label, title ↔ subtitle
    static let xs: CGFloat = 8      // between sibling rows, small gaps
    static let sm: CGFloat = 12     // inner padding of compact elements
    static let md: CGFloat = 16     // standard inner padding
    static let margin: CGFloat = 20 // screen side margin
    static let lg: CGFloat = 24     // between sections
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48    // end-of-scroll breathing room
}

// MARK: - Corner radius

enum Radius {
    static let sm: CGFloat = 12
    static let md: CGFloat = 16     // rows, cards
    static let lg: CGFloat = 24     // the sticky note
}

// MARK: - Fixed sizes

enum Size {
    static let tapTarget: CGFloat = 44   // Apple HIG minimum
    static let noteMax: CGFloat = 340
    static let placedSticker: CGFloat = 80
    static let drawerTile: CGFloat = 68
    static let drawerArt: CGFloat = 44
    static let drawerPreview: CGFloat = 72
    static let drawerLip: CGFloat = 52
    static let stickerThumb: CGFloat = 32
    static let sliderLabel: CGFloat = 56
    static let tabHeight: CGFloat = 52
    static let tabLabelHeight: CGFloat = 22
    static let tabBarWidth: CGFloat = 256
    static let compactTabBarWidth: CGFloat = 156
    static let weekRow: CGFloat = 64
}

// MARK: - Typography
//
// Cormorant sets day numerals and Year headings, Bradley Hand labels the paper,
// and Poppins sets the controls and supporting text.

enum Typeface {
    private static let hand = "BradleyHandITCTT-Bold"
    private static let daySerif = "CormorantGaramond-Light"
    private static let headerSerif = "CormorantGaramond-Medium"
    private static let monthSerif = "CormorantGaramond-SemiBold"
    private static let regular = "Poppins-Regular"
    private static let medium = "Poppins-Medium"

    static var numeral: Font { numeral(size: 156) }
    static let dateHeading = Font.custom(hand, size: 23, relativeTo: .headline)
    static let noteLead = paperLabel(20)
    static let noteTail = paperLabel(26)
    static let heading = Font.custom(medium, size: 17, relativeTo: .headline)
    static let body = Font.custom(regular, size: 15, relativeTo: .body)
    static let callout = Font.custom(medium, size: 14, relativeTo: .callout).monospacedDigit()
    static let subhead = Font.custom(regular, size: 14, relativeTo: .subheadline)
    static let caption = Font.custom(regular, size: 12, relativeTo: .caption)
    static let tabLabel = Font.custom(medium, size: 12, relativeTo: .caption)
    static let calendarTitle = Font.custom(medium, size: 22, relativeTo: .title2)
    static let monthTitle = Font.custom(monthSerif, size: 68, relativeTo: .largeTitle)
    static let yearHeading = Font.custom(headerSerif, size: 24, relativeTo: .headline)
    static let yearCaption = Font.custom(headerSerif, size: 21, relativeTo: .subheadline)
    static let yearTabLabel = Font.custom(headerSerif, size: 18, relativeTo: .caption)

    static func paperLabel(_ size: CGFloat) -> Font { .custom(hand, fixedSize: size) }

    static func numeral(size: CGFloat) -> Font {
        guard let font = UIFont(name: daySerif, size: size) else {
            return .system(size: size, weight: .light, design: .serif)
        }
        // Lining figures give every digit the same baseline and height on the page.
        let descriptor = font.fontDescriptor.addingAttributes([
            .featureSettings: [[UIFontDescriptor.FeatureKey.type: kNumberCaseType,
                                UIFontDescriptor.FeatureKey.selector: kUpperCaseNumbersSelector]],
        ])
        return Font(UIFont(descriptor: descriptor, size: size))
    }

    static let icon = Font.system(size: 15, weight: .medium)
    static let iconSmall = Font.system(size: 12, weight: .medium)
    static let tabIcon = Font.system(size: 18, weight: .medium)

    /// Makes the bundled .ttf files available by name. Call once at launch.
    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    func mix(_ other: Color, _ t: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let amount = CGFloat(t)
        return Color(red: r1 + (r2 - r1) * amount,
                     green: g1 + (g2 - g1) * amount,
                     blue: b1 + (b2 - b1) * amount)
    }
}

extension View {
    func glass<S: Shape>(_ shape: S, untinted: Bool = false) -> some View {
        modifier(PaperGlass(shape: shape, untinted: untinted))
    }
}

private struct PaperGlass<S: Shape>: ViewModifier {
    let shape: S
    let untinted: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.white, in: shape)
                .overlay { shape.stroke(Ink.hairline, lineWidth: 1).allowsHitTesting(false) }
        } else if #available(iOS 26.0, *) {
            content.glassEffect(untinted ? .clear : .regular.tint(PaperGlassColor.tint), in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                    .overlay { if !untinted { shape.fill(PaperGlassColor.tint) } }
                    .overlay { shape.stroke(PaperGlassColor.rim, lineWidth: 1) }
                    .allowsHitTesting(false)
            }
        }
    }
}
