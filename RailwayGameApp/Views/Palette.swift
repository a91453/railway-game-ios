import GameCore
import GamePresentation
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
    /// Decision 270: a blank map's seeded streets, as the real map's roads
    /// (`BaseMapStyle`'s road, major road and casing, light and dark).
    static let road = hex(light: 0xFFFFFF, dark: 0x363D72)
    static let roadMajor = hex(light: 0xFFFFFF, dark: 0x424A84)
    static let roadCasing = hex(light: 0xCDD1E4, dark: 0x1E2348)
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
    /// Decision 182: a freight line's trains, grey (4.51:1 on the light
    /// map, 5.74:1 on the dark), where a passenger line's are in its colour.
    static let freightTrain = hex(light: 0x666C80, dark: 0xA4AABD)
    /// Decision 182: a streak of rain, a blue grey, light on the dark map.
    static let rain = hex(light: 0x4A5A80, dark: 0xC9D3EA, alpha: 0.45)
    /// Decision 182: what darkens the map under rain and typhoons, a navy
    /// near black, and lightning's flash.
    static let weatherShade = hex(light: 0x10142E, dark: 0x05071A)
    static let lightning = hex(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// Decision 277: a streak of rain over the 3D map, the reference's pale
    /// blue grey whatever the appearance (the 3D map has its own light), at
    /// the rain's opacity (`Map3DRain.opacity`).
    static let rain3D = rgb(Map3DRain.rgb)
    /// The link through a transfer group's stations: MapBuilder's
    /// interchange, white with a black edge in either appearance, here
    /// white with the icon's navy.
    static let transferLink = hex(light: 0xFFFFFF, dark: 0xFFFFFF)
    static let transferEdge = hex(light: 0x262C57, dark: 0x262C57)
    /// Decision 220: a journey trace's arcs, navy on a white edge in either
    /// appearance (the transfer link's two colours the other way round):
    /// never a line's colour or a gradient, so an arc is not read as a line.
    static let journeyArc = hex(light: 0x262C57, dark: 0x262C57)
    static let journeyCase = hex(light: 0xFFFFFF, dark: 0xFFFFFF)
    /// The player's buildings (decision 92), edged in ``ink``: every kind
    /// in the station's warm yellow, told apart by its glyph (decision 121).
    /// The owner's choice of 2026-10-13: what the player built reads as the
    /// player's, like the stations, and keeps clear of the town's use hues
    /// (``cityRoof``), which once clashed with them (homes orange, shops
    /// red, offices blue against the town's green, blue and amber).
    static let playerBuilding = station
    /// Decision 121: the kind's glyph on a player's building, navy in
    /// either appearance (the buildings' yellow is light on the dark map,
    /// so ``ink`` would not show): 8.69:1 on ``playerBuilding``.
    static let buildingGlyph = hex(light: 0x262C57, dark: 0x262C57)

    /// Decision 126: the city's own buildings on the plain map, a pale roof
    /// over a deeper wall in their use's hue (the land use layer's: homes
    /// green, shops blue, offices amber, factories purple, schools and
    /// public offices red, sights teal), edged in ``cityOutline``. Paler
    /// than the player's buildings, which carry a glyph, so the town reads
    /// as the ground the player builds on. The same in either appearance:
    /// they are light on the dark map too.
    static func cityRoof(_ use: LandUse) -> Color {
        switch use {
        case .residential: hex(light: 0xA8DCA8, dark: 0xA8DCA8)
        case .commercial: hex(light: 0xA9CBEB, dark: 0xA9CBEB)
        case .office: hex(light: 0xF5CD95, dark: 0xF5CD95)
        case .industrial: hex(light: 0xCFC9E6, dark: 0xCFC9E6)
        case .civic: hex(light: 0xF6BCAE, dark: 0xF6BCAE)
        case .leisure: hex(light: 0xAEE0D8, dark: 0xAEE0D8)
        case .agricultural: farmGround
        case .park: parkGround
        }
    }

    static func cityWall(_ use: LandUse) -> Color {
        switch use {
        case .residential: hex(light: 0x63B06F, dark: 0x63B06F)
        case .commercial: hex(light: 0x5F95CB, dark: 0x5F95CB)
        case .office: hex(light: 0xD99649, dark: 0xD99649)
        case .industrial: hex(light: 0x9088C2, dark: 0x9088C2)
        case .civic: hex(light: 0xDB7C6E, dark: 0xDB7C6E)
        case .leisure: hex(light: 0x4CA597, dark: 0x4CA597)
        case .agricultural: farmGround
        case .park: parkGround
        }
    }

    /// The buildings' edge: navy in either appearance, as
    /// ``buildingGlyph``.
    static let cityOutline = hex(light: 0x262C57, dark: 0x262C57)
    /// Open ground (decision 126): a park's lawn and a farm's field, a
    /// shade off the land.
    static let parkGround = hex(light: 0xCDE8B5, dark: 0x3E6B3A)
    static let farmGround = hex(light: 0xF1E6C8, dark: 0x5A5236)

    /// Decision 124, H3: what carries a stretch of track, on the build
    /// card's long section. The track's teal on the surface; the
    /// `Railway/` site's bank (`rail-structures.js` `#c6c0b1`) deepened
    /// for an embankment and a deeper earth for a cutting; the casing's
    /// navy for a viaduct, a river blue for a bridge, grey underground.
    static func section(_ kind: TrackSectionKind) -> Color {
        switch kind {
        case .surface: track
        case .embankment: embankment
        case .cutting: cutting
        case .viaduct: hex(light: 0x5A6390, dark: 0x9AA3D0)
        case .bridge: hex(light: 0x3E7CB1, dark: 0x7AB0DE)
        case .tunnel: hex(light: 0x8A8A8A, dark: 0x9C9C9C)
        }
    }
    /// The slopes of an embankment and a cutting, on the long section and
    /// beside the track on the map.
    static let embankment = hex(light: 0xB3A88E, dark: 0xC6C0B1)
    static let cutting = hex(light: 0x8C6A4A, dark: 0xB08D6A)
    /// The long section's ground and water.
    static let groundLine = hex(light: 0x6B4F2E, dark: 0xD7B884)
    static let water = hex(light: 0x7FB8E0, dark: 0x3E6E99)

    /// Decision 205: what a mark near the lines is drawn on, the panels'
    /// white (``Theme/panel``), edged and lettered in ``ink`` (13.29:1 on
    /// the light, 9.64:1 on the dark #30376A): a line may be any colour
    /// the player picks, so these marks tell themselves apart by shape and
    /// by navy and white, never by a hue a line could have.
    static let markerFill = hex(light: 0xFFFFFF, dark: 0x30376A)
    /// Decision 205: a selected train's edge, the stations' warm yellow
    /// inside an ``ink`` line, where it was the accent's teal, the track's
    /// colour.
    static let trainSelection = station
    /// Decision 243: the navy edge of the line's band along a painted
    /// train, in both maps (inside the body, on its white or silver): a
    /// pale line colour (white, yellow) still shows on it.
    static let liveryBandEdge = rgb(0x262C57)

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
    ///
    /// Decision 216: with the colour-blind-safe palette on (the settings'
    /// ``LinePalette``, on the device), the safe colour nearest it
    /// (``LinePalette/safeColor(for:)``), the same in light and dark.
    static func lineColor(_ id: LineID, custom: LineColor? = nil) -> Color {
        if LinePalette.current == .colourBlindSafe {
            return rgb(LinePalette.safeColor(for: custom?.rgb ?? LineBadge.automaticColor(of: id)))
        }
        if let custom {
            return color(custom)
        }
        let colors: [Color] = [metroBlue, metroGreen, metroAmber, metroPurple, metroCyan, metroRed]
        return colors[abs(Int(id.rawValue)) % colors.count]
    }

    /// Decision 182: what a train is drawn in. A line's train in its line's
    /// colour, a freight line's in ``freightTrain``, one on no line in
    /// ``train``; all of them in ``train`` while the passenger load layer
    /// colours the track (decision 178), so that only its colours tell the
    /// loads.
    static func trainColor(_ look: TrainLook, plain: Bool = false) -> Color {
        guard !plain else { return train }
        switch look {
        case .plain: return train
        case .line(let id, let custom): return lineColor(id, custom: custom)
        case .freight: return freightTrain
        }
    }

    /// Decision 182: the time of day's tint, which the map is multiplied by
    /// (``DayNight``): the colour at its strength.
    static func tint(_ tint: DayNight.Tint) -> Color {
        Color(red: tint.colour.red, green: tint.colour.green, blue: tint.colour.blue).opacity(tint.strength)
    }

    /// Decision 182: what the time of day's tint does to what is under it
    /// (``DayNight/Tint/multiplier``), for a view drawn over the tint that
    /// darkens with the map (`colorMultiply`).
    static func dimming(_ tint: DayNight.Tint) -> Color {
        let multiplier = tint.multiplier
        return Color(red: multiplier.red, green: multiplier.green, blue: multiplier.blue)
    }

    /// A ``LineColor`` as a SwiftUI colour.
    static func color(_ line: LineColor) -> Color {
        rgb(line.rgb)
    }

    /// A packed `0xRRGGBB` as a SwiftUI colour.
    static func rgb(_ rgb: Int) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
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
    case departmentStore = "MapGlyphDepartmentStore"
    case hotel = "MapGlyphHotel"
    case amusementPark = "MapGlyphAmusementPark"
    case crowd = "MapGlyphCrowd"
    /// Decision 205: one person, the waiting passengers' count beside it;
    /// the crowding set's one-person step (``crowd`` two, ``full`` three).
    case person = "MapGlyphPerson"
    case full = "MapGlyphFull"
    case warning = "MapGlyphWarning"
    /// ``warning``'s outline without its cut-out mark, drawn under it.
    case warningSolid = "MapGlyphWarningSolid"
    /// A sight's rating (decision 174).
    case star = "MapGlyphStar"
    /// Decision 246: where a city's request points, a flag.
    case request = "MapGlyphRequest"
    /// Decision 182: a typhoon blows over the station, the weather map's
    /// typhoon sign.
    case typhoon = "MapGlyphTyphoon"
    /// Decision 214: a depot's garage (the station badge's), and the plate
    /// of a train leaving it or entering it (`docs/UI_THEME.md` 機廠).
    case depot = "MapGlyphDepot"
    case depotOut = "MapGlyphDepotOut"
    case depotIn = "MapGlyphDepotIn"
    /// Decision 222: a station's shops, one, two or three bags for the
    /// convenience store, the arcade and the mall (`docs/UI_THEME.md`).
    case shops1 = "MapGlyphShops1"
    case shops2 = "MapGlyphShops2"
    case shops3 = "MapGlyphShops3"
    /// Decision 167, later: a tile of the map not bought yet, shut until
    /// the best day unlocks it, open after.
    case lock = "MapGlyphLock"
    case lockOpen = "MapGlyphLockOpen"

    /// The glyph of a station's shops at `level`.
    static func shops(_ level: StationCommerceLevel) -> MapGlyph {
        switch level {
        case .convenienceStore: .shops1
        case .arcade: .shops2
        case .mall: .shops3
        }
    }

    var image: Image {
        Image(rawValue).renderingMode(.template)
    }
}

extension LinePalette {
    /// The palette the player chose in the settings (decision 216), kept on
    /// the device: read where a line's colour is drawn, so every view and
    /// canvas draws the same; views that must redraw when it changes keep
    /// it with `@AppStorage(LinePalette.key)`.
    static var current: LinePalette {
        UserDefaults.standard.string(forKey: key).flatMap(LinePalette.init(rawValue:)) ?? .standard
    }
}
