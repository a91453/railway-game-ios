import GameCore

/// Worlds set up for the game website's screenshots (decision 165), opened
/// only by the Debug app's `-screenshot-scene` launch argument from the
/// screenshot UI test. Each is built from GameCore's own commands, as the
/// demos are, and run on to a moment worth showing; nothing in them is
/// drawn or staged outside the game's rules.
public enum ScreenshotScene: String, CaseIterable, Sendable {
    /// The demo map (``DemoWorld``) with freight: a freight track inside
    /// the ring, a yard at West and at East, industry beyond each, and a
    /// freight line whose train carries goods between them. Run on to the
    /// second morning just after the hour's goods came in, when both yards
    /// hold goods, the train carries a load and the first midnight has left
    /// stations short of building materials.
    case freight

    /// The demo map with two depots, one beyond West and one beyond East,
    /// and Line 1 keeping its trains at the west one (decision 221): the
    /// line panel's depot checklist, for its UI test. The high-speed demo
    /// has depots too, but takes minutes to build on a test runner.
    case depots

    /// Decision 514: the demo map on its second morning with zones in each
    /// outlook the zoning layer marks: by the demo's stations, which grew
    /// last night, schools (which the city builds) and the use the city
    /// wants least (not needed now); round a new station no train serves
    /// yet (waits for its station); and further out than any station
    /// reaches (too far). For the screenshot review of the pull request
    /// that marked them.
    case zoning

    /// Decision 524: the demo map with realistic operation, run on to its
    /// second morning, so each line's card shows its last seven days'
    /// punctuality beside Taiwan Railway's. For the screenshot review of
    /// the pull request that added it.
    case punctuality

    /// Decision 533: the demo map with a school and a hospital of the
    /// company's beside its first station, run on to half past seven on
    /// the second morning, a school day, when the students are on their
    /// way: the station panel's row of the riders they bring. For the
    /// screenshot review of the pull request that added it.
    case commute

    /// Decision 506 續二 (BADGE): the demo map on its fourth morning with
    /// West and East crowded every day and 中央 (Central) only since the
    /// second: West expanded once, its concourse mark beside its name, and
    /// Central's station size card past the people it needs but full on
    /// only three of the last seven days. The demo's ridership comes from
    /// its land and stays under 50,000 a day, so this scene sets the three
    /// stations' demand itself (the land's off, as on a map the player
    /// draws on). For the screenshot review of the pull request that drew
    /// the mark, not the website.
    case expansion

    /// Decision 536: the demo map with its first line bought as the
    /// Neiwan Line and its second as the Danhai light rail's Green
    /// Mountain Line (recorded as bought, as the app records a real line
    /// it laid), run on to the second morning: their trains drawn and
    /// named as the real lines' own. For the screenshot review of the pull
    /// request that drew them so.
    case acquired

    /// Decision 555: a real-world map of Taipei round Taipei Main Station
    /// (``taipeiMain``) or Taipei 101 (``taipei101``), a short line laid
    /// 300 m north of it so the map opens there: for the screenshots of the 3D
    /// map leaned to 60° beside its own tilt (`-screenshot-3d-view`,
    /// ``Map3DScreenshotView``), at 10:00, so the sun's shadows show.
    case taipeiMain
    case taipei101
    /// Decision 600: the same map on the Taiwan Railway's viaduct south of
    /// Taichung Station, for the screenshots of the real trains on the
    /// tracks they are assigned and the double track's one deck.
    case taichungViaduct
    /// Decision 607: the same map at the expressway interchange west of
    /// Taichung over the high-speed line, the Fazi River beside it, for
    /// the screenshots of its link roads meeting the decks at one height.
    case interchange

    /// Decision 596: the same map round the big junction 380 m east of
    /// Taipei Main Station (23 stop lines) at 10:00 and at 20:00, for the
    /// screenshots of the traffic waiting at its stop lines and the people
    /// at its crossings (`-screenshot-3d-view`), paused to go on at 10×.
    case streetStop
    case streetStopNight

    /// Decision 564: an empty real-world map round the Wenhu Line, for the
    /// Debug app's `-screenshot-buy-real trtc:BR` to buy the line on and
    /// run on to the morning (``GameSession/buyForScreenshot(_:)``, ``GameSession/runForScreenshot(until:)``):
    /// its trains each on the track to their right, as the real ones run.
    /// For the screenshot review of the pull request that put them there.
    case wenhu

    /// Decision 603: the same empty map round the Xiaobitan Branch Line,
    /// for `-screenshot-buy-real trtc:G_XBT`: its single track and its
    /// one train, as the real line's. For the screenshot review of the
    /// pull request that laid it so.
    case xiaobitan

    /// Decision 565: a new real-world game round Taipei Main Station, a
    /// line of two stations 800 m apart whose platforms are four 20 m cars
    /// long, as the platform tool builds them, and its train of four
    /// standing at the far one: for the screenshots of a train stopped
    /// with every car inside its platform, on the 2D map and the 3D one.
    case platformStop

    /// Decision 578: a new real-world game round Taipei Main Station, a
    /// line of two stations 14 km apart (a new map is 16 km wide; the longest gap it holds, over the station view's reach) with its train
    /// running to the far one: for the screenshot of the 3D follow bar's
    /// station view greyed out while the next stop is too far.
    case farStops

    /// Decision 573: the demo map, where ``prepare(_:)`` lays a depot with
    /// the depot tool off Line 2's north end (on its viaduct, so the
    /// sidings pass over the ring): Line 2 and the Ring Line both end or
    /// call near it, so the banner offers each. For the screenshot review
    /// of the pull request that added the offer.
    case depotOffer

    /// Decision 574: a new real-world game round Muzha with the Maokong
    /// Gondola built as the cable car mode lays it
    /// (``RealCableway/maokong``), run on to 10:00 of the second day, so
    /// its card has a day's account: the rope and its stations on the 2D
    /// map, and the mode's card.
    case maokong

    /// Decision 580 (FOLLOWBUS): the demo map with a road along its first
    /// station's row and a feeder bus route of two stops on it, a bus every
    /// ten minutes, run on to half past nine in the morning, when buses are
    /// out: for the screenshots of the 3D map following a bus
    /// (`-screenshot-follow-bus`).
    case followBus

    /// Decision 342 (FOLLOWXRAY): the same feeder bus route on Taipei Main
    /// Station's real city, with its real buildings along the road, for the
    /// screenshots of the followed bus seen through them.
    case followBusCity

    /// Decision 585: a new real-world game round the mouth of the Tamsui
    /// River with the Tamsui–Bali ferry opened as the transit tool's ferry
    /// mode lays it (``RealFerry/tamsuiBali``), run on to 10:00 of the
    /// second day, so its card has a day's account: the crossing and its
    /// piers on the 2D map, and the mode's card.
    case tamsuiFerry

    /// Decision 585 PR-3 (FERRY3): a new real-world game round Kaohsiung's
    /// harbour mouth with the Gushan–Cijin ferry opened as the ferry mode
    /// lays it (``RealFerry/gushanCijin``), two boats every 10 minutes,
    /// run on to 10:00 of the second day: the double-ended ferry and its
    /// piers on the 3D map.
    case gushanFerry

    /// Decision 585 PR-3: ``gushanFerry`` at 18:30 of the second day, its
    /// lamps lit at dusk.
    case gushanFerryEvening

    /// Decision 585 PR-4 (FERRYFOLLOW): ``tamsuiFerry`` three minutes on
    /// (10:03), the 10:00 boat half way over to Bali: followed at 10:00 it
    /// had only just left, the other boat lying at the same berth.
    case tamsuiFerryCrossing

    /// Decision 555: where ``taipeiMain`` and ``taipei101`` are, in degrees
    /// (the station's, as `Map3DFrameCostReportTests`; 101's, as
    /// ``Map3DTaipeiLandmark/taipei101``).
    public var place: (latitude: Double, longitude: Double)? {
        switch self {
        case .taipeiMain, .followBusCity: (25.0478, 121.5170)
        case .taipei101: (25.033946307135494, 121.56455513294843)
        case .taichungViaduct: (24.1369, 120.6850)
        case .interchange: (24.1489, 120.6233)
        case .streetStop, .streetStopNight: (25.048099, 121.520745)
        case .wenhu: (25.0600, 121.5600)
        // Between Qizhang and Xiaobitan stations.
        case .xiaobitan: (24.9734, 121.5368)
        // Its far station, 400 m east and 300 m north of Taipei Main
        // Station (a metre at the anchor's latitude, as RealWorldFrame).
        case .platformStop: (25.0478 + 0.0026949, 121.5170 + 0.0039662)
        // Between Taipei Zoo South and Zhinan Temple stations.
        case .maokong: (24.9825, 121.584)
        // Between the Tamsui and Bali piers.
        case .tamsuiFerry, .tamsuiFerryCrossing: (25.1640, 121.4376)
        // Between the Gushan and Cijin piers.
        case .gushanFerry, .gushanFerryEvening: (22.6165, 120.26775)
        // Decision 578: its first station, 7 km west and 300 m north of it.
        case .farStops: (25.0478 + 0.0026949, 121.5170 - 7_000 * 0.00000991)
        default: nil
        }
    }

    /// The real lines ``acquired`` records its first two lines as, in order.
    public static let acquiredLines = ["tra:NEIWAN", "ntdlrt:V"]

    /// The scene's world, its clock paused at the moment to show. `water`
    /// is the app's map of Taiwan's water, for a scene by the water
    /// (``tamsuiFerry``); the others do without it.
    public func make(in language: DisplayLanguage, water: WaterGrid? = nil) -> GameWorld {
        switch self {
        case .freight: Self.freightWorld(in: language)
        case .depots: Self.depotsWorld(in: language)
        case .zoning: Self.zoningWorld(in: language)
        case .punctuality: Self.punctualityWorld(in: language)
        case .commute: Self.commuteWorld(in: language)
        case .expansion: Self.expansionWorld(in: language)
        case .acquired: Self.acquiredWorld(in: language)
        case .taipeiMain, .taipei101, .taichungViaduct, .interchange: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), in: language)
        case .streetStop: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), resume: .x10, in: language)
        case .streetStopNight: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), until: 120, resume: .x10, in: language)
        case .wenhu, .xiaobitan: Self.realLineWorld(at: self, in: language)
        case .platformStop: Self.platformStopWorld(in: language)
        case .farStops: Self.farStopsWorld(in: language)

        case .depotOffer: Self.pausedDemo(in: language)
        case .maokong: Self.maokongWorld(in: language)
        case .followBus: Self.followBusWorld(in: language)
        case .followBusCity: Self.followBusCityWorld(in: language)
        case .tamsuiFerry: Self.ferryWorld(.tamsuiBali, at: self, every: 15, until: 34 * 60, in: language, water: water)
        case .tamsuiFerryCrossing:
            Self.ferryWorld(.tamsuiBali, at: self, every: 15, until: 34 * 60, then: 3, in: language, water: water)
        case .gushanFerry: Self.ferryWorld(.gushanCijin, at: self, every: 10, until: 34 * 60, in: language, water: water)
        case .gushanFerryEvening: Self.ferryWorld(.gushanCijin, at: self, every: 10, until: 42 * 60 + 30, in: language, water: water)
        }
    }

    /// What the scene does once its game is open, with the player's own
    /// tools: ``depotOffer`` lays its depot. Nothing for the others.
    @MainActor public func prepare(_ session: GameSession) {
        guard self == .depotOffer, let north = Self.depotOfferEnd(in: session.world) else { return }
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        session.tapNetwork(at: north.plan, reach: 64)
        session.addDepotYard()
    }

    /// Line 2's north end: the demo's highest track end furthest north.
    static func depotOfferEnd(in world: GameWorld) -> WorldCoordinate? {
        world.network.nodes.filter { $0.ends.count == 1 && $0.position.z > 0 }.min { $0.position.y < $1.position.y }?.position
    }

    private static func pausedDemo(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Follow a bus

    /// Half past nine on the first morning.
    public static let followBusRunSeconds: Int64 = 9 * 3_600 + 1_800

    private static func followBusWorld(in language: DisplayLanguage) -> GameWorld {
        followBus(on: DemoWorld.make(in: language))
    }

    private static func followBusCityWorld(in language: DisplayLanguage) -> GameWorld {
        var world = taipeiWorld(at: ScreenshotScene.followBusCity.place ?? (25.0478, 121.5170), in: language)
        // A new game has no roads until they are turned on.
        if world.roads == nil { world.enableRoads() }
        return followBus(on: world)
    }

    /// `start`'s first station with a road along its row and the feeder
    /// bus route on it, run on to ``followBusRunSeconds``.
    private static func followBus(on start: GameWorld) -> GameWorld {
        var world = start
        do throws(GameError) {
            guard let station = world.stations.first else { throw .unknownStation(StationID(rawValue: 1)) }
            let home = CellPosition(containing: station.location)
            let cells = (0...24).map { CellPosition(row: home.row, column: home.column + $0) }
            try world.borrow(CompanyAccounts.maximumLoan)
            try world.setRoads(cells, in: Array(Set(cells.map { LandBlock(cellRow: $0.row, column: $0.column) })))
            _ = try world.createBusRoute(to: station.id, stops: [cells[24], cells[14]], service: .every(minutes: 10), buses: 3)
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            // The city's world is on to ten already: no further.
            try world.advance(ticks: max(0, Int((followBusRunSeconds - world.clock.now.seconds) / 600)))
        } catch {
            preconditionFailure("The follow-a-bus screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Wenhu and Xiaobitan

    /// Decision 564: a new game's map round `scene`'s place (decision 603:
    /// the Xiaobitan Branch Line's too), twice the usual a side as the
    /// tests buy the line on (`RealLineAcquisitionTests.game(round:)`),
    /// with money enough for it; bought once the app's real data is read.
    private static func realLineWorld(at scene: ScreenshotScene, in language: DisplayLanguage) -> GameWorld {
        guard let place = scene.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude),
              let bounds = try? WorldBounds(width: 1 << 21, height: 1 << 21) else { return DemoWorld.make(in: language) }
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: Money(100_000_000_000))
        try? world.mapGround()
        // On to 05:30 while the map is empty, ten minutes a tick: the Debug
        // app then runs only the morning itself after it buys the line.
        world.setSpeed(.fast)
        try? world.advance(ticks: 33)
        world.setSpeed(.paused)
        return world
    }

    /// Decision 574: the Maokong Gondola on a new game of Muzha, at 10:00
    /// of the second day.
    private static func maokongWorld(in language: DisplayLanguage) -> GameWorld {
        guard let place = Self.maokong.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude)
        else { return DemoWorld.make(in: language) }
        var world = GameWorld.newGame(anchor: anchor)
        if let stops = RealCableway.maokong.stops(in: world) {
            _ = try? world.createCableway(stops: stops, legMetres: RealCableway.maokong.legMetres, meetsNear: RealCableway.maokong.meetsNear(in: world))
        }
        // On to 10:00 of day 1 (.fast is ten minutes a tick).
        world.setSpeed(.fast)
        try? world.advance(ticks: 34 * 6)
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    /// Whether the scene is by the water and waits for the app's map of
    /// Taiwan's water (decision 585).
    public var needsWater: Bool {
        self == .tamsuiFerry || self == .gushanFerry || self == .gushanFerryEvening || self == .tamsuiFerryCrossing
    }

    /// Decision 585: a real ferry, two boats every `every` minutes, on a
    /// new game round `scene`'s place, run on to `until` minutes from the
    /// start (in whole ten minutes): Tamsui–Bali at 10:00 of the second
    /// day; Gushan–Cijin then and at 18:30 (decision 585 PR-3).
    private static func ferryWorld(_ ferry: RealFerry, at scene: ScreenshotScene, every minutes: Int64, until: Int, then: Int = 0,
                                   in language: DisplayLanguage, water grid: WaterGrid?) -> GameWorld {
        guard let place = scene.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude)
        else { return DemoWorld.make(in: language) }
        let frame = RealWorldFrame(anchor: anchor, bounds: GameWorld.newGameBounds)
        let water = grid?.cells(frame: frame, bounds: GameWorld.newGameBounds) ?? []
        let steep = grid?.steepCells(frame: frame, bounds: GameWorld.newGameBounds) ?? []
        var world = GameWorld.newGame(anchor: anchor, water: water, steep: steep)
        if let piers = ferry.piers(in: world) {
            _ = try? world.createFerryRoute(piers: piers, legMetres: ferry.legMetres, service: .every(minutes: minutes), boats: 2)
        }
        // .fast is ten minutes a tick.
        world.setSpeed(.fast)
        try? world.advance(ticks: until / 10)
        world.setSpeed(.normal)
        // A minute a tick.
        try? world.advance(ticks: then)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Expansion

    /// Eight in the morning of the fourth day (day 3): West and East have
    /// been full on four days, Central on three.
    public static let expansionRunSeconds: Int64 = 3 * 86_400 + 8 * 3_600

    private static func expansionWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            let ids = world.stations.map(\.id)
            guard ids.count >= 3 else { throw .unknownStation(StationID(rawValue: 3)) }
            world.setLandDemand(false)
            // The stations' own counts of the people through them, not the
            // lines' (which count those the trains carried).
            world.setLineAccounts(false)
            func crowd(_ id: StationID, trips: Int64) throws(GameError) {
                let demand = world.stationDemand(of: id)
                try world.setStationDemand(id, to: StationDemand(kind: demand?.kind ?? .residential, dailyTrips: trips,
                                                                hinterland: demand?.hinterland ?? 0))
            }
            try crowd(ids[0], trips: 300_000)
            try crowd(ids[2], trips: 300_000)
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            try world.advance(ticks: 86_400 / 600)
            try crowd(ids[1], trips: 200_000)
            try world.advance(ticks: Int((expansionRunSeconds - 86_400) / 600))
            // The concourse costs more than the demo holds.
            if world.accounts.loan < CompanyAccounts.maximumLoan {
                try world.borrow(CompanyAccounts.maximumLoan - world.accounts.loan)
            }
            try world.expandStation(at: ids[0])
        } catch {
            preconditionFailure("The expansion screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Acquired

    /// Seven in the morning of the second day: the trains out.
    static let acquiredRunSeconds: Int64 = 31 * 3_600

    /// Decision 555: a new real-world game at `place`, a line 1.6 km long
    /// laid west to east through it, at 10:00 of the first day.
    private static func taipeiWorld(at place: (latitude: Double, longitude: Double), until ticks: Int = 60,
                                    resume: GameSpeed = .normal, in language: DisplayLanguage) -> GameWorld {
        guard let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude) else { return DemoWorld.make(in: language) }
        let world = GameWorld.newGame(anchor: anchor)
        guard let frame = RealWorldFrame(world: world) else { return world }
        let middle = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 800 * metre
        // Decision 555 續 (LANDMARK101): 300 m north of the place, clear of
        // its landmark (101's ground is 82 m from its middle), which gives
        // way to track on the ground through it (decision 370); y is south.
        let y = Int64(middle.y - 300 * metre)
        let line = try? LineBuilder.line(through: [PlanPoint(x: Int64(middle.x - half), y: y),
                                                   PlanPoint(x: Int64(middle.x + half), y: y)], in: world)
        var opened = line ?? world
        // On to 10:00, the sun high in the south-east (.fast is ten minutes
        // a tick), or as many ticks on as asked (120: 20:00).
        opened.setSpeed(.fast)
        try? opened.advance(ticks: ticks)
        // To go on at `resume` (decision 596's junction: 10×, where the
        // signals change and the traffic waits at them).
        opened.setSpeed(resume)
        opened.setSpeed(.paused)
        return opened
    }

    private static func acquiredWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            for (line, real) in zip(world.lines.prefix(acquiredLines.count), acquiredLines) {
                // A run down the line every twenty minutes from 05:00,
                // three minutes a stop, as a real line bought has its
                // timetable's (decision 315).
                let stops = line.stops.count
                let runs = stride(from: Int64(5 * 3_600), through: 23 * 3_600, by: 20 * 60).map { start in
                    LineRun(from: 0, to: stops - 1, times: (0..<stops).map { stop in
                        let at = start + Int64(stop) * 180
                        return LineRunTime(arrival: at, departure: stop == 0 || stop == stops - 1 ? at : at + 30)
                    })
                }
                try world.setLineRuns(line.id, to: runs)
                let tier: LineAcquisition.Tier = real.hasPrefix("tra:") ? .branch : .lightRail
                try world.recordLineAcquisition(line: line.id, realLine: real, dailyRiders: 0, tier: tier)
            }
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(acquiredRunSeconds / 600))
        } catch {
            preconditionFailure("The acquired screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Far stops

    /// Decision 578: ``farStops``'s world, paused with its train running,
    /// well short of the far station.
    private static func farStopsWorld(in language: DisplayLanguage) -> GameWorld {
        guard let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170) else { return DemoWorld.make(in: language) }
        let world = GameWorld.newGame(anchor: anchor)
        guard let frame = RealWorldFrame(world: world) else { return world }
        let middle = frame.worldPosition(latitude: 25.0478, longitude: 121.5170)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 7_000 * metre
        let y = Int64(middle.y - 300 * metre)
        guard var opened = try? LineBuilder.line(through: [PlanPoint(x: Int64(middle.x - half), y: y),
                                                           PlanPoint(x: Int64(middle.x + half), y: y)], in: world) else { return world }
        for _ in 0..<7_200 {
            if opened.trains.first(where: { $0.position != nil }) != nil, case .travellingToStop? = opened.trains.first?.execution { break }
            try? opened.advance(ticks: 1)
        }
        opened.setSpeed(.paused)
        return opened
    }

    // MARK: - Platform stop

    /// Decision 565: ``platformStop``'s world, paused while its train stands
    /// at the far platform (its head at the platform's end), at most two
    /// game hours on.
    private static func platformStopWorld(in language: DisplayLanguage) -> GameWorld {
        guard let anchor = GeoAnchor(latitudeDegrees: 25.0478, longitudeDegrees: 121.5170) else { return DemoWorld.make(in: language) }
        let world = GameWorld.newGame(anchor: anchor)
        guard let frame = RealWorldFrame(world: world) else { return world }
        let middle = frame.worldPosition(latitude: 25.0478, longitude: 121.5170)
        let metre = Double(WorldCoordinate.unitsPerMetre), half = 400 * metre
        let y = Int64(middle.y - 300 * metre)
        guard var opened = try? LineBuilder.line(through: [PlanPoint(x: Int64(middle.x - half), y: y),
                                                           PlanPoint(x: Int64(middle.x + half), y: y)],
                                                 in: world, carLength: world.platformCarLength),
              let edge = opened.network.edges.first else { return world }
        let berth = edge.length - 2 * opened.platformCarLength
        for _ in 0..<7_200 {
            if let train = opened.trains.first, case .onEdge(let traversal, let offset)? = train.position,
               traversal.direction == .forward, offset == berth { break }
            try? opened.advance(ticks: 1)
        }
        opened.setSpeed(.paused)
        return opened
    }

    // MARK: - Commute

    /// Half past seven on the second morning, a Tuesday: the first is the
    /// New Year holiday, with no school.
    static let commuteRunSeconds: Int64 = 31 * 3_600 + 30 * 60

    private static func commuteWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            guard let station = world.stations.first else { throw .unknownStation(StationID(rawValue: 1)) }
            // A school and a hospital cost more than the demo holds.
            try world.borrow(CompanyAccounts.maximumLoan)
            // The first sites round the station a building can stand on,
            // nearest first, within its 800 m.
            let directions: [(Int64, Int64)] = [(0, -1), (0, 1), (-1, 0), (1, 0), (-1, -1), (1, -1), (-1, 1), (1, 1)]
            var offsets: [(Int64, Int64)] = []
            for distance in stride(from: Int64(6_000), through: 42_000, by: 4_000) {
                for (dx, dy) in directions {
                    offsets.append((dx * distance, dy * distance))
                }
            }
            for kind in [PlacedBuildingKind.school, .hospital] {
                var refused: GameError?
                for (dx, dy) in offsets {
                    do throws(GameError) {
                        try world.placeBuilding(kind, at: PlanPoint(x: station.point.x + dx, y: station.point.y + dy))
                        refused = nil
                        break
                    } catch {
                        refused = error
                    }
                }
                if let refused { throw refused }
            }
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(commuteRunSeconds / 600))
        } catch {
            preconditionFailure("The commute screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Punctuality

    /// A day and nine hours: the first day settled, trains running.
    static let punctualityRunSeconds: Int64 = 33 * 3_600

    private static func punctualityWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        world.setRealisticOperation(true)
        do throws(GameError) {
            // .fast is ten minutes a tick.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(punctualityRunSeconds / 600))
        } catch {
            preconditionFailure("The punctuality screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Depots

    /// How far beyond West and East, and to the south, each depot stands.
    private static let depotOffset: Int64 = 4 * 1_024

    private static func depotsWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            guard let line1 = world.lines.first, let westID = line1.stops.first, let eastID = line1.stops.last,
                  let west = world.station(id: westID)?.point, let east = world.station(id: eastID)?.point
            else { throw .unknownLine(LineID(rawValue: 1)) }
            let westDepot = try world.buildStation(
                named: language.text("West Depot", "西機廠"), at: PlanPoint(x: west.x - depotOffset, y: west.y + depotOffset)
            ).id
            let eastDepot = try world.buildStation(
                named: language.text("East Depot", "東機廠"), at: PlanPoint(x: east.x + depotOffset, y: east.y + depotOffset)
            ).id
            try world.setStationDepot(westDepot, to: true)
            try world.setStationDepot(eastDepot, to: true)
            try world.setLineDepots(line1.id, to: [westDepot])
        } catch {
            preconditionFailure("The depots screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Zoning

    private static func zoningWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            // Past the first midnight, when the served stations grew.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(freightRunSeconds / 600))
            let row = Int((world.bounds.height / 2) / Land.cellLength)
            let column = Int((world.bounds.width / 2) / Land.cellLength)
            // The use the city wants least, if it has more than it wants.
            let levels = world.cityDemandLevels
            let unwanted = [(Zone.residential, levels.homes), (.commercial, levels.shops), (.office, levels.work)]
                .min { $0.1 < $1.1 }.map(\.0) ?? .residential
            // The town fills the demo's stations' 800 m (some 13 cells), so
            // only its edge is in reach: north of it, out past the reach,
            // the unwanted use; west, schools.
            try world.setZone(unwanted, rows: (row - 20)...(row - 10), columns: (column - 6)...(column + 6))
            try world.setZone(.civic, rows: (row - 6)...(row + 6), columns: (column - 20)...(column - 10))
            // A station 1.5 km east, no train serves yet, zoned round.
            let east = Int64(column + 24) * Land.cellLength + Land.cellLength / 2
            _ = try world.buildStation(
                named: language.text("New Town", "新市鎮"), at: PlanPoint(x: east, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
            )
            try world.setZone(.residential, rows: (row - 4)...(row + 4), columns: (column + 20)...(column + 28))
        } catch {
            preconditionFailure("The zoning screenshot scene no longer builds: \(error)")
        }
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    /// Decision 522: the zoning drag the zoning scene's screenshot holds
    /// down: a box some 2 km a side round the new station 1.5 km east,
    /// reaching back to the town's edge, so the drag shows cells in reach
    /// and the grey ones past it.
    public static func zoningDrag(in world: GameWorld) -> (from: PlanPoint, to: PlanPoint) {
        let row = Int((world.bounds.height / 2) / Land.cellLength)
        let column = Int((world.bounds.width / 2) / Land.cellLength)
        func middle(_ row: Int, _ column: Int) -> PlanPoint {
            PlanPoint(x: Int64(column) * Land.cellLength + Land.cellLength / 2, y: Int64(row) * Land.cellLength + Land.cellLength / 2)
        }
        return (middle(row - 15, column + 9), middle(row + 15, column + 39))
    }

    // MARK: - Freight

    /// How long the freight scene runs before it is shown: to 08:00:30 on
    /// the second day, past the first midnight's growth and half a minute
    /// after the hour's goods came in. The train clears a yard in minutes
    /// on this short track, so only just after the hour do both yards hold
    /// goods while it carries a load.
    static let freightRunSeconds: Int64 = 32 * 3_600 + 30
    /// The freight track's distance south of Line 1: inside the demo's
    /// inner ring (192 m), under Line 2's viaduct (8 m up), 40 m from Line 1.
    private static let freightOffset: Int64 = 2_560
    /// The industry beyond each yard: a block of cells this many cells
    /// from the middle of the map (1 km), each with ``industryJobs`` jobs,
    /// so each yard takes in some 240 tons at each hour, more than the
    /// train's 160.
    private static let industryDistance = 16
    private static let industryJobs: Int64 = 750

    private static func freightWorld(in language: DisplayLanguage) -> GameWorld {
        var world = DemoWorld.make(in: language)
        do throws(GameError) {
            try addFreight(to: &world, language: language)
            // .fast is ten minutes a tick, .x10 one second.
            world.setSpeed(.fast)
            try world.advance(ticks: Int(freightRunSeconds / 600))
            world.setSpeed(.x10)
            try world.advance(ticks: Int(freightRunSeconds % 600))
        } catch {
            preconditionFailure("The freight screenshot scene no longer builds: \(error)")
        }
        // Paused, to go on at the usual speed (the HUD shows the speed a
        // paused game resumes at).
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    private static func addFreight(to world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
        let middleRow = Int((world.bounds.height / 2) / Land.cellLength)
        let middleColumn = Int((world.bounds.width / 2) / Land.cellLength)
        // Industry west of West and east of East, on cells the city has not
        // taken, so each yard is the nearest to its own.
        var cells = world.land.cells
        var taken = Set(cells.map { [$0.row, $0.column] })
        for side in [-1, 1] {
            for dr in -2...2 {
                for step in 0..<3 {
                    let row = middleRow + dr, column = middleColumn + side * (industryDistance + step)
                    guard taken.insert([row, column]).inserted else { continue }
                    cells.append(LandCell(row: row, column: column, use: .industrial, residents: 0, jobs: industryJobs))
                }
            }
        }
        try world.setLand(cells)

        // West and East are the demo's first and last stations on Line 1.
        guard let line1 = world.lines.first, let west = line1.stops.first, let east = line1.stops.last else {
            throw .unknownLine(LineID(rawValue: 1))
        }
        let cx = world.bounds.width / 2, cy = world.bounds.height / 2
        let reach: Int64 = 9 * 1_024
        let platform = 4 * Train.carLength
        let from = try world.buildTrackNode(at: WorldCoordinate(x: cx - reach, y: cy + freightOffset))
        let to = try world.buildTrackNode(at: WorldCoordinate(x: cx + reach, y: cy + freightOffset))
        let track = try world.buildTrackEdge(from: from, to: to)
        try world.addTrackPlatform(west, on: track, from: 1_024, to: 1_024 + platform)
        try world.addTrackPlatform(east, on: track, from: 2 * reach - 1_024 - platform, to: 2 * reach - 1_024)
        try world.buildFreightFacility(at: west)
        try world.buildFreightFacility(at: east)

        let line = try world.createLine(named: language.text("Freight Line", "貨運線"), stops: [west, east]).id
        try world.setLineFreight(line, to: true)
        try world.setLineServiceWindow(line, to: .allDay)
        try world.setLineTrainsInService(line, to: TrainsInService(peak: 1, offPeak: 1, low: 1))
        let train = try world.purchaseTrain(named: language.text("Freight Train 1", "貨運列車 1")).id
        try world.setTrainCars(train, to: 4)
        let berth = 1_024 + platform
        try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: track, direction: .forward), offset: berth))
        try world.setTrainContinuation(train, along: [], stoppingAt: berth)
        try world.setTrainMovementRate(train, to: 512)
        try world.assignTrain(train, to: line)
    }
}

extension GameSession {
    /// Decision 564: real line `id` bought (``ScreenshotScene/wenhu``),
    /// the game paused; `false` when it is not on sale (the real data not
    /// read yet) or not bought.
    public func buyForScreenshot(_ id: String) -> Bool {
        guard let line = buyableRealLines.first(where: { $0.id == id }), acquireRealLine(realLineOffer(for: line)) else { return false }
        return perform { (world: inout GameWorld) throws(GameError) in
            world.setSpeed(.paused)
            return ""
        }
    }

    /// Decision 564: the game run on to `seconds` into the day, then
    /// paused, on a copy of the world off the main thread, put back as
    /// one edit: the app's main thread stays free (the 06:00 passenger
    /// plan of a city map takes minutes in a Debug build, and a UI test's
    /// queries time out).
    public func runForScreenshot(until seconds: Int64) async {
        let start = world
        let ran = await Task.detached(priority: .userInitiated) { () -> GameWorld in
            var world = start
            world.setSpeed(.normal)
            while world.clock.now.seconds % GameTime.secondsPerDay < seconds {
                do throws(GameError) { try world.advance(ticks: 1) } catch { break }
            }
            world.setSpeed(.paused)
            return world
        }.value
        _ = perform { (world: inout GameWorld) throws(GameError) in
            world = ran
            return ""
        }
    }

    /// Decision 564: the train of real line `id` bought nearest its middle
    /// station, for the screenshot to follow along its double track.
    public func screenshotTrainMidway(on id: String) -> TrainID? {
        guard let line = world.acquisition(of: id)?.line.flatMap({ world.line(id: $0) }), !line.stops.isEmpty,
              let middle = world.station(id: line.stops[line.stops.count / 2])?.location else { return nil }
        let placed = line.assignedTrains.compactMap { id in
            world.train(id: id).flatMap(\.position).flatMap { world.location(of: $0) }.map { (id, $0.position.plan) }
        }
        return placed.min { a, b in
            (WorldVector(a.1) - WorldVector(middle)).length < (WorldVector(b.1) - WorldVector(middle)).length
        }?.0
    }
}
