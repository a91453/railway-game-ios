import GameCore

// Decision 802: what the 3D map draws differently by where its map is,
// in one place. Until now three things each asked the map's anchor on
// their own: whose streets (decision 732's ``Map3DStreetRegion``), whether
// the ground is under snow and which gauge the rails are laid at (decision
// 799). The buildings asked nothing, so Rovaniemi's stood under Taiwan's
// water tanks and sheet-steel rooftop rooms, in Taiwan's tile colours.
// Only what is drawn changes, and all of it comes from the map's anchor,
// so no save records any of it; a map with no anchor (the generated ones)
// and every map of Taiwan is drawn as it was.

/// Decision 802: the look of the place a 3D map is of.
public struct Map3DRegionLook: Sendable, Equatable {
    /// Whose streets it draws (decision 732).
    public let streets: Map3DStreetRegion
    /// Whose buildings the city is drawn as.
    public let buildings: Buildings
    /// Whether its ground and roofs are under snow (decision 799).
    public let snow: Bool
    /// The gauge its rails are laid at, metres (decision 799).
    public let gauge: Float

    /// Taiwan's, which every map without an anchor is drawn as.
    public static let taiwan = Map3DRegionLook(streets: .taiwan, buildings: .taiwan, snow: false, gauge: Map3DTrackGauge.cape)

    /// The look of `world`'s map.
    public init(world: GameWorld) {
        self = world.geoAnchor.map(Self.init(anchor:)) ?? .taiwan
    }

    /// The look round `anchor`.
    /// - Hong Kong's streets and buildings within 22.1–22.6° N and
    ///   113.8–114.5° E, which holds the whole territory and none of
    ///   Taiwan (Kinmen is at 118.3° E); decision 812 its buildings.
    /// - Finland's streets, buildings and 1,524 mm gauge within
    ///   59.5–70.2° N and 19.0–31.6° E.
    /// - FUKUOKA-STREETS: Japan's streets and buildings within 24–46° N and
    ///   east of 122.5° E (Yonaguni, Japan's westernmost, is at 123.0° E;
    ///   Taiwan's easternmost islet at 122.1° E).
    /// - Snow north of 60° N (Rovaniemi is at 66.5°; Taiwan and Hong Kong
    ///   are south of 26°), whatever the country.
    public init(anchor: GeoAnchor) {
        let hongKong = 221_000_000...226_000_000 ~= anchor.latitude && 1_138_000_000...1_145_000_000 ~= anchor.longitude
        let finland = 595_000_000...702_000_000 ~= anchor.latitude && 190_000_000...316_000_000 ~= anchor.longitude
        let japan = 240_000_000...460_000_000 ~= anchor.latitude && 1_225_000_000...1_460_000_000 ~= anchor.longitude
        self.init(streets: hongKong ? .hongKong : finland ? .finland : japan ? .japan : .taiwan,
                  buildings: hongKong ? .hongKong : finland ? .nordic : japan ? .japan : .taiwan,
                  snow: anchor.latitude >= 600_000_000, gauge: finland ? Map3DTrackGauge.finnish : Map3DTrackGauge.cape)
    }

    init(streets: Map3DStreetRegion, buildings: Buildings, snow: Bool, gauge: Float) {
        self.streets = streets
        self.buildings = buildings
        self.snow = snow
        self.gauge = gauge
    }

    /// Decision 802: whose buildings the city's are drawn as: the real
    /// outlines (decisions 239 and 389) and the houses the game lays along
    /// the roads (decisions 263 and 385).
    public enum Buildings: Sendable, Equatable {
        /// 透天厝 and blocks of flats in tile, a water tank or a sheet-steel
        /// room on the roof, arcades, window grilles and blade signs.
        case taiwan
        /// Finland's: wooden houses of one or two floors under a pitched
        /// roof, in red ochre, yellow ochre, white and grey; plastered and
        /// brick blocks of flats under a flat roof; nothing on the roofs,
        /// and nothing hung on the street fronts.
        case nordic
        /// Decision 812: Hong Kong's: slender towers of flats in pale
        /// pastels with their lift and tank rooms on the roof; walk-up
        /// tenements (唐樓) in faded mosaic, shops below and huts on the
        /// roof; offices walled in blue-green glass; grey concrete roofs.
        case hongKong
        /// FUKUOKA-STREETS: Japan's: houses of one or two floors under a
        /// pitched roof, blocks of flats and offices under flat ones,
        /// nothing on the roofs, shops opening straight on the pavement
        /// (no arcades) with their signs hung out, no Taiwanese temple
        /// (a shrine or a temple is drawn as a public building).
        case japan

        /// Whether a house's roof has a water tank or a sheet-steel room
        /// (decisions 235 and 267).
        var hasRoofClutter: Bool { self == .taiwan }

        /// Whether the street fronts have window grilles, air
        /// conditioners and blade signs (decision 610). Decision 812:
        /// Hong Kong's too.
        var hasStreetFronts: Bool { self != .nordic }

        /// Decision 812: whether shops stand under arcades (騎樓) and
        /// rooms are built on house roofs: Taiwan's. Hong Kong's
        /// tenements open straight on the pavement, and their huts are
        /// drawn with their roofs (``Map3DScene/Builder/addHongKongRoof``).
        var hasArcades: Bool { self == .taiwan }

        /// Whether a low house stands under a pitched roof.
        var pitchesLowRoofs: Bool { self == .nordic || self == .japan }

        /// FUKUOKA-STREETS: whether a hall tagged as a temple is drawn as
        /// Taiwan's (decision 235's swallowtail roof): not in Finland
        /// (decision 802) or Japan.
        var drawsTaiwanTemples: Bool { self == .taiwan || self == .hongKong }
    }
}
