import GameCore

// Decision 535 (continued, KLRT): buying a ring, the Kaohsiung Circular
// Light Rail. Its runs go round it both ways (decision 535's ring runs,
// ``LineRun/way``), so it is laid with no ends: a double track all the way
// round, each station with a platform each way and no loop, the track
// closing on itself where it began (the seam, as the reference's
// `close_metro_loops.mjs` closes a metro loop), and its depot beside the
// line, where every train stands overnight.
//
// The pieces: the first track round from the seam to just short of it
// (piece 0), the second beside it (piece 1, the side the depot's wye
// leaves, ``RealLineDepotLayout``), the two short stretches closing each
// track at the seam, the depot's crossovers and the depot.

extension RealLineLaying {
    /// How long the stretch is that closes each track at the seam.
    static let ringSeam = 80 * RealLineAcquisition.metre
    /// The depot's crossovers on a ring: a light rail's short turnouts,
    /// 40 m (the ring's stations lie 300 to 1,000 m apart, and the wye and
    /// its crossovers must fit between two of them).
    static let ringCrossover = 40 * RealLineAcquisition.metre
    /// Decision 612: how far the ring's first track lies off the real
    /// line's drawing, to its right going round: the drawing follows one
    /// of the light rail's two real tracks, the other some 4 m to its
    /// right (OSM, `rail_tracks.json`, the median 4.0 m), and the second
    /// track goes ``HighSpeedDemo/trackOffset`` (5 m) to the first's
    /// left. So each track lies about half a metre off a real one, not
    /// the second 5 m outside both.
    static let ringShift = 4.5 * RealLineAcquisition.metre
    /// Decision 612: how high a ring's station on a real bridge stands
    /// over the ground at least: one level, the least clearance over a
    /// crossing (8 m), where the real light rail's Love River bridge at
    /// Zhen'ai Pier is about 7 m (`rail_tracks.json`); not a metro
    /// viaduct's 16 m (``RealLineAcquisition/raisedStation``).
    static let ringRaisedStation = Double(TrackStructure.clearance)

    /// The main track's nodes of a ring's depot (as
    /// ``RealLineDepotLayout/marks(at:)``, with ``ringCrossover``).
    static func ringDepotMarks(at j: Double) -> [Double] {
        let gap = RealLineDepotLayout.gap, arms = 2 * RealLineDepotLayout.armReach
        return [j - gap - ringCrossover, j - gap, j, j + arms, j + arms + gap, j + arms + gap + ringCrossover]
    }

    /// `runs` with its stops the other way round the ring, from the same
    /// first stop: each run's way turned, its calls as they were.
    static func turned(_ runs: RealLineRuns) -> RealLineRuns {
        guard let first = runs.stops.first else { return runs }
        var turned = runs
        turned.stops = [first] + runs.stops.dropFirst().reversed()
        turned.runs = runs.runs.map { run in
            var run = run
            run.way = run.way.map { $0 == .inner ? .outer : .inner }
            return run
        }
        turned.ring = true
        return turned
    }

    /// The offer of the ring `line`, its stations at `points` (in the
    /// order of its stops): laid round with its depot, or why it cannot be.
    func ringOffer(
        for line: RealBranchLine, runs dataRuns: RealLineRuns, points dataPoints: [WorldVector], raising: StationRaising, depot: Bool,
        railways: RealRailways, frame: RealWorldFrame
    ) -> (offer: RealLineOffer, crossesTrack: Bool, laid: RealLineAcquisition?) {
        func refused(_ english: String, _ chinese: String) -> (offer: RealLineOffer, crossesTrack: Bool, laid: RealLineAcquisition?) {
            (RealLineOffer(line: line, acquisition: nil, price: nil, problem: language.text(english, chinese)), false, nil)
        }
        let metre = RealLineAcquisition.metre
        let followRefusal = refused("The real line's track could not be followed here.", "這裡沒辦法沿著真實鐵路鋪軌。")
        // The real line's drawing, closed round.
        guard let drawn = railways.lines.first(where: { $0.lineKey == "\(line.system)|\(line.network)" }), drawn.points.count > 2 else {
            return followRefusal
        }
        var shape = drawn.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
        if let first = shape.first, let last = shape.last, (first - last).length > metre { shape.append(first) }
        // Along the stops' order.
        func along(_ path: WorldPath, _ point: WorldVector) -> Double { path.nearest(point).along }
        var round = WorldPath(shape)
        func forward(_ path: WorldPath, _ a: WorldVector, _ b: WorldVector) -> Bool {
            let difference = along(path, b) - along(path, a)
            let step = difference < 0 ? difference + path.length : difference
            return step < path.length / 2
        }
        guard dataPoints.count > 2 else { return followRefusal }
        if !forward(round, dataPoints[0], dataPoints[1]) { round = WorldPath(shape.reversed()) }
        // The depot's wye leaves the second track, on the left going up
        // the line (``RealLineDepotLayout/lay(_:points:along:at:second:marks:first:length:ground:water:in:)``):
        // where the real depot is on the right, the stops go the other way
        // round.
        let site = depot ? RealLineDepotSite.sites(of: line.id).first { $0.beyond == nil } : nil
        guard let site else {
            return refused("The line's trains have no room to stand overnight.", "這條線的列車晚上沒有地方停。")
        }
        let sitePoints = [site.junction, site.yard.start, site.yard.end].map {
            WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude))
        }
        var runs = dataRuns, points = dataPoints
        do {
            let j = along(round, sitePoints[0])
            if (sitePoints[1] - round.point(at: j)).dot(round.tangent(at: j).normal) > 0 {
                runs = Self.turned(dataRuns)
                points = [dataPoints[0]] + dataPoints.dropFirst().reversed()
                round = WorldPath(round.points.reversed())
            }
        }
        let count = runs.stops.count
        let stopsAlong = points.map { along(round, $0) }
        // The seam: the middle of the longest stretch between two stops
        // with no depot in it.
        let depotAt = along(round, sitePoints[0])
        func gap(_ index: Int) -> (from: Double, length: Double) {
            let from = stopsAlong[index], to = stopsAlong[(index + 1) % count]
            return (from, to > from ? to - from : to + round.length - from)
        }
        func holdsDepot(_ index: Int) -> Bool {
            let stretch = gap(index)
            let offset = depotAt >= stretch.from ? depotAt - stretch.from : depotAt + round.length - stretch.from
            return offset < stretch.length
        }
        guard let longest = (0..<count).filter({ !holdsDepot($0) }).max(by: { gap($0).length < gap($1).length }) else { return followRefusal }
        let seamMiddle = (gap(longest).from + gap(longest).length / 2).truncatingRemainder(dividingBy: round.length)
        // The line's stops from the first past the seam, in the same order
        // round: its runs keep their stations and their way.
        let firstPast = (longest + 1) % count
        runs.stops = Array(runs.stops[firstPast...] + runs.stops[..<firstPast])
        points = Array(points[firstPast...] + points[..<firstPast])
        let start = seamMiddle + Self.ringSeam / 2
        let rotated = round.points(from: start, to: round.length) + round.points(from: 0, to: start)
        let smooth = WorldPath(rotated).smoothed().points
        // Decision 612: onto the real tracks, the drawing to its right
        // (``ringShift``); the path closes on itself, so its ends turn
        // with their neighbours across the seam.
        let ring = WorldPath(smooth.indices.map { index in
            let before = smooth[index == 0 ? max(0, smooth.count - 2) : index - 1]
            let after = smooth[index == smooth.count - 1 ? min(1, smooth.count - 1) : index + 1]
            return smooth[index] + (after - before).unit.normal * Self.ringShift
        })
        guard ring.length > 4 * Self.ringSeam else { return followRefusal }
        let mainLength = ring.length - Self.ringSeam
        let path = WorldPath(ring.points(from: 0, to: mainLength))
        let seamPath = WorldPath(ring.points(from: mainLength, to: ring.length))
        let stationsAt = points.map { path.nearest($0) }
        guard stationsAt.allSatisfy({ $0.away <= RealLineAcquisition.stationReach }), zip(stationsAt, stationsAt.dropFirst()).allSatisfy({ $0.along < $1.along }) else {
            return refused("The real line's stations are not along its track here.", "真實車站不在這段鐵路上。")
        }

        // The ground under the way and the depot's, read in on a copy;
        // decision 401, the tiles under it bought with it.
        var draft = world.pricingCopy()
        let step = 32 * metre, side = 16 * metre
        let samples = [ring, WorldPath(sitePoints)].flatMap { way in
            (0...Int(way.length / step)).flatMap { index -> [PlanPoint] in
                let point = way.point(at: Double(index) * step)
                return [(-side, -side), (-side, side), (side, -side), (side, side)].map { dx, dy in WorldVector(x: point.x + dx, y: point.y + dy).plan }
            }
        }
        let cars = line.cars
        let platformLength = Int64(cars + 1) * Train.carLength
        // Decision 621: a strip yard's ground, along the line from its wye.
        let leads = path.nearest(sitePoints[0]).along
        let yardSamples = site.strip != nil
            ? RealLineDepotLayout.Strip.groundSamples(
                along: path, at: leads, side: (sitePoints[1] - path.point(at: leads)).dot(path.tangent(at: leads).normal) >= 0 ? 1 : -1,
                site: site, length: platformLength, back: 50 * metre, step: step
            )
            : RealLineDepotLayout.groundSamples(of: sitePoints, site: site, length: platformLength, back: 50 * metre, step: step)
        var tiles: [MapTile] = []
        if let expansion = world.mapExpansion {
            let wanted = Set((samples + yardSamples).map { MapExpansion.tile(at: $0) }).filter { world.isOnMap($0) && !expansion.owns($0) }
            guard let order = RealLineAcquisition.buyingOrder(of: wanted, owned: expansion.owned) else {
                return refused(
                    "The land this line crosses does not touch yours. Use Expand Map to buy up to the line first, then buy it.",
                    "這條線經過的地和你的地不相連。先用「擴建地圖」買到這條線旁邊，再收購。"
                )
            }
            if landCheckOnly { return (RealLineOffer(line: line, acquisition: nil, price: nil, problem: nil), false, nil) }
            tiles = order
            for tile in tiles {
                try? draft.buyMapTile(tile, passingMilestone: true)
            }
            if !tiles.isEmpty {
                GameSession.readLand(roundStationsOf: &draft, population: population, places: places, water: self.water, coverage: coverage)
            }
        }
        try? draft.readGround(under: samples + yardSamples, from: heights)
        let mapped = draft.ground.isMapped
        let planning = draft
        func ground(_ point: WorldVector) -> Double {
            Double(planning.groundHeight(at: point.plan) ?? 0)
        }
        func water(_ point: WorldVector) -> Bool {
            guard mapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }

        // Each station level, a platform each way, no loop.
        let half = Double(platformLength) / 2
        var forced = [0, path.length]
        var zones: [ClosedRange<Double>] = []
        var spans: [ClosedRange<Double>] = []
        var levels: [TrackRise.Level] = []
        let carried = railways.structures?.stretches(along: path, frame: frame, system: line.system) ?? []
        func sameName(_ index: Int) -> StationID? {
            let real = railways.stations.first { $0.id == "\(line.system)|\(runs.stops[index])" }
            let names = Set([runs.stops[index], real?.name(in: language)].compactMap { $0 })
            return world.stations
                .filter { !$0.isDepot && names.contains($0.name) && (WorldVector($0.location) - points[index]).length <= RealLineAcquisition.junctionReach }
                .min { (WorldVector($0.location) - points[index]).length < (WorldVector($1.location) - points[index]).length }?.id
        }
        for index in 0..<count {
            let at = stationsAt[index].along
            let zone = (at - half)...(at + half)
            zones.append(zone)
            let span = (zone.lowerBound - RealWorldDemo.platformMargin)...(zone.upperBound + RealWorldDemo.platformMargin)
            spans.append(span)
            forced += [span.lowerBound, span.upperBound]
            let height = ground(path.point(at: at))
            let raised = switch raising {
            case .none: false
            case .viaducts, .viaductsAndShared:
                (raising == .viaductsAndShared && sameName(index) != nil) || RealLineAcquisition.isRaised(
                    at: at, before: index > 0 ? stationsAt[index - 1].along : nil,
                    after: index < count - 1 ? stationsAt[index + 1].along : nil, carried: carried
                )
            }
            let low = raised ? height + Self.ringRaisedStation : height - RealWorldDemo.stationReach
            levels.append(TrackRise.Level(span, from: low, to: low + 2 * RealWorldDemo.stationReach))
        }
        guard let firstSpan = spans.first, let lastSpan = spans.last,
              firstSpan.lowerBound > RealWorldDemo.shortestEdge, lastSpan.upperBound < path.length - RealWorldDemo.shortestEdge else {
            return refused("The real line's stations are not along its track here.", "真實車站不在這段鐵路上。")
        }
        // The depot's wye and crossovers, clear of the stations.
        let j = path.nearest(sitePoints[0]).along
        let marks = Self.ringDepotMarks(at: j)
        let reach = marks[0]...marks[marks.count - 1]
        guard reach.lowerBound > RealWorldDemo.shortestEdge, reach.upperBound < path.length - RealWorldDemo.shortestEdge,
              !spans.contains(where: { $0.overlaps(reach) }),
              (sitePoints[1] - path.point(at: j)).dot(path.tangent(at: j).normal) < 0 else {
            return refused("The line's depot does not fit here.", "這條線的機廠放不下。")
        }
        forced += marks
        let climbRefusal = refused(
            "The track cannot climb along this line within the steepest grade.",
            "沿這條線的高低差超過遊戲的坡度上限，鋪不上去。"
        )
        guard let rise = TrackRise(
            path: path, ground: ground, water: water, levels: levels, grade: line.rulingGrade, carried: carried, slack: line.stationSlack
        ) else { return climbRefusal }
        let main = RealWorldDemo.TrackPlan(path, forced: forced, avoiding: zones, rise: rise, structure: .automatic)
        // The second track beside the first all the way round, on its
        // left going up the line.
        let offset = -HighSpeedDemo.trackOffset
        let second = RealWorldDemo.TrackPlan(beside: main, at: Array(main.nodes.indices), offsets: main.nodes.map { _ in offset }, following: true)
        // The seam: each track closed from its last node to its first.
        guard let seamRise = TrackRise(
            path: seamPath, ground: ground, water: water,
            levels: [TrackRise.Level(0...0, at: Double(rise.node(at: path.length))), TrackRise.Level(seamPath.length...seamPath.length, at: Double(rise.node(at: 0)))],
            grade: line.rulingGrade
        ) else { return climbRefusal }
        let lastNode = main.nodes.count - 1
        let seam = RealWorldDemo.TrackPlan(
            seamPath, forced: [0, seamPath.length], avoiding: [], close: [0...seamPath.length], start: main.nodes[lastNode], end: main.nodes[0],
            rise: seamRise, structure: .automatic
        )
        let seamBeside = RealWorldDemo.TrackPlan(beside: seam, at: Array(seam.nodes.indices), offsets: seam.nodes.map { _ in offset }, following: true)
        var plans: [(plan: RealWorldDemo.TrackPlan, start: RealLineAcquisition.NodeAt?, end: RealLineAcquisition.NodeAt?, together: Bool)] = [
            (main, nil, nil, false),
            (second, nil, nil, true),
            (seam, RealLineAcquisition.NodeAt(piece: 0, node: lastNode), RealLineAcquisition.NodeAt(piece: 0, node: 0), true),
            (seamBeside, RealLineAcquisition.NodeAt(piece: 1, node: lastNode), RealLineAcquisition.NodeAt(piece: 1, node: 0), true),
        ]
        // The crossovers either side of the wye, as on a line with ends
        // (decision 479): onto the second track before it, off it after.
        let node = { (distance: Double) in main.distances.firstIndex { abs($0 - distance) < 1 } }
        let depotNodes = marks.compactMap(node)
        guard depotNodes.count == 6 else { return refused("The line's depot does not fit here.", "這條線的機廠放不下。") }
        let depotMarks = depotNodes.map { (main: $0, second: $0) }
        plans.append((
            RealWorldDemo.TrackPlan(beside: main, at: [depotNodes[0], depotNodes[1]], offsets: [0, offset]),
            RealLineAcquisition.NodeAt(piece: 0, node: depotNodes[0]), RealLineAcquisition.NodeAt(piece: 1, node: depotNodes[1]), true
        ))
        plans.append((
            RealWorldDemo.TrackPlan(beside: main, at: [depotNodes[4], depotNodes[5]], offsets: [offset, 0]),
            RealLineAcquisition.NodeAt(piece: 1, node: depotNodes[4]), RealLineAcquisition.NodeAt(piece: 0, node: depotNodes[5]), true
        ))
        var pieces = plans.map { entry in
            let plan = entry.plan
            let nodes = plan.nodes.indices.map { WorldCoordinate(x: plan.nodes[$0].point.x, y: plan.nodes[$0].point.y, z: plan.heights[$0]) }
            let ground = plan.curves.indices.flatMap { index -> [PlanPoint] in
                let surveyed = TrackGeometry(from: nodes[index], to: nodes[index + 1], curve: plan.curves[index]).map(NetworkBuilding.surveyedPoints(of:)) ?? []
                return [nodes[index].plan, nodes[index + 1].plan] + surveyed
            }
            return RealLineAcquisition.Piece(
                nodes: nodes, start: entry.start, end: entry.end, curves: plan.curves, distances: plan.distances, structure: plan.structure,
                together: entry.together, ground: ground
            )
        }
        let laidDepot = site.strip != nil
            ? RealLineDepotLayout.strip(
                site, along: path, at: j, second: second, marks: depotMarks, first: pieces.count, length: platformLength, ground: ground, in: language
            )
            : RealLineDepotLayout.lay(
                site, points: sitePoints, along: path, at: j, second: second, marks: depotMarks, first: pieces.count, length: platformLength,
                ground: ground, water: water, in: language
            )
        guard let laidDepot else {
            return refused("The line's depot does not fit here.", "這條線的機廠放不下。")
        }
        pieces += laidDepot.pieces

        let stops = runs.stops.enumerated().map { index, name in
            let at = path.point(at: stationsAt[index].along).plan
            let real = railways.stations.first { $0.id == "\(line.system)|\(name)" }
            return RealLineAcquisition.Stop(
                name: real?.name(in: language) ?? name, at: at, existing: sameName(index),
                demand: GameSession.newStationDemand(at: at, in: world, population: population, places: places)
            )
        }
        // Each stop's platforms, the first track's first.
        let platforms = zones.indices.flatMap { stop in
            [0, 1].map { piece in
                RealLineAcquisition.Platform(stop: stop, at: RealLineAcquisition.PieceAt(piece: piece, distance: zones[stop].lowerBound), length: platformLength)
            }
        }
        // Every train in the depot overnight.
        let trainsets = runs.overnight.values.reduce(0, +)
        guard trainsets <= laidDepot.depot.platforms.count else {
            return refused("The line's trains have no room to stand overnight.", "這條線的列車晚上沒有地方停。")
        }
        let lineName = line.name(in: language)
        let starts = laidDepot.depot.platforms.prefix(trainsets).enumerated().map { number, at in
            RealLineAcquisition.Start(name: RealWorldDemo.trainName(line: lineName, number: number + 1, in: language), at: at, forward: true)
        }
        let lineRuns = runs.runs.map { run in
            LineRun(
                from: runs.stops.firstIndex(of: run.calls[0].station) ?? 0,
                to: runs.stops.firstIndex(of: run.calls[run.calls.count - 1].station) ?? 0,
                times: run.calls.map { LineRunTime(arrival: $0.arrival, departure: $0.departure) },
                days: run.days.reduce(0) { $0 | 1 << $1 }, way: run.way
            )
        }
        // Kaohsiung publishes only the whole line's riders a day, not each
        // stop's: each stop counts as a light rail stop with no figure of
        // its own does (``GameSession/transferPoints(of:data:ridership:)``,
        // one point), not as the metro station of the same name beside it
        // (Hamasen's); some 38,000 a day, near the line's real 40,000.
        let riders = Int64(count * GameSession.transferRidersPerPoint)
        let color = railways.lines.first { $0.lineKey == "\(line.system)|\(line.network)" }
            .flatMap { LineColor(rgb: Int($0.palette.color.red) << 16 | Int($0.palette.color.green) << 8 | Int($0.palette.color.blue)) }
        func acquisition(buying tiles: [MapTile]) -> RealLineAcquisition {
            RealLineAcquisition(
                realLine: line.id, pieces: pieces, stops: stops, platforms: platforms, lineName: lineName, color: color, runs: lineRuns,
                trains: starts, cars: cars, trainType: line.trainType, dailyRiders: min(riders, LineAcquisition.maximumDailyRiders),
                tiles: tiles.isEmpty ? nil : tiles, tier: line.tier, depot: laidDepot.depot, ring: true
            )
        }
        // GameCore's answer and the price, on a funded copy.
        while true {
            let bought = acquisition(buying: tiles)
            var probe = world.pricingCopy()
            do throws(GameError) {
                let price = try build(bought, in: &probe)
                return (RealLineOffer(line: line, acquisition: bought, price: price, problem: nil), false, nil)
            } catch {
                if case .mapTileNotOwned(let tile) = error, let owned = world.mapExpansion?.owned, !tiles.contains(tile) {
                    guard let order = RealLineAcquisition.buyingOrder(of: Set(tiles + [tile]), owned: owned) else {
                        return refused(
                            "The land this line crosses does not touch yours. Use Expand Map to buy up to the line first, then buy it.",
                            "這條線經過的地和你的地不相連。先用「擴建地圖」買到這條線旁邊，再收購。"
                        )
                    }
                    tiles = order
                    continue
                }
                let crosses = if case .trackConflict = error { true } else { false }
                return (RealLineOffer(line: line, acquisition: nil, price: nil, problem: error.playerMessage(in: language)), crosses, bought)
            }
        }
    }

    /// Decision 535 (continued, KLRT): where a ring's trains stop at each
    /// station, by the line's stops (``build(_:in:recording:)`` lists them
    /// the other way round from the ring as laid, each with its first
    /// track's platform and then its second's): the trains keep right,
    /// so those going the way the ring was laid (down the line's stops)
    /// stop on the first track, those going the other way on the second.
    /// The leg round from the last stop to the first, and back, too.
    static func ringRoutePreferences(_ platformsOf: [Int: [TrackPlatform]], stops: Int) -> [LineRoutePreference] {
        var routes: [LineRoutePreference] = []
        for (stop, platforms) in platformsOf.sorted(by: { $0.key < $1.key }) where platforms.count > 1 {
            routes.append(LineRoutePreference(from: (stop + stops - 1) % stops, to: stop, platform: platforms[1]))
            routes.append(LineRoutePreference(from: (stop + 1) % stops, to: stop, platform: platforms[0]))
        }
        return routes
    }
}
