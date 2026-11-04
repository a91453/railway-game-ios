import GameCore

// Where Taiwan's named festivals are held on a real-world map (decision
// 576). Three of the four places are sights the game already has
// (`AttractionCatalog`, whose coordinates come from OpenStreetMap, ODbL
// 1.0): Dajia Jenn Lann Temple (`t062`, where the Mazu pilgrimage sets
// out), the Pingxi sky lanterns (`p01`) and Taipei 101 (`t001`, the New
// Year's Eve fireworks). The Mid-Autumn barbecues are by the Keelung River
// at Dajia Riverside Park (大佳河濱公園); its coordinates are read off the
// map by eye, not from a source: UNVERIFIED.

public enum FestivalCatalog {
    /// One festival's place: its sight's key in ``AttractionCatalog``, or its
    /// own degrees.
    struct Place {
        let kind: FestivalKind
        let spot: String?
        let latitude: Double
        let longitude: Double
    }

    static let places: [Place] = [
        Place(kind: .mazuProcession, spot: "t062", latitude: 0, longitude: 0),
        Place(kind: .lanternFestival, spot: "p01", latitude: 0, longitude: 0),
        Place(kind: .newYearsEve, spot: "t001", latitude: 0, longitude: 0),
        Place(kind: .midAutumn, spot: nil, latitude: 25.0736, longitude: 121.5353),
    ]

    /// The places that lie inside a world of `bounds` laid over the Earth as
    /// `frame` says.
    public static func sites(in frame: RealWorldFrame, bounds: WorldBounds) -> [FestivalSite] {
        places.compactMap { place in
            var latitude = place.latitude, longitude = place.longitude
            if let key = place.spot, let spot = AttractionCatalog.spots.first(where: { $0.id == key }) {
                latitude = spot.latitude
                longitude = spot.longitude
            }
            let position = frame.worldPosition(latitude: latitude, longitude: longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height) else { return nil }
            return FestivalSite(kind: place.kind, point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())))
        }
    }
}

extension FestivalKind {
    /// The festival's name.
    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .mazuProcession: language.text("Dajia Mazu Pilgrimage", "大甲媽祖遶境")
        case .lanternFestival: language.text("Lantern Festival", "元宵燈會")
        case .newYearsEve: language.text("New Year's Eve countdown", "跨年晚會")
        case .midAutumn: language.text("Mid-Autumn moon viewing", "中秋賞月烤肉")
        }
    }

    /// When in the day the crowd comes: empty for all day.
    public func hoursText(in language: DisplayLanguage) -> String {
        guard hours != 0..<24 else { return "" }
        let end = hours.upperBound == 24 ? "24:00" : "\(hours.upperBound):00"
        return language.text(" It draws crowds from \(hours.lowerBound):00 to \(end).", "人潮多在 \(hours.lowerBound):00 到 \(end)。")
    }
}
