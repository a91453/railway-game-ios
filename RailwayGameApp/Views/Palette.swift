import GameCore
import SwiftUI
import UIKit

/// The map's colours and the lines' colours, each with a light and a dark
/// variant. The interface's colours are ``Theme``'s.
///
/// Since decision 84 (2026-10-08, the owner's choice) the map is drawn in
/// the app icon's style ahead of Phase 8's renderer: the icon's pale
/// ground (#ECEEF6, dark #262C57), teal track (#12A08F, dark #45D3C0) with
/// its pale centre line (#BDEFE7, dark #D4FAF4), warm stations (#FFC86B)
/// and navy (#262C57, dark #ECEEF6) for what is drawn on them. The traffic
/// and population colours below stay (docs/UI_THEME.md), and the lines'
/// colours stay for good.
enum Palette {
    static let land = hex(light: 0xECEEF6, dark: 0x262C57)
    static let mapEdge = hex(light: 0x262C57, dark: 0xECEEF6, alpha: 0.3)
    /// The track's bed: the icon's teal, a shade darker on the light map
    /// (#10917F) so it stands out from the ground by 3:1 (3.37:1; the
    /// icon's #12A08F is 2.81:1), as a graphic needs; 7.17:1 on the dark.
    static let track = hex(light: 0x10917F, dark: 0x45D3C0)
    /// The line down the middle of the track, as the icon's.
    static let trackCentre = hex(light: 0xBDEFE7, dark: 0xD4FAF4)
    /// Navy on the light map, pale on the dark: station names, nodes,
    /// tunnels, the edges of stations and the casing of a viaduct (the
    /// icon's buildings; ``Theme/textPrimary``, 11.47:1 and 9.64:1 on the
    /// map's ground).
    static let ink = hex(light: 0x262C57, dark: 0xECEEF6)
    /// The icon's warm station, with ``ink`` round it and its symbol.
    static let station = hex(light: 0xFFC86B, dark: 0xFFC86B)
    static let stationSymbol = hex(light: 0x262C57, dark: 0x262C57)
    static let train = hex(light: 0x262C57, dark: 0xECEEF6)
    /// The link through a transfer group's stations: MapBuilder's
    /// interchange, white with a black edge in either appearance, here
    /// white with the icon's navy.
    static let transferLink = hex(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let transferEdge = hex(light: 0x262C57, dark: 0x262C57)
    /// The player's buildings (decision 92), edged in ``ink``: homes,
    /// shops and offices in the land use layer's hues (orange, red, blue).
    static let house = hex(light: 0xF4A259, dark: 0xF6B47A)
    static let shop = hex(light: 0xE05A4F, dark: 0xEC7A70)
    static let office = hex(light: 0x4C7FD0, dark: 0x7AA2E3)
    /// Decision 111: the shore's buildings, a weathered pier's brown and a
    /// sea teal.
    static let wharf = hex(light: 0xA0704A, dark: 0xC09070)
    static let marina = hex(light: 0x1F9E9A, dark: 0x4CC3BF)
    /// Decision 121: the kind's glyph on a player's building, navy in
    /// either appearance (the buildings' hues are light on the dark map,
    /// so ``ink`` would not show): 3.11:1 or more on all ten.
    static let buildingGlyph = hex(light: 0x262C57, dark: 0x262C57)

    // Transit Semantic Colors
    static let metroBlue = dynamic(light: (0.07, 0.45, 0.88), dark: (0.24, 0.60, 1.00))
    static let metroGreen = dynamic(light: (0.13, 0.62, 0.36), dark: (0.22, 0.78, 0.48))
    static let metroAmber = dynamic(light: (0.88, 0.52, 0.08), dark: (0.96, 0.65, 0.20))
    static let metroPurple = dynamic(light: (0.48, 0.28, 0.82), dark: (0.65, 0.48, 0.95))
    static let metroCyan = dynamic(light: (0.05, 0.60, 0.72), dark: (0.20, 0.75, 0.88))
    static let metroRed = dynamic(light: (0.85, 0.24, 0.24), dark: (0.95, 0.38, 0.38))

    /// The casing under a train's movement authority (Stage V4e): the
    /// `Railway/` site's `followCase` (#fffdf6 light, #10141c dark), which
    /// it draws under a followed train's route.
    static let followCase = dynamic(light: (1.00, 0.992, 0.965), dark: (0.063, 0.078, 0.110))

    /// The colour a line is drawn with in the lines panel and the follow
    /// bar's dot: the one the player chose (`custom`, the line's
    /// ``LineColor``), or else one picked from the line's ID, as the lines
    /// panel always has.
    static func lineColor(_ id: LineID, custom: LineColor? = nil) -> Color {
        if let custom {
            return color(custom)
        }
        let colors: [Color] = [metroBlue, metroGreen, metroAmber, metroPurple, metroCyan, metroRed]
        return colors[abs(Int(id.rawValue)) % colors.count]
    }

    /// A ``LineColor`` as a SwiftUI colour.
    static func color(_ line: LineColor) -> Color {
        Color(
            red: Double((line.rgb >> 16) & 0xFF) / 255,
            green: Double((line.rgb >> 8) & 0xFF) / 255,
            blue: Double(line.rgb & 0xFF) / 255
        )
    }

    private static func hex(light: UInt32, dark: UInt32, alpha: Double = 1) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >> 8) & 0xFF) / 255,
                blue: Double(rgb & 0xFF) / 255,
                alpha: alpha
            )
        })
    }

    private static func dynamic(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

/// The map's own glyphs (ARCHITECTURE decision 121): the app icon's style
/// (filled, rounded, heavy enough to read at a few points) for what stands
/// on the map, in place of SF Symbols. Each is a one-colour template SVG in
/// the asset catalog, tinted where it is drawn, so one image serves both
/// appearances. The interface's buttons keep SF Symbols.
enum MapGlyph: String {
    case train = "MapGlyphTrain"
    case house = "MapGlyphHouse"
    case shop = "MapGlyphShop"
    case office = "MapGlyphOffice"
    case wharf = "MapGlyphWharf"
    case marina = "MapGlyphMarina"
    case crowd = "MapGlyphCrowd"
    case full = "MapGlyphFull"
    case warning = "MapGlyphWarning"
    /// ``warning``'s outline without its cut-out mark, drawn under it.
    case warningSolid = "MapGlyphWarningSolid"

    var image: Image {
        Image(rawValue).renderingMode(.template)
    }
}
