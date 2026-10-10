import Foundation
import GameCore

// The real-world demo (2026-10-05, the author's request): a real-world map
// whose railway is Taiwan's real one, built as the game's own track so the
// game's rules can be tried on real lines. The lines are the `Railway/`
// site's (``RealRailways``), projected onto the world as the app lays the
// world over Apple's map, so the built track lies on the real one drawn
// under it.

extension RealWorldFrame {
    /// The world point at `latitude`° north, `longitude`° east, in world
    /// units: the same place the app's map shows there (Web Mercator, as
    /// MapKit's map points, at a metre of the world to a metre at the
    /// anchor's latitude; see ``RealWorldFrame``).
    public func worldPosition(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
        let anchorLatitude = anchor.latitudeDegrees
        let pointsPerMetre = Self.worldPoints / (2 * Double.pi * Self.earthRadius * cos(anchorLatitude * .pi / 180))
        let east = (Self.mercatorX(longitude) - Self.mercatorX(anchor.longitudeDegrees)) / pointsPerMetre
        let south = (Self.mercatorY(latitude) - Self.mercatorY(anchorLatitude)) / pointsPerMetre
        return worldPosition(east: east, south: south)
    }

    /// MapKit's world: 2^28 map points a side, the Earth's equatorial
    /// radius in metres (WGS-84).
    static let worldPoints = 268_435_456.0
    static let earthRadius = 6_378_137.0

    static func mercatorX(_ longitude: Double) -> Double {
        (longitude + 180) / 360 * worldPoints
    }

    static func mercatorY(_ latitude: Double) -> Double {
        let sine = sin(latitude * .pi / 180)
        return (0.5 - log((1 + sine) / (1 - sine)) / (4 * Double.pi)) * worldPoints
    }
}

/// A real-world game with Taiwan's real railway built and running, to try
/// the game on (2026-10-05, the author's request): the Pingxi Line from
/// Sandiaoling to Jingtong, the Yilan Line from Sijiaoting through Ruifang
/// and Houtong to Sandiaoling, and the Shenao Line from Ruifang to Badouzi,
/// on their real alignments over Apple's map.
///
/// Built like ``DemoWorld``: a new game at ``anchor`` and ordinary
/// `GameWorld` commands that charge their usual costs. The game starts
/// with what they cost on top of a new game's money, so what is left is a
/// new game's.
///
/// The track is the game's, not the real one's: the real lines' centre
/// lines become a single track of smooth curves (cubic edges whose
/// directions agree at every node, so trains run through), the stations
/// have a platform each, and Ruifang, Houtong, Sandiaoling and Shifen have a
/// passing loop with a second platform (the real Yilan Line is double
/// track; Shifen is where the real Pingxi Line's trains meet). The Shenao
/// Line leaves the Yilan Line at the west end of Ruifang's loop.
///
/// - The Pingxi Line runs Ruifang to Jingtong with two trains.
/// - The Yilan Line runs Sijiaoting to Sandiaoling with one train, on the
///   same track.
/// - The Shenao Line runs Badouzi to Ruifang with one train.
///
/// Traffic control is on, as in every new game, so the trains meet at the
/// loops and wait for each other on the single track.
public enum RealWorldDemo {
    /// The middle of the map: between Badouzi in the north, Jingtong in the
    /// south-west and Houtong in the east, all within 6.4 km of it.
    public static let anchor: GeoAnchor = {
        guard let anchor = GeoAnchor(latitude: 250_805_000, longitude: 1_217_756_000) else {
            preconditionFailure("The demo's anchor is not on the Earth")
        }
        return anchor
    }()

    /// The demo as it was before decision 132, flat at 0 m and with the
    /// lines above, built on `railways`, with `land` the map's people
    /// (``LandImport``; without it, the towns of a new game) and `water`
    /// its water (``WaterGrid``, decision 105) and steep slopes (decision
    /// 115). The Pingxi challenge (decision 90) is played on it: its
    /// targets were measured there. The demo itself is
    /// ``make(in:railways:land:water:steep:heights:)``.
    public static func makeFlat(
        in language: DisplayLanguage, railways: RealRailways, land: [LandCell]? = nil, water: [CellPosition] = [], steep: [CellPosition] = []
    ) -> GameWorld {
        let layout = Layout(railways: railways)
        var world = GameWorld.newGame(
            anchor: anchor, balance: GameWorld.startingBalance + layout.cost(at: ConstructionCosts.newGame), land: land, water: water, steep: steep
        )
        // The demo's stations keep the ridership it gives them (Phase 6b).
        // Unlike the blank demo (ARCHITECTURE decision 78) it does not take
        // them from the land: most of its riders come for the sights, which
        // the land does not hold, and without the app's people its stations
        // would have none.
        world.setLandDemand(false)
        do throws(GameError) {
            try layout.build(in: &world, language: language)
        } catch {
            preconditionFailure("The real-world demo no longer builds: \(error)")
        }
        return world
    }

    // MARK: - The layout

    /// Cars per train; each platform takes a car more.
    static let cars = 3
    static let trains = 4
    static let platformLength = Int64(cars + 1) * Train.carLength
    /// Room left between a platform and the nearest node.
    static let platformMargin = 16.0 * metre
    /// How far each end of a passing loop lies from its station, how far it
    /// stands off the main track, and over how much of each end it moves
    /// out to it.
    static let loopReach = 200.0 * metre
    static let loopOffset = 5.0 * metre
    static let loopRamp = 100.0 * metre
    /// How far the Yilan Line runs on past Sijiaoting, its west terminal.
    static let westRunOn = 250.0 * metre

    static let metre = Double(WorldCoordinate.unitsPerMetre)

    /// A real station: the site's, and where it is in the world.
    struct Stop {
        let station: RealRailways.Station
        let point: WorldVector
    }

    /// Where everything goes: worked out before anything is built, so the
    /// game can start with what it costs.
    struct Layout {
        let main: TrackPlan
        let loops: [TrackPlan]
        let branch: TrackPlan
        let mainStops: [Stop]
        let mainPlatforms: [ClosedRange<Double>]
        let loopStops: [Stop]
        let branchStops: [Stop]
        let branchPlatforms: [ClosedRange<Double>]
        /// Where on the main track the loops leave and rejoin it, and the
        /// Shenao Line leaves it.
        let loopEnds: [(Double, Double)]
        let junction: Double

        init(railways: RealRailways) {
            let frame = RealWorldFrame(anchor: RealWorldDemo.anchor, bounds: GameWorld.newGameBounds)
            func line(_ prefix: String) -> WorldPath {
                guard let line = railways.lines.first(where: { $0.name.hasPrefix(prefix) }) else {
                    preconditionFailure("The real railways have no \(prefix)")
                }
                return WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
            }
            func stop(_ name: String) -> Stop {
                guard let station = railways.stations.first(where: { $0.id == "tra_sched|\(name)" }) else {
                    preconditionFailure("The real railways have no \(name)")
                }
                return Stop(station: station, point: WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude)))
            }

            let yilan = line("宜蘭線"), pingxi = line("平溪線"), shenao = line("深澳線")
            let sijiaoting = stop("四腳亭"), ruifang = stop("瑞芳"), houtong = stop("猴硐"), sandiaoling = stop("三貂嶺")
            let pingxiStops = ["大華", "十分", "望古", "嶺腳", "平溪", "菁桐"].map(stop)

            // The main track: the Yilan Line's centre line from past
            // Sijiaoting back to Sandiaoling (the site's runs the other way),
            // then the Pingxi Line's on to Jingtong.
            let from = yilan.project(sandiaoling.point), to = yilan.project(sijiaoting.point) + westRunOn
            let mainPath = WorldPath(yilan.points(from: from, to: to).reversed() + pingxi.points).smoothed()
            let mainStops = [sijiaoting, ruifang, houtong, sandiaoling] + pingxiStops
            let mainPlatforms = mainStops.map { platformZone(on: mainPath, at: $0.point) }
            let loopStops = [ruifang, houtong, sandiaoling, pingxiStops[1]]
            let loopEnds = loopStops.map { stop in
                let at = mainPath.project(stop.point)
                return (at - loopReach, at + loopReach)
            }
            let junction = loopEnds[0].0
            let main = TrackPlan(
                mainPath, forced: [0, mainPath.length] + loopEnds.flatMap { [$0.0, $0.1] }, avoiding: mainPlatforms,
                close: [(junction - besideReach)...junction]
            )

            // Each loop leaves the main track at one node and joins it again
            // at the next, standing off it in the middle.
            let loops = loopEnds.map { ends in
                let path = mainPath.offset(from: ends.0, to: ends.1, by: loopOffset, ramp: loopRamp)
                return TrackPlan(
                    path, forced: [0, path.length], avoiding: [middlePlatform(of: path)],
                    start: main.node(at: ends.0), end: main.node(at: ends.1)
                )
            }

            // The Shenao Line leaves at the west end of Ruifang's loop,
            // heading west beside the Yilan Line before it turns north.
            let beside = shenao.project(mainPath.point(at: junction))
            let branchPath = WorldPath([mainPath.point(at: junction)] + shenao.points(from: beside + 120 * metre, to: shenao.length).dropFirst()).smoothed()
            let branchStops = ["海科館", "八斗子"].map(stop)
            let branchPlatforms = branchStops.map { platformZone(on: branchPath, at: $0.point) }
            guard let start = main.node(at: junction) else { preconditionFailure("The junction is not a node") }
            branch = TrackPlan(
                branchPath, forced: [0, branchPath.length], avoiding: branchPlatforms, looseUntil: 300 * metre, close: [0...besideReach],
                start: (start.point, start.direction.reversed)
            )
            self.main = main
            self.loops = loops
            self.mainStops = mainStops
            self.mainPlatforms = mainPlatforms
            self.loopStops = loopStops
            self.branchStops = branchStops
            self.branchPlatforms = branchPlatforms
            self.loopEnds = loopEnds
            self.junction = junction
        }

        /// What building it costs at `costs` (the prices of
        /// ``GameWorld/buildTrackEdge(from:to:curve:profile:structure:)``,
        /// ``GameWorld/buildStation(named:at:)``,
        /// ``GameWorld/purchaseTrain(named:)`` and
        /// ``GameWorld/setTrainCars(_:to:)``): every track is on the ground.
        func cost(at costs: ConstructionCosts) -> Money {
            let tracks = ([main, branch] + loops).flatMap(\.lengths).map { length in
                max(1, (length + ConstructionCosts.trackPricingLength - 1) / ConstructionCosts.trackPricingLength) * TrackStructure.surface.costFactor
            }
            let track = tracks.reduce(0, +) * costs.track.amount
            let stations = Int64(Set((mainStops + branchStops).map(\.station.id)).count) * costs.station.amount
            let trains = Int64(RealWorldDemo.trains) * (costs.train.amount + Int64(cars - 1) * costs.car.amount)
            return Money(track + stations + trains)
        }

        func build(in world: inout GameWorld, language: DisplayLanguage) throws(GameError) {
            let mainTrack = try main.build(in: &world)
            var loopTracks: [Track] = []
            for (plan, ends) in zip(loops, loopEnds) {
                guard let start = mainTrack.node(at: ends.0), let end = mainTrack.node(at: ends.1) else { preconditionFailure("A loop's ends are not nodes") }
                loopTracks.append(try plan.build(in: &world, start: start, end: end))
            }
            guard let junctionNode = mainTrack.node(at: junction) else { preconditionFailure("The junction is not a node") }
            let branchTrack = try branch.build(in: &world, start: junctionNode)

            // The stations, each at its first platform.
            var ids: [String: StationID] = [:]
            func platform(_ stop: Stop, on track: Track, zone: ClosedRange<Double>) throws(GameError) {
                let id: StationID
                if let built = ids[stop.station.id] {
                    id = built
                } else {
                    let middle = track.plan.path.point(at: (zone.lowerBound + zone.upperBound) / 2)
                    id = try world.buildStation(named: stop.station.name(in: language), at: middle.plan).id
                    ids[stop.station.id] = id
                }
                let (edge, offset) = track.edge(at: zone.lowerBound, in: world)
                try world.addTrackPlatform(id, on: edge, from: offset, to: offset + platformLength)
            }
            for (stop, zone) in zip(mainStops, mainPlatforms) {
                try platform(stop, on: mainTrack, zone: zone)
            }
            for (stop, track) in zip(loopStops, loopTracks) {
                try platform(stop, on: track, zone: middlePlatform(of: track.plan.path))
            }
            for (stop, zone) in zip(branchStops, branchPlatforms) {
                try platform(stop, on: branchTrack, zone: zone)
            }
            func id(_ stop: Stop) -> StationID {
                guard let id = ids[stop.station.id] else { preconditionFailure("\(stop.station.id) was not built") }
                return id
            }
            // Every station has ridership, so passengers, fares and costs
            // start at once: towns where people live and work, the Pingxi
            // Line's sights and the sea at Badouzi. The game's numbers, not
            // real ones.
            for (stop, kind, trips) in RealWorldDemo.ridership(mainStops + branchStops) {
                try world.setStationDemand(id(stop), to: StationDemand(kind: kind, dailyTrips: trips))
            }

            // The lines and their trains, each train at its line's first
            // platform facing the way it leaves.
            func place(_ name: String, on track: Track, zone: ClosedRange<Double>, forward: Bool) throws(GameError) -> TrainID {
                let train = try world.purchaseTrain(named: name).id
                try world.setTrainCars(train, to: cars)
                let (edge, start) = track.edge(at: zone.lowerBound, in: world)
                let length = world.network.edge(edge)?.length ?? 0
                let offset = forward ? start + platformLength : length - start
                try world.placeTrain(train, at: .onEdge(TrackTraversal(edge: edge, direction: forward ? .forward : .backward), offset: offset))
                try world.setTrainContinuation(train, along: [], stoppingAt: offset)
                try world.setTrainMovementRate(train, to: 512)
                return train
            }
            func run(_ name: String, calling stops: [Stop], trains: Int) throws(GameError) -> LineID {
                let line = try world.createLine(named: name, stops: stops.map(id)).id
                try world.setLineServiceWindow(line, to: .allDay)
                try world.setLineTrainsInService(line, to: TrainsInService(peak: trains, offPeak: trains, low: trains))
                return line
            }
            let names = RealWorldDemo.lineNames(in: language)
            func train(_ line: Int, _ number: Int) -> String {
                RealWorldDemo.trainName(line: names[line], number: number, in: language)
            }
            let (ruifang, houtong, sandiaoling) = (mainStops[1], mainStops[2], mainStops[3])

            let pingxi = try run(names[0], calling: [ruifang, houtong, sandiaoling] + mainStops.dropFirst(4), trains: 2)
            try world.assignTrain(try place(train(0, 1), on: mainTrack, zone: mainPlatforms[1], forward: true), to: pingxi)
            try world.assignTrain(try place(train(0, 2), on: loopTracks[0], zone: middlePlatform(of: loopTracks[0].plan.path), forward: true), to: pingxi)

            let yilan = try run(names[1], calling: [mainStops[0], ruifang, houtong, sandiaoling], trains: 1)
            try world.assignTrain(try place(train(1, 1), on: mainTrack, zone: mainPlatforms[0], forward: true), to: yilan)

            let shenao = try run(names[2], calling: [branchStops[1], branchStops[0], ruifang], trains: 1)
            try world.assignTrain(try place(train(2, 1), on: branchTrack, zone: branchPlatforms[1], forward: false), to: shenao)
        }
    }

    /// The lines' names: the Pingxi, Yilan and Shenao Lines.
    static func lineNames(in language: DisplayLanguage) -> [String] {
        [language.text("Pingxi Line", "平溪線"), language.text("Yilan Line", "宜蘭線"), language.text("Shenao Line", "深澳線")]
    }

    static func trainName(line: String, number: Int, in language: DisplayLanguage) -> String {
        language.text("\(line) Train \(number)", "\(line)列車 \(number)")
    }

    /// Each station's ridership, by its Chinese name.
    static let ridershipByName: [String: (StationDemandKind, Int64)] = [
        "四腳亭": (.residential, 8_000), "瑞芳": (.office, 20_000), "猴硐": (.scenic, 6_000), "三貂嶺": (.scenic, 2_000),
        "大華": (.scenic, 1_000), "十分": (.scenic, 10_000), "望古": (.scenic, 1_000), "嶺腳": (.residential, 2_000),
        "平溪": (.scenic, 6_000), "菁桐": (.scenic, 6_000), "海科館": (.scenic, 5_000), "八斗子": (.residential, 4_000),
        // Decision 132's longer demo.
        "七堵": (.residential, 12_000), "八堵": (.residential, 6_000), "暖暖": (.residential, 5_000), "牡丹": (.residential, 1_000),
        "三坑": (.residential, 4_000), "基隆": (.office, 24_000),
    ]

    static func ridership(_ stops: [Stop]) -> [(Stop, StationDemandKind, Int64)] {
        stops.compactMap { stop in
            ridershipByName[stop.station.name(in: .traditionalChinese)].map { (stop, $0.0, $0.1) }
        }
    }

    /// Where a station's platform lies along `path`: centred on the point of
    /// the path nearest the station, moved in from either end of the path
    /// so it keeps clear of it.
    static func platformZone(on path: WorldPath, at point: WorldVector) -> ClosedRange<Double> {
        let half = Double(platformLength) / 2
        let room = half + platformMargin
        let middle = min(max(path.project(point), room), path.length - room)
        return (middle - half)...(middle + half)
    }

    /// A platform in the middle of a passing loop.
    static func middlePlatform(of path: WorldPath) -> ClosedRange<Double> {
        let middle = path.length / 2, half = Double(platformLength) / 2
        return (middle - half)...(middle + half)
    }

    // MARK: - Laying track

    /// The tolerances of the fit: how far an edge may stray from the
    /// smoothed centre line (closely where the Shenao Line runs beside the
    /// Yilan Line, 6 to 12 m off it, so the two keep 4 m apart, and on the
    /// ground demo through the passing loops), how long
    /// and how short it may be, and how far its direction may turn.
    static let tolerance = 3.0 * metre
    static let closeTolerance = 1.0 * metre
    /// How far the Shenao Line runs beside the Yilan Line west of Ruifang.
    static let besideReach = 1_300.0 * metre
    static let longestEdge = 960.0 * metre
    static let shortestEdge = 30.0 * metre
    static let sharpestTurn = 60.0 * Double.pi / 180

    /// Track to lay along a path: nodes at `forced` distances along it and
    /// wherever the fit needs one, but never within a platform `avoiding`
    /// (and its margin); between them, cubic edges that leave and reach
    /// each node along the path's direction there, so every node joins the
    /// edges on either side.
    ///
    /// `start` and `end` give nodes already planned, and the direction to
    /// leave them by, for the path's ends. Up to `looseUntil` along the
    /// path the edges need not follow it closely: a branch's first edge,
    /// which leaves its junction along the main track before it moves over
    /// to its own line.
    struct TrackPlan {
        let path: WorldPath
        let distances: [Double]
        /// The node at each distance, and the way the track runs there.
        let nodes: [(point: PlanPoint, direction: WorldVector)]
        let curves: [TrackCurve]

        /// The height of each node, in world units: 0 on flat ground.
        let heights: [Int64]
        /// What carries each edge.
        let structure: TrackStructure

        /// With `rise` (decision 132) the track has the heights it gives,
        /// edges are cut until their straight grade keeps close to it, and
        /// never where a node would stand too far above or below the ground.
        init(
            _ path: WorldPath, forced: [Double], avoiding: [ClosedRange<Double>], looseUntil: Double = 0, close: [ClosedRange<Double>] = [],
            start: (point: PlanPoint, direction: WorldVector)? = nil, end: (point: PlanPoint, direction: WorldVector)? = nil,
            rise: TrackRise? = nil, structure: TrackStructure = .surface
        ) {
            self.path = path
            self.structure = structure
            let keepOut = avoiding.map { ($0.lowerBound - platformMargin)...($0.upperBound + platformMargin) }
            func tangent(at distance: Double) -> WorldVector {
                if distance == 0, let start { return start.direction }
                if distance == path.length, let end { return end.direction }
                return path.tangent(at: distance)
            }
            func cubic(_ a: Double, _ b: Double) -> (WorldVector, WorldVector, WorldVector, WorldVector) {
                let p0 = path.point(at: a), p3 = path.point(at: b)
                let handle = (b - a) / 3
                return (p0, p0 + tangent(at: a) * handle, p3 - tangent(at: b) * handle, p3)
            }
            // Splits until every piece is close enough to the path.
            var cuts: [Double] = []
            func split(_ a: Double, _ b: Double) {
                let length = b - a
                let turn = tangent(at: a).angle(to: tangent(at: b))
                let limit = close.contains { $0.overlaps(a...b) } ? closeTolerance : tolerance
                let near = b <= looseUntil || deviation(of: cubic(a, b), from: path, between: a, and: b) <= limit
                let level = rise?.fits(from: a, to: b) ?? true
                if length <= longestEdge, turn <= sharpestTurn, near, level { return }
                guard length > 2 * shortestEdge else { return }
                var cut = (a + b) / 2
                if let zone = keepOut.first(where: { $0.contains(cut) }) {
                    if zone.lowerBound > a + shortestEdge {
                        cut = zone.lowerBound
                    } else if zone.upperBound < b - shortestEdge {
                        cut = zone.upperBound
                    } else {
                        return
                    }
                }
                if let rise, !rise.allowsNode(at: cut) {
                    // The nearest place a node may stand, every 16 m either
                    // way; none in a deep tunnel, which stays one edge.
                    let step = 16 * metre
                    let places = (1...Int(length / step)).flatMap { [cut - Double($0) * step, cut + Double($0) * step] }
                    guard let place = places.first(where: { place in
                        place > a + shortestEdge && place < b - shortestEdge && rise.allowsNode(at: place)
                            && !keepOut.contains { $0.contains(place) }
                    }) else { return }
                    cut = place
                }
                split(a, cut)
                cuts.append(cut)
                split(cut, b)
            }
            let forced = Array(Set(forced)).sorted()
            var distances: [Double] = []
            for (a, b) in zip(forced, forced.dropFirst()) {
                distances.append(a)
                split(a, b)
            }
            distances = (distances + cuts + [forced[forced.count - 1]]).sorted()
            self.distances = distances

            var nodes = distances.map { (point: path.point(at: $0).plan, direction: tangent(at: $0)) }
            if let start { nodes[0] = start }
            if let end { nodes[nodes.count - 1] = end }
            self.nodes = nodes
            heights = distances.map { rise?.node(at: $0) ?? 0 }
            curves = distances.indices.dropLast().map { index in
                let handle = (distances[index + 1] - distances[index]) / 3
                let c1 = WorldVector(nodes[index].point) + nodes[index].direction * handle
                let c2 = WorldVector(nodes[index + 1].point) - nodes[index + 1].direction * handle
                return .cubic(c1.plan, c2.plan)
            }
        }

        /// The planned node at `distance` along the path, if one is there.
        func node(at distance: Double) -> (point: PlanPoint, direction: WorldVector)? {
            distances.firstIndex { abs($0 - distance) < 1 }.map { nodes[$0] }
        }

        /// Each edge's length, as the game works it out.
        var lengths: [Int64] {
            curves.indices.compactMap { index in
                TrackGeometry(
                    from: WorldCoordinate(x: nodes[index].point.x, y: nodes[index].point.y),
                    to: WorldCoordinate(x: nodes[index + 1].point.x, y: nodes[index + 1].point.y),
                    curve: curves[index]
                )?.length
            }
        }

        /// Builds the track, from `start` and to `end` if they are built;
        /// `together`, its edges as one command
        /// (``GameWorld/buildTrackEdges(_:)``), the spacing checked once all
        /// are built: a passing loop, which runs within 4 m of the main
        /// track near each end, joins it at its far end only with its last
        /// edge.
        func build(in world: inout GameWorld, start: TrackNodeID? = nil, end: TrackNodeID? = nil, together: Bool = false) throws(GameError) -> Track {
            var ids: [TrackNodeID] = []
            for (index, node) in nodes.enumerated() {
                if index == 0, let start {
                    ids.append(start)
                } else if index == nodes.count - 1, let end {
                    ids.append(end)
                } else {
                    ids.append(try world.buildTrackNode(at: WorldCoordinate(x: node.point.x, y: node.point.y, z: heights[index])))
                }
            }
            var edges: [TrackEdgeID] = []
            if together {
                edges = try world.buildTrackEdges(curves.enumerated().map { index, curve in
                    TrackEdgePlan(from: ids[index], to: ids[index + 1], curve: curve, structure: structure)
                })
            } else {
                for (index, curve) in curves.enumerated() {
                    edges.append(try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: structure))
                }
            }
            return Track(plan: self, nodes: ids, edges: edges)
        }
    }

    /// How far the cubic `a`…`b` strays from `path` between those distances
    /// along it, sampled at sixteenths.
    static func deviation(of curve: (WorldVector, WorldVector, WorldVector, WorldVector), from path: WorldPath, between a: Double, and b: Double) -> Double {
        let points = path.points(from: a, to: b)
        var farthest = 0.0
        for step in 1..<16 {
            let t = Double(step) / 16, u = 1 - t
            let point = curve.0 * (u * u * u) + curve.1 * (3 * u * u * t) + curve.2 * (3 * u * t * t) + curve.3 * (t * t * t)
            var nearest = Double.infinity
            for (p, q) in zip(points, points.dropFirst()) {
                nearest = min(nearest, point.distance(toSegment: p, q))
            }
            farthest = max(farthest, nearest)
        }
        return farthest
    }

    /// Track built from a plan: its nodes and edges.
    struct Track {
        let plan: TrackPlan
        let nodes: [TrackNodeID]
        let edges: [TrackEdgeID]

        /// The node at `distance` along the path, if one stands there.
        func node(at distance: Double) -> TrackNodeID? {
            plan.distances.firstIndex { abs($0 - distance) < 1 }.map { nodes[$0] }
        }

        /// The edge `distance` along the path is on, and how far along the
        /// edge it is, in the edge's own length.
        func edge(at distance: Double, in world: GameWorld) -> (TrackEdgeID, Int64) {
            let distances = plan.distances
            let index = max(0, min(edges.count - 1, distances.lastIndex { $0 <= distance } ?? 0))
            let a = distances[index], b = distances[index + 1]
            let length = Double(world.network.edge(edges[index])?.length ?? 0)
            return (edges[index], Int64(((distance - a) / (b - a) * length).rounded()))
        }
    }
}

// MARK: - Plane geometry

/// A point or direction in the world's plan, in world units.
struct WorldVector: Hashable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: (x: Double, y: Double)) {
        self.init(x: point.x, y: point.y)
    }

    init(_ point: PlanPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    /// The nearest whole point.
    var plan: PlanPoint {
        PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded()))
    }

    var length: Double {
        (x * x + y * y).squareRoot()
    }

    var reversed: WorldVector {
        WorldVector(x: -x, y: -y)
    }

    var unit: WorldVector {
        let length = length
        return length > 0 ? WorldVector(x: x / length, y: y / length) : self
    }

    /// The direction a quarter turn from this one, one way round.
    var normal: WorldVector {
        WorldVector(x: -y, y: x)
    }

    static func + (a: WorldVector, b: WorldVector) -> WorldVector { WorldVector(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: WorldVector, b: WorldVector) -> WorldVector { WorldVector(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: WorldVector, k: Double) -> WorldVector { WorldVector(x: a.x * k, y: a.y * k) }

    func dot(_ other: WorldVector) -> Double {
        x * other.x + y * other.y
    }

    /// The angle between two directions, 0 to π.
    func angle(to other: WorldVector) -> Double {
        acos(max(-1, min(1, unit.dot(other.unit))))
    }

    func distance(toSegment a: WorldVector, _ b: WorldVector) -> Double {
        let along = b - a
        let squared = along.dot(along)
        let t = squared > 0 ? max(0, min(1, (self - a).dot(along) / squared)) : 0
        return (a + along * t - self).length
    }
}

/// A line through points in the plan, measured along its length.
struct WorldPath: Sendable {
    let points: [WorldVector]
    /// The distance along the path to each point.
    let distances: [Double]

    /// The path through `points`, without points that repeat the one before
    /// to within a centimetre.
    init(_ points: [WorldVector]) {
        var kept: [WorldVector] = []
        for point in points where kept.last.map({ ($0 - point).length >= 0.64 }) ?? true {
            kept.append(point)
        }
        self.points = kept
        var distances: [Double] = [0]
        for (a, b) in zip(kept, kept.dropFirst()) {
            distances.append(distances[distances.count - 1] + (b - a).length)
        }
        self.distances = distances
    }

    var length: Double {
        distances[distances.count - 1]
    }

    /// The point `distance` along the path, the ends beyond it.
    func point(at distance: Double) -> WorldVector {
        let distance = min(max(distance, 0), length)
        guard let index = distances.lastIndex(where: { $0 <= distance }), index < points.count - 1 else {
            return points[points.count - 1]
        }
        let a = distances[index], b = distances[index + 1]
        let t = b > a ? (distance - a) / (b - a) : 0
        return points[index] + (points[index + 1] - points[index]) * t
    }

    /// The way the path runs at `distance`: along its chord 25 m either
    /// way, which smooths out the kinks of a surveyed line.
    func tangent(at distance: Double) -> WorldVector {
        let reach = 25.0 * Double(WorldCoordinate.unitsPerMetre)
        return (point(at: distance + reach) - point(at: distance - reach)).unit
    }

    /// How far along the path its point nearest `point` lies.
    func project(_ point: WorldVector) -> Double {
        var best = (distance: Double.infinity, along: 0.0)
        for index in points.indices.dropLast() {
            let a = points[index], b = points[index + 1]
            let along = b - a
            let squared = along.dot(along)
            let t = squared > 0 ? max(0, min(1, (point - a).dot(along) / squared)) : 0
            let away = (a + along * t - point).length
            if away < best.distance {
                best = (away, distances[index] + t * (distances[index + 1] - distances[index]))
            }
        }
        return best.along
    }

    /// The path's points from `start` to `end` along it, the ends included.
    func points(from start: Double, to end: Double) -> [WorldVector] {
        let start = min(max(start, 0), length), end = min(max(end, 0), length)
        let inside = zip(points, distances).filter { $0.1 > start && $0.1 < end }.map(\.0)
        return [point(at: start)] + inside + [point(at: end)]
    }

    /// The path resampled every 5 m and averaged over 15 m either way (less
    /// near its ends, which stay where they are): a surveyed line's small
    /// kinks smoothed out, its curves kept.
    func smoothed() -> WorldPath {
        let metre = Double(WorldCoordinate.unitsPerMetre)
        let spacing = 5 * metre, reach = 3
        let count = max(2, Int((length / spacing).rounded()))
        let samples = (0...count).map { point(at: length * Double($0) / Double(count)) }
        var points: [WorldVector] = []
        for index in samples.indices {
            let window = min(reach, index, samples.count - 1 - index)
            var sum = WorldVector(x: 0, y: 0)
            for other in (index - window)...(index + window) {
                sum = sum + samples[other]
            }
            points.append(sum * (1 / Double(2 * window + 1)))
        }
        return WorldPath(points)
    }

    /// A path beside this one from `start` to `end` along it, standing
    /// `offset` off it to one side, and moving out to that over `ramp` at
    /// each end along a smooth step (no sideways slope where it leaves and
    /// rejoins).
    func offset(from start: Double, to end: Double, by offset: Double, ramp: Double) -> WorldPath {
        let count = max(8, Int(((end - start) / (10 * Double(WorldCoordinate.unitsPerMetre))).rounded()))
        var points: [WorldVector] = []
        for step in 0...count {
            let distance = start + (end - start) * Double(step) / Double(count)
            let edge = min(distance - start, end - distance)
            let t = min(1, max(0, edge / ramp))
            let smooth = t * t * (3 - 2 * t)
            points.append(point(at: distance) + tangent(at: distance).normal * (offset * smooth))
        }
        return WorldPath(points)
    }
}
