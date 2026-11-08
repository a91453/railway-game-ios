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
    /// Decision 581, later: the same map at the Changhua Roundhouse, for
    /// the screenshots of the locomotives standing in its doorways.
    case changhuaRoundhouse

    /// Decision 596: the same map round the big junction 380 m east of
    /// Taipei Main Station (23 stop lines) at 10:00 and at 20:00, for the
    /// screenshots of the traffic waiting at its stop lines and the people
    /// at its crossings (`-screenshot-3d-view`), paused to go on at 10×.
    case streetStop
    case streetStopNight

    /// Decision 610: the same map round Banqiao's low-rise blocks north
    /// of Fuzhong (decision 610 續: no towers within 80 m), for the close-up screenshots of the real buildings' street
    /// fronts (arcade pillars, grilles, blade signs, rooftop rooms).
    case streetFronts

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

    /// Decision 535 (continued, KLRT): the same empty map round the
    /// Kaohsiung Circular Light Rail, for `-screenshot-offer-real krtc:C`
    /// (its purchase card) and `-screenshot-buy-real krtc:C` (its trains
    /// going round each way). For the screenshot review of the pull
    /// request that put it on sale.
    case klrt

    /// Decision 605 (continued): the same empty map, four times as wide,
    /// round Chang Gung Memorial Hospital station at 02:00, for
    /// `-screenshot-buy-real-before tymc:A` to buy the Taoyuan Airport MRT
    /// as it was before its expresses came
    /// (``GameSession/buyAsBeforeForScreenshot(_:)``): its panel's
    /// rebuild, the card, and the station's four tracks after it. For
    /// the screenshot review of the pull request that made it work.
    case tymcRebuild

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
    /// of the pull request that added the offer. Decision 619: the camera
    /// is turned to the yard, which the demo opens at the top edge.
    case depotOffer

    /// Decision 574: a new real-world game round Muzha with the Maokong
    /// Gondola built as the cable car mode lays it
    /// (``RealCableway/maokong``), run on to 10:00 of the second day, so
    /// its card has a day's account: the rope and its stations on the 2D
    /// map, and the mode's card.
    case maokong

    /// Decision 615: the same on a new game round Sun Moon Lake with the
    /// Sun Moon Lake Ropeway (``RealCableway/sunMoonLake``) laid, whose
    /// cabins are Sun Moon Lake's.
    case sunMoonLake

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

    /// Decision 585 續 (FERRY-QIJIN): the whole of Taiwan with the land
    /// (no people, its water) read in round a point on Kaohsiung
    /// harbour's north side and not round Cijin, as on the author's map,
    /// looking over the harbour mouth: the ferry mode's pale blue shore.
    case cijinShore

    /// Decision 611 (ROADTUNNEL): a new game round the road tunnels'
    /// portals, its ground read, at 10:00: the Hsuehshan Tunnel's two
    /// bores at Toucheng, Provincial Highway 9's (蘇花改) tunnels north of
    /// Nanao, and its gallery south of Su'ao.
    case hsuehshanTunnel
    case suhuaTunnel
    case suhuaGallery

    /// Decision 625 (STATION-EXT-1): an empty real-world map round TRA
    /// Taichung (the old station beside the new), TRA Hsinchu, TRA Banqiao, HSR Taoyuan (with the Airport MRT's A18), HSR Taichung (with Xinwuri) and HSR Zuoying
    /// (with Xinzuoying), run on empty to 09:30 or, `…Night`, 19:30: for
    /// the Debug app's `-screenshot-lay-demo` to lay the demo's real lines
    /// round it (``GameSession/layDemoForScreenshot(_:)``) and run on half
    /// an hour, for the screenshots of the real stations' exterior studies
    /// over the platforms and trains, by day and by night. For the
    /// screenshot review of the pull request that stood them there.
    case exteriorTaichung, exteriorTaichungNight
    case exteriorHsinchu, exteriorHsinchuNight
    case exteriorBanqiao, exteriorBanqiaoNight
    case exteriorTaoyuanHSR, exteriorTaoyuanHSRNight
    case exteriorTaichungHSR, exteriorTaichungHSRNight
    case exteriorZuoying, exteriorZuoyingNight

    /// Decision 629 (TRACKHEIGHT): flat ground 4 km a side, 5 m up, with
    /// a river 192 m wide across it, and a stretch of track drawn across
    /// the river on the ground: the build card refusing it and offering
    /// the heights that get it over or under. For the screenshot review of
    /// the pull request that added them.
    case trackHeight

    /// Decision 555: where ``taipeiMain`` and ``taipei101`` are, in degrees
    /// (the station's, as `Map3DFrameCostReportTests`; 101's, as
    /// ``Map3DTaipeiLandmark/taipei101``).
    public var place: (latitude: Double, longitude: Double)? {
        switch self {
        case .taipeiMain, .followBusCity: (25.0478, 121.5170)
        case .taipei101: (25.033946307135494, 121.56455513294843)
        case .taichungViaduct: (24.1369, 120.6850)
        case .interchange: (24.1489, 120.6233)
        // In front of the roundhouse's doorways, 12 m south and 5 m east of
        // its middle (``Map3DTaipeiLandmark/changhuaRoundhouse``).
        case .changhuaRoundhouse: (24.0858608 - 12 / 110_759, 120.5401168 + 5 / 101_684)
        case .streetStop, .streetStopNight: (25.048099, 121.520745)
        case .streetFronts: (25.0185, 121.4536)
        case .wenhu: (25.0600, 121.5600)
        // Between Qizhang and Xiaobitan stations.
        case .xiaobitan: (24.9734, 121.5368)
        // The middle of the ring's 38 stations.
        case .klrt: (22.6281, 120.3036)
        // Chang Gung Memorial Hospital station, as the bundled tymc.json.
        case .tymcRebuild: (25.06053, 121.37073)
        // Its far station, 400 m east and 300 m north of Taipei Main
        // Station (a metre at the anchor's latitude, as RealWorldFrame).
        case .platformStop: (25.0478 + 0.0026949, 121.5170 + 0.0039662)
        // Between Taipei Zoo South and Zhinan Temple stations.
        case .maokong: (24.9825, 121.584)
        // Between the ropeway's two stations.
        case .sunMoonLake: (23.8562, 120.9429)
        // Between the Tamsui and Bali piers.
        case .tamsuiFerry, .tamsuiFerryCrossing: (25.1640, 121.4376)
        // Between the Gushan and Cijin piers.
        case .gushanFerry, .gushanFerryEvening, .cijinShore: (22.6165, 120.26775)
        // Decision 578: its first station, 7 km west and 300 m north of it.
        case .farStops: (25.0478 + 0.0026949, 121.5170 - 7_000 * 0.00000991)
        // Decision 611: between each pair of portals (the base map's ends).
        case .hsuehshanTunnel: (24.84776, 121.79127)
        case .suhuaTunnel: (24.52307, 121.82816)
        case .suhuaGallery: (24.60857, 121.85564)
        // Decision 625: each study's origin (``Map3DStationExteriorBatch1/origin(of:)``).
        case .exteriorTaichung, .exteriorTaichungNight: (24.13732601, 120.68671829)
        case .exteriorHsinchu, .exteriorHsinchuNight: (24.80160443, 120.97165154)
        case .exteriorBanqiao, .exteriorBanqiaoNight: (25.0144511, 121.4640451)
        case .exteriorTaoyuanHSR, .exteriorTaoyuanHSRNight: (25.01347985, 121.214539)
        case .exteriorTaichungHSR, .exteriorTaichungHSRNight: (24.1112536, 120.61474665)
        case .exteriorZuoying, .exteriorZuoyingNight: (22.68726485, 120.3074864)
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
        case .taipeiMain, .taipei101, .taichungViaduct, .interchange, .changhuaRoundhouse: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), in: language)
        case .hsuehshanTunnel, .suhuaTunnel, .suhuaGallery: Self.groundWorld(at: self, in: language)
        case .streetStop: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), resume: .x10, in: language)
        case .streetStopNight: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), until: 120, resume: .x10, in: language)
        case .streetFronts: Self.taipeiWorld(at: place ?? (25.0478, 121.5170), in: language)
        case .wenhu, .xiaobitan, .klrt: Self.realLineWorld(at: self, in: language)
        // The line runs 50 km; the map opens at 02:00, its last trains in.
        case .tymcRebuild: Self.realLineWorld(at: self, side: 1 << 22, ticks: 12, in: language)
        case .exteriorTaichung, .exteriorHsinchu, .exteriorBanqiao, .exteriorTaoyuanHSR, .exteriorTaichungHSR, .exteriorZuoying:
            Self.realLineWorld(at: self, ticks: 57, in: language)
        case .exteriorTaichungNight, .exteriorHsinchuNight, .exteriorBanqiaoNight, .exteriorTaoyuanHSRNight, .exteriorTaichungHSRNight, .exteriorZuoyingNight:
            Self.realLineWorld(at: self, ticks: 117, in: language)
        case .platformStop: Self.platformStopWorld(in: language)
        case .farStops: Self.farStopsWorld(in: language)

        case .depotOffer: Self.pausedDemo(in: language)
        case .maokong: Self.maokongWorld(in: language)
        case .sunMoonLake: Self.cablewayWorld(.sunMoonLake, at: self, in: language)
        case .followBus: Self.followBusWorld(in: language)
        case .followBusCity: Self.followBusCityWorld(in: language)
        case .tamsuiFerry: Self.ferryWorld(.tamsuiBali, at: self, every: 15, until: 34 * 60, in: language, water: water)
        case .tamsuiFerryCrossing:
            Self.ferryWorld(.tamsuiBali, at: self, every: 15, until: 34 * 60, then: 3, in: language, water: water)
        case .gushanFerry: Self.ferryWorld(.gushanCijin, at: self, every: 10, until: 34 * 60, in: language, water: water)
        case .gushanFerryEvening: Self.ferryWorld(.gushanCijin, at: self, every: 10, until: 42 * 60 + 30, in: language, water: water)
        case .cijinShore: Self.cijinShoreWorld(water: water)
        case .trackHeight: Self.trackHeightWorld()
        }
    }

    /// What the scene does once its game is open, with the player's own
    /// tools: ``depotOffer`` lays its depot. Nothing for the others.
    @MainActor public func prepare(_ session: GameSession) {
        if self == .cijinShore, let frame = RealWorldFrame(world: session.world) {
            let (west, north) = frame.worldPosition(latitude: 22.632, longitude: 120.252)
            let (east, south) = frame.worldPosition(latitude: 22.598, longitude: 120.288)
            let region = WorldRegion(minX: west, minY: north, maxX: east, maxY: south)
            // The map follows a camera request made after it is up, and it
            // opens on the whole island (some seconds after the game, its
            // real-world data read), where a request only zooms out and
            // cannot move (the world is all in view): asked again each
            // second for 3 minutes, as the UI test pinches in.
            Task { @MainActor in
                for _ in 0..<180 {
                    try? await Task.sleep(for: .seconds(1))
                    session.lookOver(region)
                }
            }
            return
        }
        if self == .trackHeight {
            // Decision 629: the stretch drawn across the river, as two taps.
            let (from, to, middle) = Self.trackHeightStretch
            session.selectTool(.network)
            session.networkSnapsToTrack = false
            session.tapNetwork(at: from, reach: 16)
            session.tapNetwork(at: to, reach: 16)
            session.lookAt(middle)
            Task { @MainActor in
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(1))
                    session.lookAt(middle)
                }
            }
            return
        }
        guard self == .depotOffer, let north = Self.depotOfferEnd(in: session.world) else { return }
        session.selectTool(.network)
        session.setNetworkMode(.depot)
        // Decision 619: four sidings, which the throat splits two and two,
        // the sides mirroring each other (three, which two-way turnouts
        // cannot halve, is one turnout deeper on one side).
        session.networkDepotSidings = 4
        let before = Set(session.world.network.nodes.map(\.id))
        session.tapNetwork(at: north.plan, reach: 64)
        session.addDepotYard()
        // Decision 619: the yard is at the map's top edge, under the HUD
        // and the banner, as the demo opens; the camera is asked to put its
        // throat in the middle, at the zoom the map has (asked to show it
        // whole, the map fits it in what the banner and panels leave clear,
        // a sliver, and zooms out to the island), again each second for a
        // minute (the map follows a request made after it is up). The
        // throat: the track's end, the turnouts, and the bends 40 m past the
        // last of them.
        let middle = Self.depotOfferThroatMiddle(in: session.world, end: north, built: before)
        session.lookAt(middle)
        Task { @MainActor in
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                session.lookAt(middle)
            }
        }
    }

    /// The middle of the throat of the yard laid at `end` (the nodes not
    /// in `built`): see ``prepare(_:)``.
    static func depotOfferThroatMiddle(in world: GameWorld, end: WorldCoordinate, built: Set<TrackNodeID>) -> PlanPoint {
        let laid = world.network.nodes.filter { !built.contains($0.id) }
        func distance(_ point: WorldCoordinate) -> Int64 { abs(point.x - end.x) + abs(point.y - end.y) }
        let turnouts = laid.filter { $0.ends.count >= 3 }.map(\.position)
        let reach = (turnouts.map(distance).max() ?? 0) + 40 * WorldCoordinate.unitsPerMetre
        let throat = laid.filter { $0.ends.count >= 2 && distance($0.position) <= reach }.map(\.position) + [end]
        let xs = throat.map(\.x), ys = throat.map(\.y)
        return PlanPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
    }

    /// Line 2's north end: the demo's highest track end furthest north.
    static func depotOfferEnd(in world: GameWorld) -> WorldCoordinate? {
        world.network.nodes.filter { $0.ends.count == 1 && $0.position.z > 0 }.min { $0.position.y < $1.position.y }?.position
    }

    /// ``trackHeight``'s ends, 896 m apart either side of its river, and
    /// the river's middle.
    static let trackHeightStretch = (
        from: PlanPoint(x: 26 * 4_096, y: 32 * 4_096), to: PlanPoint(x: 40 * 4_096, y: 32 * 4_096),
        middle: PlanPoint(x: 33 * 4_096, y: 32 * 4_096)
    )

    /// ``trackHeight``'s world: 4 × 4 blocks of ground 5 m up, cell
    /// columns 31 to 33 water, paused at the start.
    static func trackHeightWorld() -> GameWorld {
        var world = GameWorld(
            bounds: try! WorldBounds(width: 262_144, height: 262_144),
            economy: GameEconomy(balance: Money(500_000_000), costs: .standard),
            clock: GameClock(speed: .paused)
        )
        let side = GroundBlock.side
        let blocks = (0..<4).flatMap { row in
            (0..<4).compactMap { column in
                GroundBlock(block: LandBlock(row: row, column: column), heights: Array(repeating: 5, count: side * side))
            }
        }
        do throws(GameError) {
            try world.setGround(blocks)
            try world.setWater((0..<64).flatMap { row in (31...33).map { CellPosition(row: row, column: $0) } })
        } catch {
            preconditionFailure("The track height screenshot scene no longer builds: \(error)")
        }
        return world
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

    /// Decision 611: a new game round `scene`'s place, its ground read (the
    /// hills the road tunnels go into), on to 10:00.
    private static func groundWorld(at scene: ScreenshotScene, in language: DisplayLanguage) -> GameWorld {
        guard let place = scene.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude)
        else { return DemoWorld.make(in: language) }
        var world = GameWorld.newGame(anchor: anchor)
        try? world.mapGround()
        // .fast is ten minutes a tick.
        world.setSpeed(.fast)
        try? world.advance(ticks: 60)
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    // MARK: - Wenhu and Xiaobitan

    /// Decision 564: a new game's map round `scene`'s place (decision 603:
    /// the Xiaobitan Branch Line's too), twice the usual a side as the
    /// tests buy the line on (`RealLineAcquisitionTests.game(round:)`),
    /// with money enough for it; bought once the app's real data is read.
    private static func realLineWorld(at scene: ScreenshotScene, side: Int64 = 1 << 21, ticks: Int = 33, in language: DisplayLanguage) -> GameWorld {
        guard let place = scene.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude),
              let bounds = try? WorldBounds(width: side, height: side) else { return DemoWorld.make(in: language) }
        var world = GameWorld.newGame(anchor: anchor, bounds: bounds, balance: Money(100_000_000_000))
        try? world.mapGround()
        // On to 05:30 while the map is empty, ten minutes a tick: the Debug
        // app then runs only the morning itself after it buys the line.
        // Decision 625: on to 09:30 (57) or 19:30 (117) for the exteriors.
        world.setSpeed(.fast)
        try? world.advance(ticks: ticks)
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

    /// Decision 615: `real` on a new game round `scene`'s place, at 10:00
    /// of the second day as ``maokongWorld(in:)``.
    private static func cablewayWorld(_ real: RealCableway, at scene: ScreenshotScene, in language: DisplayLanguage) -> GameWorld {
        guard let place = scene.place, let anchor = GeoAnchor(latitudeDegrees: place.latitude, longitudeDegrees: place.longitude)
        else { return DemoWorld.make(in: language) }
        var world = GameWorld.newGame(anchor: anchor)
        if let stops = real.stops(in: world) {
            _ = try? world.createCableway(stops: stops, legMetres: real.legMetres, meetsNear: real.meetsNear(in: world))
        }
        world.setSpeed(.fast)
        try? world.advance(ticks: 34 * 6)
        world.setSpeed(.normal)
        world.setSpeed(.paused)
        return world
    }

    /// Whether the scene is by the water and waits for the app's map of
    /// Taiwan's water (decision 585).
    public var needsWater: Bool {
        self == .tamsuiFerry || self == .gushanFerry || self == .gushanFerryEvening || self == .tamsuiFerryCrossing || self == .cijinShore
    }

    /// The point on Kaohsiung harbour's north side ``cijinShore`` reads
    /// the land round: 2.5 km north of Cijin's ferry station.
    static let cijinShoreRead = (latitude: 22.635, longitude: 120.280)

    /// ``cijinShore``'s world: the whole of Taiwan, the blocks within
    /// ``WholeTaiwan/landReach`` of ``cijinShoreRead`` read in with their
    /// water and no people.
    private static func cijinShoreWorld(water grid: WaterGrid?) -> GameWorld {
        var world = GameWorld.newWholeTaiwanGame()
        guard let grid, let frame = RealWorldFrame(world: world) else { return world }
        let (x, y) = frame.worldPosition(latitude: cijinShoreRead.latitude, longitude: cijinShoreRead.longitude)
        let blocks = Set(Land.blocks(within: WholeTaiwan.landReach, of: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded())), in: world.bounds))
        try? world.expandLand(blocks.sorted(), cells: [], water: grid.cells(frame: frame, bounds: world.bounds, in: blocks))
        world.setSpeed(.paused)
        return world
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

    /// Decision 605 (continued): real line `id` bought from its timetable
    /// as it was before decision 605, every train stopping everywhere
    /// (``ScreenshotScene/tymcRebuild``), the game paused and the line
    /// picked; `false` when it is not on sale or not bought.
    public func buyAsBeforeForScreenshot(_ id: String) -> Bool {
        guard let current = railways, let runs = current.metroRuns[id] else { return false }
        var before = current
        before.metroRuns[id] = runs.stoppingEverywhere()
        railways = before
        let bought = buyForScreenshot(id)
        railways = current
        if bought, let line = world.acquisition(of: id)?.line { selectLine(line) }
        return bought
    }

    /// Decision 605 (continued): the map looked over `metres` round the
    /// scene's place, for a screenshot of what stands there.
    public func lookOverForScreenshot(_ scene: ScreenshotScene, metres: Double) {
        guard let place = scene.place, let frame = RealWorldFrame(world: world) else { return }
        let (x, y) = frame.worldPosition(latitude: place.latitude, longitude: place.longitude)
        let reach = metres * Double(WorldCoordinate.unitsPerMetre)
        lookOver(WorldRegion(minX: x - reach, minY: y - reach, maxX: x + reach, maxY: y + reach))
    }

    /// Decision 625: the demo's real lines (decision 351) laid in the
    /// view `"south,west,north,east"` (degrees), on a map the scene opened
    /// as the demo's, then the game run on half an hour, so the trains are
    /// out. `false` when the real data is not read yet.
    public func layDemoForScreenshot(_ view: String) async -> Bool {
        let parts = view.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, railways != nil, let frame = RealWorldFrame(world: world) else { return false }
        let southWest = frame.worldPosition(latitude: parts[0], longitude: parts[1])
        let northEast = frame.worldPosition(latitude: parts[2], longitude: parts[3])
        news.isDemo = true
        _ = await layDemoRealLines(in: WorldRegion(minX: southWest.x, minY: northEast.y, maxX: northEast.x, maxY: southWest.y))
        let now = world.clock.now.seconds % GameTime.secondsPerDay
        await runForScreenshot(until: now + 30 * 60)
        return true
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
