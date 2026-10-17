import AppKit

/// How a Space's name is drawn in the menu bar. A nil color means the system
/// default, which follows the menu bar's light/dark appearance.
struct LabelStyle: Equatable {
    var color: NSColor?
    var bold = false
    var italic = false

    static let plain = LabelStyle()

    static var menuBarFontSize: CGFloat { NSFont.menuBarFont(ofSize: 0).pointSize }

    func font(size: CGFloat = LabelStyle.menuBarFontSize) -> NSFont {
        var font = NSFont.menuBarFont(ofSize: size)
        if bold { font = NSFont.systemFont(ofSize: size, weight: .bold) }
        if italic {
            // Union with existing traits so italic doesn't drop bold.
            let traits = font.fontDescriptor.symbolicTraits.union(bold ? [.italic, .bold] : .italic)
            let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        return font
    }

    func attributedTitle(_ title: String) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font()]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: title, attributes: attributes)
    }
}

// MARK: - Color helpers

extension NSColor {
    /// "#RRGGBB" in sRGB.
    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    /// WCAG relative luminance.
    var relativeLuminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent)
            + 0.7152 * channel(rgb.greenComponent)
            + 0.0722 * channel(rgb.blueComponent)
    }

    /// WCAG contrast ratio, 1...21.
    func contrastRatio(against other: NSColor) -> CGFloat {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Contrast check

enum MenuBarContrast {
    /// Approximate menu bar backgrounds. The real bar is translucent over the
    /// wallpaper, so these are typical values, not exact ones.
    static let lightBackground = NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1)
    static let darkBackground = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)
    /// WCAG minimum for large/bold text and UI components.
    static let minimumRatio: CGFloat = 3

    /// Appearances where `color` is hard to read; empty when fine or when using the default color.
    static func poorContrastModes(for color: NSColor?) -> [String] {
        guard let color else { return [] }
        var modes: [String] = []
        if color.contrastRatio(against: lightBackground) < minimumRatio { modes.append("light") }
        if color.contrastRatio(against: darkBackground) < minimumRatio { modes.append("dark") }
        return modes
    }
}
