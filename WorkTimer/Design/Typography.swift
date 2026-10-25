//
//  Typography.swift
//  WorkTimer
//

import CoreText
import SwiftUI

/// The three type voices from the design:
/// - Inter Tight Bold for numerals (the Fliqlo-style face; Fliqlo's own font
///   is proprietary, Inter Tight is SIL OFL and ships inside the app),
/// - SF Pro (the system font) for the task and actions,
/// - JetBrains Mono for small-caps status lines like "FOCUSING · UNTIL 3:47 PM".
enum Typography {
    /// Make the bundled .ttf files usable by name. `.process` scope means only
    /// this app sees them; nothing is installed on the Mac.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// Inter Tight ships as one variable font holding every weight, so the
    /// weight is picked with the `wght` variation axis rather than a file name.
    fileprivate static func interTight(size: CGFloat, weight: CGFloat) -> CTFont {
        let key = "\(size)-\(weight)"
        if let cached = interTightCache[key] { return cached }
        let wghtAxis = 0x7767_6874 // the four characters "wght" packed into an integer
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontFamilyNameAttribute: "Inter Tight",
            kCTFontVariationAttribute: [wghtAxis: weight],
        ] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        interTightCache[key] = font
        return font
    }

    private static var interTightCache: [String: CTFont] = [:]
}

extension Font {
    /// Inter Tight with tabular (equal-width) figures, so digits don't shift
    /// sideways as they change.
    static func numerals(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        Font(Typography.interTight(size: size, weight: weight)).monospacedDigit()
    }

    /// JetBrains Mono for status and label lines.
    static func mono(_ size: CGFloat, medium: Bool = false) -> Font {
        .custom(medium ? "JetBrainsMono-Medium" : "JetBrainsMono-Regular", fixedSize: size)
    }
}

extension View {
    /// The design's small-caps label: mono, 11 pt, 0.16 em letter spacing.
    func monoLabel(size: CGFloat = 11, tracking: CGFloat = 0.16) -> some View {
        font(.mono(size)).tracking(size * tracking)
    }
}
