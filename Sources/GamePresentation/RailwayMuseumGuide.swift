import GameCore

/// Decision 696: what the railway museum's page shows, exhibit by exhibit:
/// the types of train on show (``PlacedBuilding/exhibits``), each with the
/// catalog's figures and, when the train garage has it (``Map3DShowcase``),
/// the key that opens it there in 3D; then the types the company can buy
/// here but has never owned, as silhouettes, with what brings them in.
public struct RailwayMuseumGuide: Equatable, Sendable {
    public struct Item: Equatable, Identifiable, Sendable {
        public let type: TrainType
        /// On show in the museum; a silhouette when not.
        public let isShown: Bool
        public let name: String
        public let family: String
        public let capacityPerCar: Int64
        public let topSpeed: Int64
        /// The train garage's entry that shows it in 3D, for an exhibit
        /// the 3D map draws with a model of its own.
        public let showcaseKey: String?
        /// Whether its track in the yard is before the hall or under a
        /// shed, for an exhibit that stands there (the first twelve).
        public let place: String?

        public var id: TrainType { type }
    }

    public let items: [Item]
    /// How many are on show.
    public let shown: Int
    /// "On show: 5 types of train · 2.25★ · today 120 visitors, yesterday 96".
    public let summary: String
    /// What a new exhibit does, or that the museum is full of what counts.
    public let hint: String

    /// `world`'s museum, its stars and visitors as `row` gives them (the
    /// museum's row of the sights panel, so the two say the same; its own
    /// stars and yesterday's count without one); `nil` when it has none.
    public init?(world: GameWorld, row: AttractionRow? = nil, in language: DisplayLanguage) {
        guard let museum = world.railwayMuseum else { return nil }
        func item(_ type: TrainType, track: Int?) -> Item {
            let card = world.trainTypeCard(type)
            // The set its head car is drawn as in the yard, which the garage lists.
            let own = Map3DTrainSet.key(type: type, performance: type.spec.performance ?? .standard)
            let key = Map3DTrainSet.set(forKey: own, count: Map3DRailwayMuseum.cars(of: own), locked: [])?.key ?? own
            var place: String?
            if let track, track < Map3DRailwayMuseum.mostShown {
                place = track < Map3DRailwayMuseum.hallTracks
                    ? language.text("On track \(track + 1), before the hall", "在館前第 \(track + 1) 股展示線")
                    : language.text("On track \(track + 1), under the car shed", "在車庫第 \(track + 1) 股展示線")
            }
            return Item(type: type, isShown: track != nil, name: type.title(in: language), family: TrainFamily(type).title(in: language),
                        capacityPerCar: card.capacityPerCar, topSpeed: card.topSpeed,
                        showcaseKey: track != nil && Map3DShowcase.entry(key) != nil ? key : nil, place: place)
        }
        let exhibits = museum.exhibits.enumerated().map { item($1, track: $0) }
        let waiting = RollingStockCatalog(world: world).entries.map(\.type).filter { !museum.exhibits.contains($0) }.map { item($0, track: nil) }
        items = exhibits + waiting
        shown = exhibits.count
        let stars = row?.starsText ?? StationMasterAdvice.starsText(Tourism.museumStars(exhibits: shown))
        let visitors = row.map { language.text("today \($0.today), yesterday \($0.yesterday)", "今天 \($0.today) 人、昨天 \($0.yesterday) 人") }
            ?? language.text("yesterday \(museum.visitors)", "昨天 \(museum.visitors) 人")
        summary = language.text(
            "\(shown) type\(shown == 1 ? "" : "s") of train on show · \(stars) · visitors \(visitors)",
            "展示 \(shown) 種列車・\(stars)・遊客\(visitors)"
        )
        if shown == 0 {
            hint = language.text("Each type of train your company owns goes on show the next day and raises the museum's stars.",
                                 "公司擁有的每一種列車，隔天會進館展示，博物館的星等跟著提高。")
        } else if shown < Tourism.exhibitsCounted {
            hint = language.text("Buy a type you have never owned and it goes on show the next day, raising the museum's stars.",
                                 "買一種沒擁有過的列車，隔天進館展示，博物館的星等再提高。")
        } else {
            hint = language.text("The yard is full: twelve types stand on its tracks. Later ones are kept in the hall.",
                                 "展示線停滿了：十二種列車都在軌道上。之後的收在館內。")
        }
    }
}
