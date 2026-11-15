import SwiftUI

extension Color {
    init?(inboxHex: String) {
        var value = inboxHex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let rgba = UInt64(value, radix: 16) else { return nil }
        let hasAlpha = value.count == 8
        let red = Double((rgba >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((rgba >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((rgba >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(rgba & 0xFF) / 255 : 1
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

enum Theme {
    struct Palette {
        var background = Color(inboxHex: "#0D1117")!
        var chrome = Color(inboxHex: "#16181B")!
        var surface = Color(inboxHex: "#191B1E")!
        var raised = Color(inboxHex: "#23262B")!
        var hover = Color(inboxHex: "#FFFFFF0B")!
        var selected = Color(inboxHex: "#31557A8C")!
        var border = Color(inboxHex: "#FFFFFF17")!
        var foreground = Color(inboxHex: "#E6E8EC")!
        var muted = Color(inboxHex: "#9BA1A9")!
        var dim = Color(inboxHex: "#697079")!
        var accent = Color(inboxHex: "#2F81F7")!
        var green = Color(inboxHex: "#3FB950")!
        var red = Color(inboxHex: "#F85149")!
        var yellow = Color(inboxHex: "#D29922")!
        var orange = Color(inboxHex: "#FFA657")!
        var purple = Color(inboxHex: "#A371F7")!
    }

    static private(set) var palette = Palette()
    static private(set) var fontFamily = "JetBrains Mono"

    static func applyFont(_ family: String?) {
        let value = family?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            fontFamily = value
        } else {
            fontFamily = "JetBrains Mono"
        }
    }

    static func font(_ size: CGFloat, weight: Font.Weight) -> Font {
        if fontFamily.caseInsensitiveCompare("System") == .orderedSame {
            return .system(size: size, weight: weight)
        }
        return .custom(fontFamily, size: size).weight(weight)
    }

    static func apply(_ overrides: [String: String]) {
        var palette = Palette()
        for (name, value) in overrides {
            guard let color = Color(inboxHex: value) else { continue }
            switch name {
            case "background": palette.background = color
            case "chrome": palette.chrome = color
            case "surface": palette.surface = color
            case "raised": palette.raised = color
            case "hover": palette.hover = color
            case "selected": palette.selected = color
            case "border": palette.border = color
            case "foreground": palette.foreground = color
            case "muted": palette.muted = color
            case "dim": palette.dim = color
            case "accent": palette.accent = color
            case "green": palette.green = color
            case "red": palette.red = color
            case "yellow": palette.yellow = color
            case "orange": palette.orange = color
            case "purple": palette.purple = color
            default: break
            }
        }
        self.palette = palette
    }

    static var background: Color { palette.background }
    static var chrome: Color { palette.chrome }
    static var surface: Color { palette.surface }
    static var raised: Color { palette.raised }
    static var hover: Color { palette.hover }
    static var selected: Color { palette.selected }
    static var border: Color { palette.border }
    static var foreground: Color { palette.foreground }
    static var muted: Color { palette.muted }
    static var dim: Color { palette.dim }
    static var accent: Color { palette.accent }
    static var green: Color { palette.green }
    static var red: Color { palette.red }
    static var yellow: Color { palette.yellow }
    static var orange: Color { palette.orange }
    static var purple: Color { palette.purple }
}

extension View {
    func inboxFont(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        font(Theme.font(size, weight: weight))
    }

    func inboxMono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> some View {
        font(Theme.font(size, weight: weight))
    }
}
