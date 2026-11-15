import GameCore

// The real venues concerts, matches and exhibitions are held at (decision
// 768, EVENT-VENUES): Taiwan's and Hong Kong's stadiums, arenas, concert
// halls and exhibition halls. The places come from OpenStreetMap (ODbL
// 1.0), looked up by name by `tools/event-venues/build_event_venues.py`,
// which writes `tools/event-venues/event_venues.json`;
// `EventVenueCatalogTests` checks this table against that file. The seats
// are the venues' usual capacities, rounded: a weight for how often events
// are held there.

public enum EventVenueCatalog {
    /// One venue: its key, names, kind, seats and degrees.
    public struct Venue: Sendable {
        public let id: String
        public let name: String
        public let englishName: String
        public let kind: EventVenueKind
        public let seats: Int64
        public let latitude: Double
        public let longitude: Double

        init(_ id: String, _ name: String, _ englishName: String, _ kind: EventVenueKind, _ seats: Int64, _ latitude: Double, _ longitude: Double) {
            self.id = id
            self.name = name
            self.englishName = englishName
            self.kind = kind
            self.seats = seats
            self.latitude = latitude
            self.longitude = longitude
        }

        /// Its name in `language`.
        public func title(in language: DisplayLanguage) -> String {
            language.text(englishName, name)
        }
    }

    public static let venues: [Venue] = [
        Venue("tw01", "臺北大巨蛋", "Taipei Dome", .stadium, 40_000, 25.042388, 121.559582),
        Venue("tw02", "臺北小巨蛋", "Taipei Arena", .arena, 15_000, 25.050717, 121.550127),
        Venue("tw03", "臺北田徑場", "Taipei Municipal Stadium", .stadium, 20_000, 25.049596, 121.551736),
        Venue("tw04", "天母棒球場", "Tianmu Baseball Stadium", .stadium, 10_000, 25.113699, 121.533047),
        Venue("tw05", "臺北和平籃球館", "Taipei Heping Basketball Gymnasium", .arena, 7_000, 25.021591, 121.545517),
        Venue("tw06", "臺北流行音樂中心", "Taipei Music Center", .arena, 5_000, 25.052381, 121.599535),
        Venue("tw07", "新莊棒球場", "Xinzhuang Baseball Stadium", .stadium, 12_000, 25.041085, 121.447772),
        Venue("tw08", "新莊體育館", "Xinzhuang Gymnasium", .arena, 6_500, 25.040767, 121.451667),
        Venue("tw09", "林口體育館", "Linkou Arena", .arena, 15_000, 25.034582, 121.383495),
        Venue("tw10", "桃園國際棒球場", "Taoyuan International Baseball Stadium", .stadium, 20_000, 25.000947, 121.200405),
        Venue("tw11", "桃園巨蛋", "Taoyuan Arena", .arena, 15_000, 24.995174, 121.323055),
        Venue("tw12", "新竹市立棒球場", "Hsinchu Baseball Stadium", .stadium, 10_000, 24.806758, 120.960844),
        Venue("tw13", "臺中洲際棒球場", "Taichung Intercontinental Baseball Stadium", .stadium, 20_000, 24.199348, 120.685009),
        Venue("tw15", "斗六棒球場", "Douliu Baseball Stadium", .stadium, 15_000, 23.717517, 120.536453),
        Venue("tw16", "臺南市立棒球場", "Tainan Municipal Baseball Stadium", .stadium, 11_000, 22.980392, 120.206224),
        Venue("tw17", "澄清湖棒球場", "Chengcing Lake Baseball Stadium", .stadium, 20_000, 22.654474, 120.35891),
        Venue("tw18", "國家體育場", "National Stadium", .stadium, 55_000, 22.702825, 120.294969),
        Venue("tw19", "高雄巨蛋", "Kaohsiung Arena", .arena, 15_000, 22.66866, 120.301905),
        Venue("tw20", "高雄流行音樂中心", "Kaohsiung Music Center", .arena, 6_000, 22.617934, 120.289793),
        Venue("tw21", "南港展覽館", "Taipei Nangang Exhibition Center", .exhibitionHall, 30_000, 25.056543, 121.618176),
        Venue("tw22", "臺北世貿中心展覽一館", "Taipei World Trade Center Exhibition Hall 1", .exhibitionHall, 20_000, 25.034034, 121.562211),
        Venue("tw23", "高雄展覽館", "Kaohsiung Exhibition Center", .exhibitionHall, 20_000, 22.607826, 120.298463),
        Venue("hk01", "啟德主場館", "Kai Tak Stadium", .stadium, 50_000, 22.322213, 114.197356),
        Venue("hk02", "啟德體藝館", "Kai Tak Arena", .arena, 10_000, 22.325818, 114.196869),
        Venue("hk03", "香港體育館", "Hong Kong Coliseum", .arena, 12_500, 22.301283, 114.181958),
        Venue("hk04", "香港大球場", "Hong Kong Stadium", .stadium, 40_000, 22.27318, 114.188947),
        Venue("hk05", "伊利沙伯體育館", "Queen Elizabeth Stadium", .arena, 3_500, 22.275155, 114.178899),
        Venue("hk06", "香港會議展覽中心", "Hong Kong Convention and Exhibition Centre", .exhibitionHall, 20_000, 22.282636, 114.172466),
        Venue("hk07", "亞洲國際博覽館", "AsiaWorld-Expo", .exhibitionHall, 14_000, 22.321438, 113.943248),
    ]

    /// The venue of key `id`, or `nil`.
    public static func venue(_ id: String) -> Venue? {
        venues.first { $0.id == id }
    }

    /// The venues that lie inside a world of `bounds` laid over the Earth as
    /// `frame` says.
    public static func venues(in frame: RealWorldFrame, bounds: WorldBounds) -> [EventVenue] {
        venues.compactMap { venue in
            let position = frame.worldPosition(latitude: venue.latitude, longitude: venue.longitude)
            guard position.x >= 0, position.y >= 0, position.x < Double(bounds.width), position.y < Double(bounds.height) else { return nil }
            return EventVenue(id: venue.id, kind: venue.kind,
                              point: PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded())), seats: venue.seats)
        }
    }
}
