import GameCore

/// A line's badge (ARCHITECTURE decision 216): its code, such as the Taipei
/// Metro's BL or R, on a white tag beside a patch of the line's colour, so
/// that lines tell themselves apart by text and not by colour alone
/// (decision 205's rule for the marks near the lines, taken to the lines
/// themselves).
///
/// A line has the code the player gave it (``ServiceLine/code``), or else
/// the app's own: the letters of its colour's name (``automaticCode(rgb:)``,
/// as the Taipei Metro names its lines BL, R, G, O, BR and Y), with a number
/// after it for the second line of that colour and on (R, R2, R3), so that
/// no two lines share a code unless the player gives them one.
public enum LineBadge {
    /// The code of each line of `lines`: its own, or the app's from its
    /// colour (`automaticColors` for a line with none, keyed by line), each
    /// automatic code the first of `letters`, `letters2`, `letters3`… that
    /// no line before it in `lines`' order (the lines' IDs, as the world
    /// keeps them) has and no line's own code is.
    public static func codes(
        for lines: [ServiceLine], automaticColor: (LineID) -> Int = automaticColor(of:)
    ) -> [LineID: String] {
        var taken = Set(lines.compactMap { $0.code?.text })
        var codes: [LineID: String] = [:]
        for line in lines {
            if let code = line.code {
                codes[line.id] = code.text
                continue
            }
            let letters = automaticCode(rgb: line.color?.rgb ?? automaticColor(line.id))
            var code = letters
            var number = 2
            while taken.contains(code) {
                code = "\(letters)\(number)"
                number += 1
            }
            taken.insert(code)
            codes[line.id] = code
        }
        return codes
    }

    /// The app's own colour of a line the player gave none, the lines
    /// panel's pick from its ID (the app's `Palette.lineColor`): blue,
    /// green, amber, purple, cyan and red, as it draws them on a light map.
    public static func automaticColor(of id: LineID) -> Int {
        automaticColors[abs(Int(id.rawValue)) % automaticColors.count]
    }

    /// `Palette`'s `metroBlue`, `metroGreen`, `metroAmber`, `metroPurple`,
    /// `metroCyan` and `metroRed` in their light form.
    public static let automaticColors = [0x1273E0, 0x219E5C, 0xE08514, 0x7A47D1, 0x0D99B8, 0xD93D3D]

    /// The letters of a colour's name: the Taipei Metro's for the colours
    /// it has (BL blue, R red, G green, O orange, BR brown, Y yellow), the
    /// English name's for the rest (PK pink, P purple, LB light blue, LG
    /// light green, T teal, IN indigo, GY grey, W white). Each of
    /// ``LineColor/presets`` and ``automaticColors`` has its own entry; any
    /// other colour is named by its hue (``hueCode(rgb:)``).
    public static func automaticCode(rgb: Int) -> String {
        namedCodes[rgb] ?? hueCode(rgb: rgb)
    }

    static let namedCodes: [Int: String] = [
        // LineColor.presets, in order.
        0xF5F5F5: "W", 0xEF5350: "R", 0xFF7043: "O", 0xFFD54F: "Y", 0xAED581: "LG",
        0x66BB6A: "G", 0x26A69A: "T", 0x4DD0E1: "LB", 0x42A5F5: "BL", 0x5C6BC0: "IN",
        0xAB47BC: "P", 0xEC407A: "PK", 0xFF80AB: "PK", 0xA1887F: "BR", 0x78909C: "GY",
        0xFFCC02: "Y", 0xFF6E40: "O", 0x00E5FF: "LB", 0x69F0AE: "LG", 0xEEFF41: "LG",
        // automaticColors.
        0x1273E0: "BL", 0x219E5C: "G", 0xE08514: "O", 0x7A47D1: "P", 0x0D99B8: "LB", 0xD93D3D: "R",
    ]

    /// A colour's letters from its hue, lightness and saturation (HSL):
    /// W, GY or K when it has little colour; else R, O (BR when dark), Y,
    /// G, T, LB, BL, P or PK by hue (the Taipei Metro's blue, hue 205, is BL).
    static func hueCode(rgb: Int) -> String {
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let chroma = high - low
        guard chroma > 0.12 else { return lightness > 0.85 ? "W" : lightness < 0.2 ? "K" : "GY" }
        var hue: Double
        if high == r {
            hue = (g - b) / chroma
        } else if high == g {
            hue = (b - r) / chroma + 2
        } else {
            hue = (r - g) / chroma + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        switch hue {
        case ..<15: return "R"
        case ..<45: return lightness < 0.45 ? "BR" : "O"
        case ..<70: return "Y"
        case ..<160: return "G"
        case ..<185: return "T"
        case ..<200: return "LB"
        case ..<255: return "BL"
        case ..<300: return "P"
        case ..<345: return "PK"
        default: return "R"
        }
    }

    /// The code `text` is, read leniently as a player types it: spaces
    /// dropped, small letters as capitals, and full-width letters and
    /// digits (as a Chinese keyboard gives them) as the plain ones. `nil`
    /// when what is left is no ``LineCode``.
    public static func code(from text: String) -> LineCode? {
        var plain = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x20, 0x09, 0x3000: continue
            case 0x61...0x7A: plain.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x20)!)
            case 0xFF21...0xFF3A, 0xFF10...0xFF19: plain.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0xFF41...0xFF5A: plain.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0 - 0x20)!)
            default: plain.unicodeScalars.append(scalar)
            }
        }
        return LineCode(plain)
    }

    /// Whether `text` is only spaces: the player asks for the app's own
    /// code again.
    public static func isBlank(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { [0x20, 0x09, 0x3000].contains($0.value) }
    }
}

/// The colours lines are drawn in (decision 216): the player's own, or, for
/// a player who tells some colours apart poorly, a palette whose colours
/// stay apart under each kind of colour blindness.
public enum LinePalette: String, CaseIterable, Sendable {
    /// Each line in the colour the player chose, or the app's pick.
    case standard
    /// Each line in the colour-blind-safe palette's colour nearest its own
    /// (``safeColor(for:)``). Only how the app draws it: the save keeps the
    /// player's colour, and turning this off brings it back.
    case colourBlindSafe

    /// The setting's key on the device (`@AppStorage`).
    public static let key = "linePalette"

    /// Masataka Okabe and Kei Ito's seven colours (*Color Universal Design*,
    /// 2002: orange, sky blue, bluish green, yellow, blue, vermillion,
    /// reddish purple; their black is the map's ink, so left out) and Paul
    /// Tol's pale grey (`#BBBBBB`, his "bright" scheme). Every pair stays
    /// apart under protanopia, deuteranopia and tritanopia (Machado 2009
    /// at full severity): CIEDE2000 10.9 at the least
    /// (`docs/UI_THEME.md`).
    public static let safeColors = [0xE69F00, 0x56B4E9, 0x009E73, 0xF0E442, 0x0072B2, 0xD55E00, 0xCC79A7, 0xBBBBBB]

    /// The safe colour a line of colour `rgb` is drawn in: chosen for each
    /// of ``LineColor/presets`` and ``LineBadge/automaticColors`` by its
    /// family (reds to vermillion, oranges to orange, yellows to yellow,
    /// greens to bluish green, light blues to sky blue, deep blues to
    /// blue, purples and pinks to reddish purple, white, grey and brown to
    /// grey), so the app's six own colours stay six; any other colour by
    /// its letters (``LineBadge/automaticCode(rgb:)``).
    public static func safeColor(for rgb: Int) -> Int {
        switch LineBadge.automaticCode(rgb: rgb) {
        case "R": 0xD55E00
        case "O": 0xE69F00
        case "Y": 0xF0E442
        case "G", "LG", "T": 0x009E73
        case "LB": 0x56B4E9
        case "BL": rgb == 0x42A5F5 ? 0x56B4E9 : 0x0072B2
        case "IN": 0x0072B2
        case "P", "PK": 0xCC79A7
        default: 0xBBBBBB
        }
    }

    /// The colour a line of colour `rgb` is drawn in with this palette.
    public func color(for rgb: Int) -> Int {
        switch self {
        case .standard: rgb
        case .colourBlindSafe: Self.safeColor(for: rgb)
        }
    }
}
