#if os(macOS)
import AppKit

enum TerminalPalette {
    case basic

    struct Pair {
        let light: [NSColor]
        let dark: [NSColor]
        let lightBG: NSColor
        let darkBG: NSColor
        let lightFG: NSColor
        let darkFG: NSColor
    }

    static func palette(for style: NSAppearance.Name) -> Pair {
        _ = style
        return basicPair
    }

    private static let basicPair = Pair(
        light: [
            rgb(0x000000), rgb(0x990000), rgb(0x00A600), rgb(0x999900),
            rgb(0x0000B2), rgb(0xB200B2), rgb(0x00A6B2), rgb(0xBFBFBF),
            rgb(0x666666), rgb(0xE50000), rgb(0x00D900), rgb(0xE5E500),
            rgb(0x0000FF), rgb(0xE500E5), rgb(0x00E5E5), rgb(0xE5E5E5),
        ],
        dark: [
            rgb(0x000000), rgb(0xC91B00), rgb(0x00C200), rgb(0xC7C400),
            rgb(0x0225C7), rgb(0xCA30C7), rgb(0x00C5C7), rgb(0xC7C7C7),
            rgb(0x686868), rgb(0xFF6E67), rgb(0x5FFA68), rgb(0xFFFC67),
            rgb(0x6871FF), rgb(0xFF77FF), rgb(0x60FDFF), rgb(0xFFFFFF),
        ],
        lightBG: rgb(0xFFFFFF),
        darkBG: rgb(0x000000),
        lightFG: rgb(0x000000),
        darkFG: rgb(0xC7C7C7)
    )

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
#endif
