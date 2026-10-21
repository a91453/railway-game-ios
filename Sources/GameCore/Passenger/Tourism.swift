// Sights and tourists (ARCHITECTURE decision 174): the second demand curve,
// beside the commuters'. Native: the reference has no tourism rules (its
// OpenWorld destination catalog only lists places), so the stars, the
// seasons and the shop are this project's own, after the idea of A-Train's
// sightseeing development.
//
// An attraction has a base rating in hundredths of a star (100 to 500) and
// may have a souvenir shop of level 0 to 2 (a quarter star a level, up to
// five stars). Every day its rating draws a number of potential tourists
// (300, 800, 2,000, 4,500 and 9,000 at one to five stars, in between by
// line); the day of the week or a holiday, the season of its kind, the
// weather and a typhoon scale them; a fifth of them (``Tourism/captureRate``)
// are the ones a railway can fetch. They set out from the sources, the
// outside connections and the five stations with the most residents, in
// proportion to their weight, and ride the attraction's station by the
// morning's scenic curve and back by the afternoon's, as any other passenger
// of the passenger model: they pay the fare, change trains and crowd them.
//
// Everything is whole numbers and thousandths.

public struct AttractionID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static func < (lhs: AttractionID, rhs: AttractionID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kind of place an attraction is, which sets its season.
public enum AttractionKind: String, CaseIterable, Codable, Sendable {
    case coast
    case mountain
    case hotSpring
    case town
}

/// A place tourists go to.
public struct Attraction: Hashable, Sendable {
    public let id: AttractionID
    public let name: String
    public let englishName: String
    public let point: PlanPoint
    public let kind: AttractionKind
    /// The rating before any shop, in hundredths of a star, 100 to 500.
    public let baseStars: Int
    /// The souvenir shop's level, 0 to ``Tourism/maximumSouvenirLevel``.
    public internal(set) var souvenir: Int
    /// The tourists of the day that last ended, and of the year so far and
    /// the year before (a year is 360 days).
    public internal(set) var yesterday: Int64
    public internal(set) var thisYear: Int64
    public internal(set) var lastYear: Int64

    public init(id: AttractionID, name: String, englishName: String, point: PlanPoint, kind: AttractionKind, baseStars: Int) {
        self.id = id
        self.name = name
        self.englishName = englishName
        self.point = point
        self.kind = kind
        self.baseStars = baseStars
        souvenir = 0
        yesterday = 0
        thisYear = 0
        lastYear = 0
    }

    /// This attraction with a souvenir shop of `level`, to ask what it would do.
    public func withSouvenir(level: Int) -> Attraction {
        var copy = self
        copy.souvenir = level
        return copy
    }

    /// The rating now, in hundredths of a star.
    public var stars: Int {
        min(500, baseStars + Tourism.starsPerSouvenirLevel * souvenir)
    }
}

/// Why an attraction draws no tourists today, or `ok`.
public enum AttractionStatus: String, Hashable, Sendable {
    case ok
    /// No station within 800 m with a passenger line calling at it.
    case noStation
    /// A station there, but no source station can ride to it.
    case noSource
    /// A typhoon blows over it today.
    case typhoon
}

/// The world's attractions (decision 174).
public struct Tourism: Hashable, Sendable {
    public internal(set) var attractions: [Attraction]
    /// The year the counters are for (day ÷ 360).
    public internal(set) var year: Int64
    public internal(set) var nextID: Int

    public static let maximumSouvenirLevel = 2
    /// What a hotel within ``SubsidiaryRules/reach`` of an attraction adds to
    /// its rating, in hundredths of a star, and how many count (decision
    /// 174, a later fix): two hotels, half a star.
    public static let starsPerHotel = 25
    public static let hotelsCounted = 2
    /// What a sightseeing train (``TrainType/isSightseeing``, decision 286)
    /// calling at a station within ``reach`` of an attraction adds to its
    /// rating, in hundredths of a star: half a star, however many call.
    public static let starsPerSightseeingTrain = 50
    /// The share of an attraction's tourists who stay the night in a hotel
    /// near it, in thousandths (shared among the hotels there).
    public static let hotelStayPermille: Int64 = 80
    public static let starsPerSouvenirLevel = 25
    /// What a level of the shop costs: $300,000, in cents.
    public static let souvenirCost: Int64 = 30_000_000
    /// What a tourist spends in the shop, in cents, times its level.
    public static let spendPerLevel: Int64 = 400
    /// A shop's upkeep a day, in hundred-thousandths of what it cost.
    public static let upkeepPerDay: Int64 = 50
    /// How close a station must be to serve an attraction: 800 m.
    public static let reach: Int64 = Land.catchmentRadius
    /// The share of potential tourists a railway fetches, in thousandths.
    public static let captureRate: Int64 = 200
    /// A source station of the outside counts as this many residents.
    public static let outsideWeight: Int64 = 200_000
    public static let busiestSources = 5
    /// The most a world has (decision 250: from 64, so that the whole of
    /// Taiwan holds every sight of the app's catalog, and a blank map that
    /// buys its map five for each of its 25 tiles).
    public static let maximumAttractions = 256
    static let potential: [Int64] = [300, 800, 2_000, 4_500, 9_000]

    public init(attractions: [Attraction] = [], year: Int64 = 0, nextID: Int = 1) {
        self.attractions = attractions
        self.year = year
        self.nextID = nextID
    }

    /// Potential tourists a day at `stars` hundredths of a star.
    public static func potentialTourists(stars: Int) -> Int64 {
        let clamped = max(100, min(500, stars))
        let low = clamped / 100 - 1
        guard low < 4 else { return potential[4] }
        let into = Int64(clamped - 100 * (low + 1))
        return potential[low] + (potential[low + 1] - potential[low]) * into / 100
    }

    /// The day's factor, in thousandths: a holiday, a Saturday, a Sunday or
    /// a weekday.
    public static func dayFactor(weekday: Int, holiday: Bool) -> Int64 {
        if holiday { return 2_000 }
        switch weekday {
        case 6: return 1_600
        case 0: return 1_300
        default: return 600
        }
    }

    /// The season's factor of `kind` in `month` (1 to 12), in thousandths.
    public static func seasonFactor(_ kind: AttractionKind, month: Int) -> Int64 {
        switch kind {
        case .coast:
            if (6...8).contains(month) { return 1_500 }
            if month == 12 || month <= 2 { return 500 }
        case .mountain:
            if month == 10 || month == 11 { return 1_300 }
            if month == 1 || month == 2 { return 1_200 }
            if month == 7 || month == 8 { return 800 }
        case .hotSpring:
            if month >= 11 || month <= 2 { return 1_400 }
            if (6...8).contains(month) { return 700 }
        case .town:
            break
        }
        return 1_000
    }

    /// The tourists who set out for an attraction of `stars` on a day with
    /// these factors (all in thousandths), rounded half up.
    public static func tourists(stars: Int, day: Int64, season: Int64, weather: Int64) -> Int64 {
        let scale: Int64 = 1_000_000_000_000
        return (potentialTourists(stars: stars) * day * season * weather * captureRate + scale / 2) / scale
    }

    /// What the day's tourists spend at a shop of `level`.
    public static func shopRevenue(tourists: Int64, level: Int) -> Money {
        Money(tourists * spendPerLevel * Int64(level))
    }
}

/// The tourists' trips between stations, for one day: by origin and then
/// destination, outbound and back.
struct TouristFlows: Sendable {
    struct Pair: Sendable {
        var outbound: Int64 = 0
        var back: Int64 = 0
    }

    var pairs: [StationID: [StationID: Pair]] = [:]

    var isEmpty: Bool { pairs.isEmpty }

    func trips(from origin: StationID, to destination: StationID) -> Int64 {
        guard let pair = pairs[origin]?[destination] else { return 0 }
        return pair.outbound + pair.back
    }

    /// The pair's trips in each hour: the outbound by the scenic arrival
    /// curve of the day, the way back by its departure curve.
    func hourly(from origin: StationID, to destination: StationID) -> [Int64] {
        guard let pair = pairs[origin]?[destination] else { return Array(repeating: 0, count: 24) }
        let out = GameWorld.apportion(pair.outbound, by: Self.weights(arrival: true))
        let back = GameWorld.apportion(pair.back, by: Self.weights(arrival: false))
        return zip(out, back).map { $0 + $1 }
    }

    private static func weights(arrival: Bool) -> [Int64] {
        let shape = arrival ? StationDemandKind.scenic.arrivalShape : StationDemandKind.scenic.departureShape
        return (0..<24).map { StationDemand.dayShape[$0] * shape[$0] }
    }

    mutating func add(outbound: Int64, back: Int64, from origin: StationID, to destination: StationID) {
        var pair = pairs[origin]?[destination] ?? Pair()
        pair.outbound += outbound
        pair.back += back
        pairs[origin, default: [:]][destination] = pair
    }
}

extension GameWorld {
    // MARK: - Commands

    /// Turns tourism on with these attractions, or off with `nil`
    /// (decision 174). Free. Each attraction is numbered from 1 in the
    /// order given and starts with no shop and no tourists.
    public mutating func setTourism(_ attractions: [Attraction]?) {
        // The shops go with the attractions they were in: their records
        // are written off (a later fix: a record naming a shop that no
        // longer exists made the save unloadable).
        for attraction in tourism?.attractions ?? [] where attraction.souvenir > 0 {
            disposeAsset(.souvenirShop, owner: attraction.id.rawValue)
        }
        guard let attractions, !attractions.isEmpty else {
            guard tourism != nil else { return }
            tourism = nil
            passengerPlan = PassengerPlanCache()
            return
        }
        var list: [Attraction] = []
        for (offset, source) in attractions.prefix(Tourism.maximumAttractions).enumerated() {
            list.append(Attraction(id: AttractionID(rawValue: offset + 1), name: source.name, englishName: source.englishName,
                                   point: source.point, kind: source.kind, baseStars: max(100, min(500, source.baseStars))))
        }
        tourism = Tourism(attractions: list, year: dayIndex(of: clock.now) / FinancePeriod.year.days, nextID: list.count + 1)
        passengerPlan = PassengerPlanCache()
    }

    /// Turns tourism on for a blank map with three to five attractions drawn
    /// from `seed` for each tile of ``MapExpansion/tileLength`` (16.384 km)
    /// a side (decision 174; decision 250: by the map's area, so a map that
    /// buys its map has them across all its tiles): on a cell of leisure
    /// land first, then on a steep slope or by the water (a cell next to
    /// water), and, if the tile has too few of those, anywhere inside it at
    /// least 600 m from its edge. Two are at least 3 km apart. Each has a
    /// kind that fits where it stands (water: coast, steep: mountain,
    /// leisure: a hot spring or a town), a name from its kind's list not
    /// used yet while one is left, and 2 to 4 stars.
    ///
    /// The tile with the world's middle draws as the whole map did before
    /// decision 250, so a map of one tile has the same places, kinds and
    /// stars (the names, from longer lists, differ), and the middle tile of
    /// a map that buys its map the usual map's.
    public mutating func foundAttractions(seed: UInt32) {
        let draw = SeedDraw(seed: seed)
        let tile = MapExpansion.tileLength
        let columns = (bounds.width + tile - 1) / tile, rows = (bounds.height + tile - 1) / tile
        let middle = (row: bounds.height / 2 / tile, column: bounds.width / 2 / tile)
        enum Place { case leisure, water, steep, open }
        var candidates: [(point: PlanPoint, place: Place)] = []
        for cell in land.cells where cell.use == .leisure {
            candidates.append((cellCentre(row: cell.row, column: cell.column), .leisure))
        }
        for run in terrain.steep {
            for column in run.column..<run.column + run.count { candidates.append((cellCentre(row: run.row, column: column), .steep)) }
        }
        for run in terrain.water {
            // The cell beside the run's west end, if it is dry.
            let beside = run.column - 1
            if beside >= 0, !terrain.isWater(row: run.row, column: beside) { candidates.append((cellCentre(row: run.row, column: beside), .water)) }
        }
        let margin: Int64 = 600 * WorldCoordinate.unitsPerMetre
        var chosen: [(point: PlanPoint, place: Place, key: String, index: Int)] = []
        func far(_ point: PlanPoint) -> Bool {
            let spacing = 3_000 * WorldCoordinate.unitsPerMetre
            return chosen.allSatisfy { other in
                let dx = other.point.x - point.x, dy = other.point.y - point.y
                return dx * dx + dy * dy >= spacing * spacing
            }
        }
        // The middle tile first, then the others row by row.
        var tiles = [middle]
        for row in 0..<rows {
            for column in 0..<columns where (row, column) != middle { tiles.append((row, column)) }
        }
        for (row, column) in tiles {
            let key = (row, column) == middle ? "tourism." : "tourism.\(row).\(column)."
            let west = column * tile, north = row * tile
            let east = min(west + tile, bounds.width), south = min(north + tile, bounds.height)
            let inside = candidates.filter { $0.point.x >= west && $0.point.x < west + tile && $0.point.y >= north && $0.point.y < north + tile }
            var wanted = Int(draw.roll("\(key)count", in: 3...5))
            if columns * rows > 1 {
                // A part of a tile at the world's edge: as many for its area.
                let area = (east - west) * (south - north)
                wanted = Int((Int64(wanted) * area + tile * tile / 2) / (tile * tile))
            }
            var found = 0
            var attempt = 0
            while found < wanted, attempt < 200, chosen.count < Tourism.maximumAttractions {
                defer { attempt += 1 }
                let point: PlanPoint
                let place: Place
                if !inside.isEmpty, attempt < 100 {
                    let pick = inside[Int(draw.roll("\(key)pick.\(attempt)", in: 0...Int64(inside.count - 1)))]
                    (point, place) = pick
                } else {
                    let x = draw.roll("\(key)x.\(attempt)", in: west + margin...max(west + margin, east - margin))
                    let y = draw.roll("\(key)y.\(attempt)", in: north + margin...max(north + margin, south - margin))
                    (point, place) = (PlanPoint(x: x, y: y), .open)
                }
                guard point.x >= 0, point.y >= 0, point.x < bounds.width, point.y < bounds.height, far(point) else { continue }
                chosen.append((point, place, key, found))
                found += 1
            }
        }
        var list: [Attraction] = []
        var used: Set<String> = []
        for (number, spot) in chosen.enumerated() {
            let kind: AttractionKind = switch spot.place {
            case .water: .coast
            case .steep: .mountain
            case .leisure: draw.roll("\(spot.key)kind.\(spot.index)", in: 0...1) == 0 ? .hotSpring : .town
            case .open: AttractionKind.allCases[Int(draw.roll("\(spot.key)kind.\(spot.index)", in: 0...3))]
            }
            let names = Self.attractionNames[kind]!
            // The drawn name, or the next one not used yet.
            let drawn = Int(draw.roll("\(spot.key)name.\(spot.index)", in: 0...Int64(names.count - 1)))
            let name = (0..<names.count).lazy.map { names[(drawn + $0) % names.count] }.first { !used.contains($0.chinese) } ?? names[drawn]
            used.insert(name.chinese)
            list.append(Attraction(id: AttractionID(rawValue: number + 1), name: name.chinese, englishName: name.english, point: spot.point,
                                   kind: kind, baseStars: Int(draw.roll("\(spot.key)stars.\(spot.index)", in: 2...4)) * 100))
        }
        setTourism(list)
    }

    private func cellCentre(row: Int, column: Int) -> PlanPoint {
        PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
    }

    /// A blank map's names of each kind (decision 250: sixteen of each, so
    /// a map of many tiles repeats few; the first three are decision 174's).
    static let attractionNames: [AttractionKind: [(chinese: String, english: String)]] = [
        .coast: [
            ("海岬燈塔", "Cape Lighthouse"), ("白沙灣", "White Sand Bay"), ("礁岩海岸", "Reef Coast"), ("漁港碼頭", "Fishing Harbour"),
            ("夕陽海堤", "Sunset Seawall"), ("貝殼沙灘", "Shell Beach"), ("海蝕洞", "Sea Caves"), ("紅樹林", "Mangrove Shore"),
            ("觀浪步道", "Wave-watching Trail"), ("濕地鳥園", "Wetland Bird Park"), ("藍色海灣", "Blue Bay"), ("防風林海岸", "Windbreak Coast"),
            ("岬角草原", "Headland Meadow"), ("鹽田", "Salt Pans"), ("潮間帶", "Tidal Flats"), ("沙丘", "Sand Dunes"),
        ],
        .mountain: [
            ("雲海山頂", "Sea-of-Clouds Peak"), ("森林步道", "Forest Trail"), ("高山湖", "Alpine Lake"), ("瀑布谷", "Waterfall Valley"),
            ("茶園山坡", "Tea Hills"), ("神木林", "Giant Tree Grove"), ("吊橋峽谷", "Suspension Bridge Gorge"), ("楓紅山谷", "Maple Valley"),
            ("觀日峰", "Sunrise Peak"), ("竹林小徑", "Bamboo Path"), ("櫻花林道", "Cherry Blossom Road"), ("螢火蟲谷", "Firefly Valley"),
            ("水庫湖畔", "Reservoir Shore"), ("石壁步道", "Cliff Trail"), ("高山牧場", "Highland Ranch"), ("星空草原", "Starlit Meadow"),
        ],
        .hotSpring: [
            ("溫泉鄉", "Hot Spring Village"), ("湯谷溫泉", "Hot Valley Spa"), ("碧潭溫泉", "Green Pool Spa"), ("冷泉公園", "Cold Spring Park"),
            ("泥漿溫泉", "Mud Spring"), ("溪畔湯屋", "Riverside Baths"), ("硫磺谷", "Sulphur Valley"), ("地熱谷", "Thermal Valley"),
            ("山中湯宿", "Mountain Spa Inn"), ("竹林溫泉", "Bamboo Grove Spa"), ("碳酸泉", "Soda Spring"), ("雲霧溫泉", "Misty Spa"),
            ("櫻花溫泉", "Blossom Spa"), ("足湯廣場", "Foot Bath Square"), ("野溪溫泉", "Wild Creek Spring"), ("溫泉老街", "Spa Street"),
        ],
        .town: [
            ("老街", "Old Street"), ("古城門", "Old Town Gate"), ("市集廣場", "Market Square"), ("夜市", "Night Market"),
            ("媽祖廟", "Mazu Temple"), ("糖廠", "Sugar Mill"), ("舊車站", "Old Station"), ("眷村", "Military Village"),
            ("紅磚古厝", "Red Brick Mansion"), ("文創園區", "Creative Park"), ("藝術村", "Art Village"), ("主題樂園", "Theme Park"),
            ("博物館", "Museum"), ("觀光工廠", "Factory Tour"), ("燈會廣場", "Lantern Square"), ("孔廟", "Confucius Temple"),
        ],
    ]

    /// Builds the next level of attraction `id`'s souvenir shop: $300,000 a
    /// level, kept as a building asset (30 years).
    ///
    /// - Throws: ``GameError/tourismNotEnabled``,
    ///   ``GameError/unknownAttraction(_:)``, ``GameError/attractionMaxedOut``,
    ///   ``GameError/insufficientFunds(required:available:)``.
    public mutating func investInSouvenirShop(of id: AttractionID) throws(GameError) {
        guard let tourism else { throw .tourismNotEnabled }
        guard let index = tourism.attractions.firstIndex(where: { $0.id == id }) else { throw .unknownAttraction(id) }
        guard tourism.attractions[index].souvenir < Tourism.maximumSouvenirLevel else { throw .attractionMaxedOut }
        let price = Money(Tourism.souvenirCost)
        try economy.spend(price)
        self.tourism!.attractions[index].souvenir += 1
        recordSouvenirAsset(of: id, cost: price)
        passengerPlan = PassengerPlanCache()
    }

    // MARK: - Queries

    public func attraction(id: AttractionID) -> Attraction? {
        tourism?.attractions.first { $0.id == id }
    }

    /// The station that serves attraction `id`: the nearest within 800 m
    /// that a passenger line calls at and that takes passengers, or `nil`.
    public func attractionStation(of id: AttractionID) -> StationID? {
        guard let attraction = attraction(id: id) else { return nil }
        return servingStation(at: attraction.point)
    }

    func servingStation(at point: PlanPoint) -> StationID? {
        let limit = Tourism.reach * Tourism.reach
        var best: (StationID, Int64)?
        for station in stations {
            let dx = station.point.x - point.x, dy = station.point.y - point.y
            let squared = dx * dx + dy * dy
            guard squared <= limit, allowsService(at: station.id), stationDemand(of: station.id) != nil,
                  lines.contains(where: { !$0.isFreight && $0.hasTrainsCalling(at: station.id) })
            else { continue }
            if best == nil || (squared, station.id) < (best!.1, best!.0) { best = (station.id, squared) }
        }
        return best?.0
    }

    /// The company's hotels within ``SubsidiaryRules/reach`` of
    /// `attraction`.
    public func hotelsNear(_ attraction: Attraction) -> Int {
        let reach = SubsidiaryRules.reach
        return placedBuildings.count { building in
            guard building.kind == .hotel else { return false }
            let dx = building.centre.x - attraction.point.x, dy = building.centre.y - attraction.point.y
            return dx * dx + dy * dy <= reach * reach
        }
    }

    /// The rating of `attraction` now, in hundredths of a star: its own
    /// (``Attraction/stars``, with its shop), a quarter star for each of
    /// the first two hotels near it and half a star when a sightseeing
    /// train calls near it (decision 286), five stars at most.
    public func stars(of attraction: Attraction) -> Int {
        stars(of: attraction, sightseeingStops: sightseeingStops())
    }

    /// The same, given ``sightseeingStops()``, worked out once for every
    /// sight.
    func stars(of attraction: Attraction, sightseeingStops: [PlanPoint]) -> Int {
        let train = Self.isNear(attraction, any: sightseeingStops) ? Tourism.starsPerSightseeingTrain : 0
        return min(500, attraction.stars + Tourism.starsPerHotel * min(Tourism.hotelsCounted, hotelsNear(attraction)) + train)
    }

    /// Whether a sightseeing train (decision 286) calls at a station within
    /// ``Tourism/reach`` of `attraction`.
    public func hasSightseeingTrain(near attraction: Attraction) -> Bool {
        Self.isNear(attraction, any: sightseeingStops())
    }

    /// The points of the stations that take passengers where a passenger
    /// line, or one of its patterns, has a train of a sightseeing type
    /// (decision 286) to call; empty, and quick, when the company has none.
    func sightseeingStops() -> [PlanPoint] {
        let sightseeing = Set(trains.lazy.filter { $0.type?.isSightseeing == true }.map(\.id))
        guard !sightseeing.isEmpty else { return [] }
        var called = Set<StationID>()
        for line in lines where !line.isFreight {
            if line.trains.contains(where: sightseeing.contains) { called.formUnion(line.stops) }
            for pattern in line.patterns where pattern.trains.contains(where: sightseeing.contains) {
                for call in pattern.calls where line.stops.indices.contains(call) { called.insert(line.stops[call]) }
            }
        }
        return stations.lazy.filter { called.contains($0.id) && self.allowsService(at: $0.id) }.map(\.point)
    }

    static func isNear(_ attraction: Attraction, any points: [PlanPoint]) -> Bool {
        points.contains { point in
            let dx = point.x - attraction.point.x, dy = point.y - attraction.point.y
            return dx * dx + dy * dy <= Tourism.reach * Tourism.reach
        }
    }

    /// The tourists of game day `day` who stay in hotels near `attraction`,
    /// counted for one hotel's customers (decision 174): the day that has
    /// just closed as the sight counted it (``Attraction/yesterday``),
    /// any other day as expected if a station serves it.
    func hotelGuests(of attraction: Attraction, onDay day: Int64) -> Int64 {
        let tourists: Int64
        if day == dayIndex(of: clock.now) - 1 {
            tourists = attraction.yesterday
        } else {
            tourists = servingStation(at: attraction.point) == nil ? 0 : touristsExpected(for: attraction, onDay: day)
        }
        return tourists * Tourism.hotelStayPermille / 1_000 / Int64(max(1, hotelsNear(attraction)))
    }

    /// The tourists attraction `id` draws on game day `day` before the
    /// railway is asked: its rating, the day, the season, the weather and
    /// any typhoon. 0 while a typhoon blows over it.
    public func touristsExpected(at id: AttractionID, onDay day: Int64) -> Int64 {
        guard let attraction = attraction(id: id) else { return 0 }
        return touristsExpected(for: attraction, onDay: day)
    }

    /// The same for any attraction value, for example one with the next level of shop.
    public func touristsExpected(for attraction: Attraction, onDay day: Int64) -> Int64 {
        let blowing = typhoons(onDay: day).contains { $0.isActive(onDay: day) && $0.covers(attraction.point) }
        guard !blowing else { return 0 }
        let year = FinancePeriod.year.days
        let dayOfYear = day - CompanyAccounts.floorDivide(day, year) * year
        let month = Int(dayOfYear / 30) + 1
        let dayFactor = Tourism.dayFactor(weekday: StationDemand.weekday(ofDay: day), holiday: holiday(onDay: day) != nil)
        let weather: Int64 = self.weather(onDay: day) == .clear ? 1_000 : 700
        return Tourism.tourists(stars: stars(of: attraction), day: dayFactor,
                                season: Tourism.seasonFactor(attraction.kind, month: month), weather: weather)
    }

    /// Why attraction `id` draws no tourists now, or ``AttractionStatus/ok``.
    public func attractionStatus(of id: AttractionID) -> AttractionStatus {
        guard let attraction = attraction(id: id) else { return .noStation }
        let day = dayIndex(of: clock.now)
        if typhoons(onDay: day).contains(where: { $0.isActive(onDay: day) && $0.covers(attraction.point) }) { return .typhoon }
        guard let station = servingStation(at: attraction.point) else { return .noStation }
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        let sources = touristSources(excluding: station, among: touristCandidates())
        return sources.contains { reaches(from: $0.station, to: station, graph: graph) } ? .ok : .noSource
    }

    /// Whether anyone at `origin` can ride to `destination`.
    func reaches(from origin: StationID, to destination: StationID, graph: PassengerRouteGraph?) -> Bool {
        if let graph { return !passengerRouteChoices(from: origin, to: destination, graph: graph).isEmpty }
        return passengerTrip(from: origin, to: destination) != nil
    }

    /// The stations tourists could set out from, worked out once for a day's
    /// flows: those that take passengers and have demand, with whether each
    /// is an outside connection and its residents (decision 137, Phase 6a).
    func touristCandidates() -> [(station: StationID, outside: Bool, residents: Int64)] {
        stations.compactMap { candidate in
            guard allowsEntry(at: candidate.id), stationDemand(of: candidate.id) != nil else { return nil }
            return (candidate.id, isOutsideConnection(candidate.id), landCatchment(of: candidate.id)?.residents ?? 0)
        }
    }

    /// The stations tourists set out from for the attraction served by
    /// `station`, with their weight: each outside connection at
    /// ``Tourism/outsideWeight``, and the busiest ``Tourism/busiestSources``
    /// stations by residents at their residents (the two add up for a station
    /// that is both); by ascending station, never `station` itself.
    func touristSources(excluding station: StationID,
                        among candidates: [(station: StationID, outside: Bool, residents: Int64)]) -> [(station: StationID, weight: Int64)] {
        var weights: [StationID: Int64] = [:]
        var residential: [(StationID, Int64)] = []
        for candidate in candidates where candidate.station != station {
            if candidate.outside { weights[candidate.station, default: 0] += Tourism.outsideWeight }
            if candidate.residents > 0 { residential.append((candidate.station, candidate.residents)) }
        }
        residential.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        for (id, residents) in residential.prefix(Tourism.busiestSources) { weights[id, default: 0] += residents }
        return weights.keys.sorted().map { ($0, weights[$0]!) }
    }

    /// The tourists' trips on game day `day`, each attraction's tourists
    /// shared among the sources that can ride to its station (and back),
    /// `reaches` saying which pairs can ride. Empty without tourism. With a
    /// day pass on sale (decision 324), its buyers' rides on to the next
    /// sight and back too, counted as that sight's visitors, and the day's
    /// passes.
    func touristFlows(onDay day: Int64, reaches: (StationID, StationID) -> Bool)
        -> (flows: TouristFlows, arrivals: [AttractionID: Int64], passes: DayPassDay) {
        var flows = TouristFlows()
        var arrivals: [AttractionID: Int64] = [:]
        var passes = DayPassDay()
        guard let tourism else { return (flows, arrivals, passes) }
        let candidates = touristCandidates()
        var visited: [(station: StationID, tourists: [(source: StationID, count: Int64, back: Bool)])] = []
        for attraction in tourism.attractions {
            let expected = touristsExpected(for: attraction, onDay: day)
            guard expected > 0, let station = servingStation(at: attraction.point) else { continue }
            let sources = touristSources(excluding: station, among: candidates).filter { reaches($0.station, station) }
            guard !sources.isEmpty else { continue }
            let shares = Self.apportion(expected, by: sources.map(\.weight))
            var tourists: [(source: StationID, count: Int64, back: Bool)] = []
            for (source, share) in zip(sources, shares) where share > 0 {
                flows.add(outbound: share, back: 0, from: source.station, to: station)
                let back = reaches(station, source.station)
                if back {
                    flows.add(outbound: 0, back: share, from: station, to: source.station)
                }
                tourists.append((source.station, share, back))
            }
            arrivals[attraction.id] = shares.reduce(0, +)
            visited.append((station, tourists))
        }
        guard accounts.mode == .management, let price = accounts.dayPass else { return (flows, arrivals, passes) }
        // Decision 324: who buys a pass, and the rides it adds.
        let sights = tourism.attractions.compactMap { sight in servingStation(at: sight.point).map { (id: sight.id, station: $0) } }
        for (station, tourists) in visited {
            let next = nextSight(from: station, among: sights, reaches: reaches)
            let ride = next.map { passFare(from: station, to: $0.station) + passFare(from: $0.station, to: station) } ?? .zero
            for tourist in tourists {
                let journey = passFare(from: tourist.source, to: station) + (tourist.back ? passFare(from: station, to: tourist.source) : .zero)
                let buyers = tourist.count * DayPass.uptake(price: price, value: journey + ride) / 1_000
                guard buyers > 0 else { continue }
                passes.sold += buyers
                passes.journeyFares = passes.journeyFares + Money(buyers * journey.amount)
                passes.visits[station, default: 0] += buyers
                if let next {
                    flows.add(outbound: buyers, back: 0, from: station, to: next.station)
                    flows.add(outbound: 0, back: buyers, from: next.station, to: station)
                    arrivals[next.id, default: 0] += buyers
                    passes.visits[next.station, default: 0] += buyers
                    passes.rides += 2 * buyers
                    passes.rideFares = passes.rideFares + Money(buyers * ride.amount)
                }
            }
        }
        passes.sales = Self.wholeDollars(passes.sold * price.amount)
        passes.journeyFares = Self.wholeDollars(passes.journeyFares.amount)
        passes.rideFares = Self.wholeDollars(passes.rideFares.amount)
        return (flows, arrivals, passes)
    }

    /// Today's tourist trips as the passenger model reaches them now (an
    /// empty set without tourism).
    func currentTouristFlows() -> TouristFlows {
        guard tourism != nil else { return TouristFlows() }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        return world.touristFlows(onDay: dayIndex(of: clock.now)) { world.reaches(from: $0, to: $1, graph: graph) }.flows
    }

    // MARK: - Midnight

    /// Counts the tourists of the day that ended, rolls the counters at the
    /// year's end. Runs at midnight, before the day is settled.
    mutating func closeTourismDay(_ day: Int64) {
        guard var tourism, day >= 0 else { return }
        let world = self
        let graph = passengerRoutingMode == .network ? PassengerRouteGraph(world: self) : nil
        let arrived = world.touristFlows(onDay: day) { world.reaches(from: $0, to: $1, graph: graph) }.arrivals
        let year = day / FinancePeriod.year.days
        if year != tourism.year {
            for index in tourism.attractions.indices {
                tourism.attractions[index].lastYear = year == tourism.year + 1 ? tourism.attractions[index].thisYear : 0
                tourism.attractions[index].thisYear = 0
            }
            tourism.year = year
        }
        for index in tourism.attractions.indices {
            let count = arrived[tourism.attractions[index].id] ?? 0
            tourism.attractions[index].yesterday = count
            tourism.attractions[index].thisYear += count
        }
        self.tourism = tourism
    }

    /// Settles day `day`'s shop takings and upkeep as one ledger row at
    /// `time`.
    mutating func settleTourism(day: Int64, time: GameTime) {
        guard let tourism else { return }
        var revenue = Money.zero, upkeep = Money.zero
        for attraction in tourism.attractions where attraction.souvenir > 0 {
            revenue = revenue + Tourism.shopRevenue(tourists: attraction.yesterday, level: attraction.souvenir)
            let cost = Tourism.souvenirCost * Int64(attraction.souvenir)
            upkeep = upkeep + Money((cost * Tourism.upkeepPerDay + 50_000) / 100_000)
        }
        guard revenue > .zero || upkeep > .zero else { return }
        write(LedgerEntry(
            kind: .dailyTourism, time: time, amount: revenue - upkeep,
            breakdown: [
                LedgerLine(item: .tourismRevenue, amount: revenue),
                LedgerLine(item: .tourismUpkeep, amount: .zero - upkeep),
            ]
        ), day: day)
    }

    /// Records a level of attraction `id`'s souvenir shop as an asset of
    /// its own, bought now: added to the first level's record, its cost was
    /// written down on that record's days, all at once on the next day, or
    /// never once the first level was written off.
    mutating func recordSouvenirAsset(of id: AttractionID, cost: Money) {
        acquireAsset(.souvenirShop, owner: id.rawValue, cost: cost)
    }

    // MARK: - Validation

    func tourismProblem() -> String? {
        guard let tourism else { return nil }
        guard !tourism.attractions.isEmpty, tourism.attractions.count <= Tourism.maximumAttractions else {
            return "A world with tourism has one to \(Tourism.maximumAttractions) attractions."
        }
        guard zip(tourism.attractions, tourism.attractions.dropFirst()).allSatisfy({ $0.id < $1.id }),
              tourism.attractions.allSatisfy({ $0.id.rawValue >= 1 && $0.id.rawValue < tourism.nextID })
        else { return "Attractions are listed once each, by ascending ID, below the next ID." }
        for attraction in tourism.attractions {
            guard (100...500).contains(attraction.baseStars), (0...Tourism.maximumSouvenirLevel).contains(attraction.souvenir),
                  (0...Self.maximumAccrued).contains(attraction.yesterday), (0...Self.maximumAccrued).contains(attraction.thisYear),
                  (0...Self.maximumAccrued).contains(attraction.lastYear), !attraction.name.isEmpty
            else { return "An attraction's rating, shop or counts are out of range." }
            guard attraction.point.x >= 0, attraction.point.y >= 0, attraction.point.x < bounds.width, attraction.point.y < bounds.height else {
                return "An attraction lies outside the world."
            }
        }
        return nil
    }
}

// MARK: - Codable

extension Attraction: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, englishName, x, y, kind, baseStars, souvenir, yesterday, thisYear, lastYear
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(AttractionID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        englishName = try container.decode(String.self, forKey: .englishName)
        point = PlanPoint(x: try container.decode(Int64.self, forKey: .x), y: try container.decode(Int64.self, forKey: .y))
        kind = try container.decode(AttractionKind.self, forKey: .kind)
        baseStars = try container.decode(Int.self, forKey: .baseStars)
        souvenir = try container.decodeIfPresent(Int.self, forKey: .souvenir) ?? 0
        yesterday = try container.decodeIfPresent(Int64.self, forKey: .yesterday) ?? 0
        thisYear = try container.decodeIfPresent(Int64.self, forKey: .thisYear) ?? 0
        lastYear = try container.decodeIfPresent(Int64.self, forKey: .lastYear) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(englishName, forKey: .englishName)
        try container.encode(point.x, forKey: .x)
        try container.encode(point.y, forKey: .y)
        try container.encode(kind, forKey: .kind)
        try container.encode(baseStars, forKey: .baseStars)
        if souvenir != 0 { try container.encode(souvenir, forKey: .souvenir) }
        if yesterday != 0 { try container.encode(yesterday, forKey: .yesterday) }
        if thisYear != 0 { try container.encode(thisYear, forKey: .thisYear) }
        if lastYear != 0 { try container.encode(lastYear, forKey: .lastYear) }
    }
}

extension Tourism: Codable {
    private enum CodingKeys: String, CodingKey {
        case attractions, year, nextID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attractions = try container.decode([Attraction].self, forKey: .attractions)
        year = try container.decodeIfPresent(Int64.self, forKey: .year) ?? 0
        nextID = try container.decode(Int.self, forKey: .nextID)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attractions, forKey: .attractions)
        if year != 0 { try container.encode(year, forKey: .year) }
        try container.encode(nextID, forKey: .nextID)
    }
}
