import GameCore

/// Decision 339: the real timetables' trains (decision 304) on the 3D map
/// of a real-world game, on real track of their own.
///
/// Where they run is the 2D map's: ``RealTrainTraffic`` places each train
/// along its line's shape (``RealLineShape``) at a second of the game day,
/// from the same timetables, the High Speed Rail's day of trains and
/// Taiwan Railway's headways. The scene lays each line's shape where it
/// comes within its region, every ``spacing``, at the height of track along
/// it (``TrackRise``, decision 132) kept to the line's real bridges and
/// tunnels (``RealRailStructures``, decision 279): on viaducts over the
/// ground, out of sight in tunnels, and on the ground elsewhere. Each
/// frame, a train's cars are laid back from the place the timetable gives
/// along that track; a car in a tunnel, past the scene's edge or beside
/// the player's own track is not drawn.
///
/// The cars are decision 318's sets (``Map3DTrainSet``), each line's the
/// stock its trains are, as many cars as its trains have; within
/// ``Map3DTrainSet/reach(of:)`` of the eye a model, farther a box with a
/// band in the line's colour, as the player's trains. No label, follow or
/// ring: those stay the player's own trains' (decisions 314, 333, 334).
public struct Map3DRealTrains: Sendable {
    /// A train of a line: its set's key and how many cars.
    struct Formation: Hashable, Sendable {
        let key: String
        let cars: Int
    }

    /// A stretch of a line within the scene: how far along the line's
    /// shape each sample is (rising), where the rails a train runs on are
    /// there each way (``lanes``: the first for a train going up the
    /// line's km, the second down it; one and the same on single track),
    /// and whether a car there shows.
    struct Track: Sendable {
        let km: [Double]
        let lanes: [[Map3DPoint]]
        let shown: [[Bool]]
        /// From the first sample a car shows at to the last, if any.
        let shownKm: ClosedRange<Double>?

        init(km: [Double], lanes: [[Map3DPoint]], shown: [[Bool]]) {
            self.km = km
            self.lanes = lanes
            self.shown = shown
            let any = km.indices.map { index in shown.contains { $0[index] } }
            shownKm = any.firstIndex(of: true).flatMap { first in any.lastIndex(of: true).map { km[first]...km[$0] } }
        }

        /// One track both ways.
        init(km: [Double], points: [Map3DPoint], shown: [Bool]) {
            self.init(km: km, lanes: [points, points], shown: [shown, shown])
        }

        /// The rails `km` along the line a train going `way` (up the km
        /// at 0 or more) runs on, if this stretch has it and a car there
        /// shows.
        func point(atKm km: Double, way: Double = 1) -> Map3DPoint? {
            guard let first = self.km.first, let last = self.km.last, km >= first, km <= last else { return nil }
            var lo = 0, hi = self.km.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if self.km[mid] <= km { lo = mid } else { hi = mid }
            }
            let lane = way >= 0 ? 0 : 1
            let points = lanes[lane], shown = self.shown[lane]
            guard shown[lo], shown[hi] else { return nil }
            let span = self.km[hi] - self.km[lo]
            let share = Float(span > 0 ? (km - self.km[lo]) / span : 0)
            return points[lo] + (points[hi] - points[lo]) * share
        }
    }

    let traffic: RealTrainTraffic
    /// By line, as ``RealTrainTraffic/lines``.
    let tracks: [[Track]]
    let formations: [Formation]
    let stripes: [UInt32]

    /// How far apart the track's samples are, metres: ``TrackRise``'s.
    static let spacing = 8.0
    /// How far past the scene's region a line is laid, metres: a train
    /// coming into it shows whole.
    static let margin = 400.0
    /// How close to a line the player bought (decision 315) its real
    /// track is not laid, nor a car drawn, metres: there the player's
    /// track is the line, and the player's own trains run on it. Without
    /// the real tracks (``RealRailTracks``), how close to any of the
    /// player's track: the TRA demo's track, traced from another survey of
    /// the Yilan Line, lies up to 16 m from the timetables' shape of it,
    /// and none 16 to 32 m.
    static let playerClearance: Float = 16
    /// Decision 402: how close to the player's track a real track is not
    /// laid, nor a car drawn on it, metres: their beds would lie one on
    /// the other (``Map3DScene/Builder/bedTop``). The real line's other
    /// track, 4 m or more beside, is.
    static let overlap: Float = Map3DScene.Builder.bedTop
    /// Decision 402: how far from a line's shape its real tracks are
    /// looked for, metres, at most how far apart the tracks of one line
    /// are (a line beside it, farther, is another), and how nearly along
    /// the shape a track runs to be the line's (the cosine of the angle).
    static let laneReach: Float = 30
    static let laneSpread: Float = 12
    static let laneAlong: Float = 0.866
    /// Decision 402: the systems whose trains keep to the right, the
    /// metros and light rails (each of the site's `metro-network.json`
    /// routes runs on the right of its other way's); the TRA's, the High
    /// Speed Rail's and the forest railway's keep to the left.
    static let rightHand: Set<String> = ["mrt", "tymc", "ntdlrt", "ntalrt", "sanying", "krtc", "tmrt"]
    /// How far under the ground the track is in a tunnel, and over it on a
    /// viaduct, metres.
    static let tunnelDepth: Float = 3
    static let viaductHeight: Float = 4
    static let embankmentHeight: Float = 1.2
    /// A car, as the player's (``TrainCars/drawnCarLength``), in the
    /// line's km.
    static let carPitch = 0.020
    static let carLength = carPitch - Double(Map3DTrains.carGap) / 1_000

    /// Each line's trains (decision 339): as many cars as `Railway/`
    /// rail-3d's formations give its trains (`integration/formations.js`
    /// `baseFormation`), each the game's set for that stock, or the nearest
    /// set it has.
    static func formation(system: String, line: RealOperationLine) -> Formation {
        switch system {
        case "thsr":
            // The 700T: twelve cars.
            return Formation(key: "highSpeed", cars: 12)
        case "tra":
            // The diesel branches' DR1000 railcars, three on a weekday;
            // the rest the EMU800, eight cars, as most local trains
            // (`dr1000`, `commuter`).
            if Map3DScene.dieselBranches.contains(where: { line.name.hasPrefix($0) }) { return Formation(key: "dieselRailcar", cars: 3) }
            return Formation(key: "emu800", cars: 8)
        case "trtc":
            switch line.id {
            // The Wenhu and Circular lines' four cars (`wenhu`, `y100`).
            case "BR", "Y": return Formation(key: "wenhu", cars: 4)
            // The branch shuttles' three.
            case "R_XBT", "G_XBT": return Formation(key: "metroC381", cars: 3)
            default: return Formation(key: "metroC381", cars: 6)
            }
        case "krtc":
            if line.id == "C" { return Formation(key: "greenTram", cars: 2) }
            return Formation(key: "metroC381", cars: 3)
        case "tymc":
            // The commuter train's four (`airportunknown`).
            return Formation(key: "metroC381", cars: 4)
        case "tmrt":
            return Formation(key: "metroC381", cars: 2)
        case "sanying":
            return Formation(key: "wenhu", cars: 2)
        case "ntdlrt", "ntalrt":
            // Decision 331: the light rail as the green tram, two cars of
            // two sections each, about the five sections' 34 m.
            return Formation(key: "greenTram", cars: 2)
        default:
            // The Alishan Forest Railway's locomotive and five short
            // coaches, about 70 m: boxes, the game has no set.
            return Formation(key: "", cars: 3)
        }
    }

    /// The lines of `traffic` laid in the scene `builder` builds, clear of
    /// `snapshot`'s track (all of it: the real lines are laid past the
    /// scene's edge). Decision 402: with `railTracks`, each real track of
    /// their systems as it runs, at its height, but within ``overlap`` of
    /// the player's track or ``playerClearance`` of a line in `bought`
    /// (its system, as `traffic`'s lines name it, and shape); without,
    /// one track along each line's shape (decision 339).
    init(traffic: RealTrainTraffic, structures: RealRailStructures?, railTracks: RealRailTracks? = nil,
         bought: [(system: String, shape: [RealRailways.Coordinate])] = [], frame: RealWorldFrame, snapshot: RailwaySnapshot,
         builder: inout Map3DScene.Builder) {
        self.traffic = traffic
        formations = traffic.lines.map { Self.formation(system: $0.system, line: $0.line) }
        stripes = traffic.lines.map { Map3DColor.rgb(UInt32($0.color.red) << 16 | UInt32($0.color.green) << 8 | UInt32($0.color.blue)) }
        let player = PlayerTrack(snapshot.edges.map { $0.geometry.points.map(builder.point) })
        func site(_ system: String) -> String { RealRailwayOperations.siteSystems[system] ?? system }
        guard let railTracks else {
            tracks = traffic.lines.map { line in
                Self.stretches(of: line, frame: frame, region: builder.region).compactMap { stretch in
                    builder.realTrack(stretch, system: site(line.system), structures: structures, frame: frame, clearOf: player)
                }
            }
            return
        }
        var boughtTrack: [String: PlayerTrack] = [:]
        for line in bought {
            let points = line.shape.map { coordinate in
                let at = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
                return builder.point(x: at.x, y: at.y, height: 0)
            }
            boughtTrack[site(line.system), default: PlayerTrack([])].add(points)
        }
        let laid = builder.realTracks(railTracks, systems: Set(traffic.lines.map { site($0.system) }), frame: frame, clearOf: player,
                                      bought: boughtTrack)
        tracks = traffic.lines.map { line in
            let system = site(line.system)
            return Self.stretches(of: line, frame: frame, region: builder.region).compactMap { stretch in
                laid.track(along: stretch, system: system, builder: builder)
            }
        }
    }

    /// Decision 358: a real line is laid in windows of this many
    /// kilometres along it, each the same whatever the region asking for
    /// it, so chunks built apart (``Map3DStreaming``) meet as the whole
    /// scene's do; and its heights found over this much more of the line
    /// either side of a window, so a window's ends rise and fall as its
    /// neighbours' do.
    static let window = 4.0
    static let windowContext = 0.5

    /// A window of a line's shape: its points (world points, and how far
    /// along the shape each is), no closer than a centimetre, reaching
    /// ``windowContext`` past `core`, the kilometres it is laid over.
    struct Stretch {
        let points: [(point: WorldVector, km: Double)]
        let core: ClosedRange<Double>
    }

    /// The windows of `line`'s shape (``window``) with a point within
    /// ``margin`` of `region`, or next to one.
    static func stretches(of line: RealTrainTraffic.Line, frame: RealWorldFrame, region: WorldRegion) -> [Stretch] {
        let margin = Self.margin * Double(WorldCoordinate.unitsPerMetre)
        func near(_ p: WorldVector) -> Bool {
            p.x >= region.minX - margin && p.x <= region.maxX + margin && p.y >= region.minY - margin && p.y <= region.maxY + margin
        }
        let points = line.shape.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }
        let km = line.shape.cumulativeKm
        func window(_ index: Int) -> Int { Int((km[index] / Self.window).rounded(.down)) }
        // A point is wanted beside one that is near, so the line runs to
        // the margin's edge.
        var windows = Set<Int>()
        for index in points.indices where near(points[index]) {
            for neighbour in max(0, index - 1)...min(points.count - 1, index + 1) { windows.insert(window(neighbour)) }
        }
        return windows.sorted().compactMap { window in
            let core = Double(window) * Self.window...Double(window + 1) * Self.window
            let reach = (core.lowerBound - Self.windowContext)...(core.upperBound + Self.windowContext)
            var stretch: [(point: WorldVector, km: Double)] = []
            for index in points.indices {
                // The points within reach, and the one either side, so
                // the stretch spans it.
                let kept = reach.contains(km[index]) || (index + 1 < points.count && km[index] < reach.lowerBound && km[index + 1] >= reach.lowerBound)
                    || (index > 0 && km[index] > reach.upperBound && km[index - 1] <= reach.upperBound)
                guard kept else { continue }
                if stretch.last.map({ (points[index] - $0.point).length >= 0.64 }) ?? true { stretch.append((points[index], km[index])) }
            }
            return stretch.count > 1 ? Stretch(points: stretch, core: core) : nil
        }
    }

    /// Where the player's track runs, for what stays clear of it.
    struct PlayerTrack {
        static let cell: Float = 32
        var segments: [Int64: [(Map3DPoint, Map3DPoint)]] = [:]

        init(_ lines: [[Map3DPoint]]) {
            for line in lines { add(line) }
        }

        mutating func add(_ line: [Map3DPoint]) {
            for (a, b) in zip(line, line.dropFirst()) {
                let low = (x: min(a.x, b.x), z: min(a.z, b.z)), high = (x: max(a.x, b.x), z: max(a.z, b.z))
                for column in Self.index(low.x)...Self.index(high.x) {
                    for row in Self.index(low.z)...Self.index(high.z) {
                        segments[Self.key(column, row), default: []].append((a, b))
                    }
                }
            }
        }

        static func index(_ v: Float) -> Int { Int((v / cell).rounded(.down)) }
        static func key(_ column: Int, _ row: Int) -> Int64 { Int64(column) << 32 | Int64(UInt32(bitPattern: Int32(row))) }

        /// Whether scene point `p` is within `reach` of the track, seen
        /// from above (`reach` at most ``cell``).
        func isNear(_ p: Map3DPoint, within reach: Float) -> Bool {
            let column = Self.index(p.x), row = Self.index(p.z)
            for c in column - 1...column + 1 {
                for r in row - 1...row + 1 {
                    for (a, b) in segments[Self.key(c, r)] ?? [] {
                        let ax = b.x - a.x, az = b.z - a.z
                        let squared = ax * ax + az * az
                        let t = squared > 0 ? max(0, min(1, ((p.x - a.x) * ax + (p.z - a.z) * az) / squared)) : 0
                        let dx = a.x + ax * t - p.x, dz = a.z + az * t - p.z
                        if dx * dx + dz * dz < reach * reach { return true }
                    }
                }
            }
            return false
        }
    }

    // MARK: - Each frame

    /// The real trains at second `second` of the game day `day` seen from
    /// `eye`, added to `frame`: the models of `models` within reach, the
    /// rest boxes; at most ``RealTrainTraffic/mostDrawn`` trains.
    public func add(to frame: inout Map3DTrains.Frame, second: Double, day: RealServiceDay, dayBefore: RealServiceDay,
                    models: Map3DModelPack?, eye: Map3DPoint?) {
        var drawn = 0
        for (index, line) in traffic.lines.enumerated() where !tracks[index].isEmpty {
            let formation = formations[index], stripe = stripes[index]
            let hasModels = models?.models(forType: formation.key) != nil
            let reach = Map3DTrainSet.reach(of: formation.key)
            let ring = line.ringKm ?? line.shape.lengthKm
            let isRing = line.ringKm != nil
            for place in traffic.places(of: line, at: second, on: day, dayBefore: dayBefore) {
                guard drawn < RealTrainTraffic.mostDrawn else { return }
                let way: Double = RealTrainRun.way(from: place.km, to: place.towardKm, ringKm: isRing ? ring : nil) >= 0 ? 1 : -1
                let length = Double(formation.cars) * Self.carPitch
                // Its middle where the timetable has it; held at the line's
                // end, its front there.
                var front = place.km + way * length / 2
                if !isRing { front = min(max(front, 0), ring) }
                // Most are in a tunnel or off the scene: those, at once.
                let span = min(front, front - way * length)...max(front, front - way * length)
                guard isRing || tracks[index].contains(where: { $0.shownKm?.overlaps(span) ?? false }) else { continue }
                var shown = false
                for car in 0..<formation.cars {
                    func at(_ km: Double) -> Map3DPoint? {
                        var km = km
                        if isRing, ring > 0 { km = (km.truncatingRemainder(dividingBy: ring) + ring).truncatingRemainder(dividingBy: ring) }
                        for track in tracks[index] {
                            if let point = track.point(atKm: km, way: way) { return point }
                        }
                        return nil
                    }
                    let start = front - way * Double(car) * Self.carPitch
                    guard let a = at(start), let b = at(start - way * Self.carLength) else { continue }
                    let along = (a - b).length
                    guard along > 1 else { continue }
                    shown = true
                    let base = (a + b) * 0.5
                    let bed = Map3DPoint(0, 0.05 - Map3DScene.Builder.bedDrop, 0)
                    frame.shadows.addShadow(
                        inner: Map3DMesh.footprint(centre: base + bed, forward: a - b, length: along, width: Map3DTrains.carWidth),
                        outer: Map3DMesh.footprint(centre: base + bed, forward: a - b, length: along + 1, width: Map3DTrains.carWidth + 1),
                        darkness: 0.38)
                    if let models, hasModels, let eye, (base - eye).length < reach,
                       let model = models.modelIndex(forType: formation.key, carIndex: car, count: formation.cars) {
                        let turned = models.isTurned(forType: formation.key, carIndex: car, count: formation.cars)
                        frame.instances.append(Map3DTrains.instance(of: models.models[model], index: model, from: turned ? a : b, to: turned ? b : a,
                                                                    stripe: stripe))
                        continue
                    }
                    frame.boxes.addBox(base: base + Map3DPoint(0, 0.3, 0), forward: a - b, length: along, width: Map3DTrains.carWidth,
                                       height: Map3DTrains.carHeight - 0.3, top: Map3DTrains.roof, side: Map3DTrains.body)
                    frame.boxes.addBox(base: base + Map3DPoint(0, 1.0, 0), forward: a - b, length: along + 0.04,
                                       width: Map3DTrains.carWidth + 0.04, height: 0.45, top: stripe, side: stripe)
                }
                if shown { drawn += 1 }
            }
        }
    }
}

// MARK: - The real track

extension Map3DScene.Builder {
    /// Decision 339: the real line through `stretch` (world points and how
    /// far along the line each is), every ``Map3DRealTrains/spacing``
    /// metres at the height ``TrackRise`` gives it, kept to `system`'s
    /// structures; laid as track (its viaducts, its surface and nothing in
    /// its tunnels) but within ``Map3DRealTrains/playerClearance`` of
    /// `player`'s track. Returns where cars on it are drawn, or `nil` for
    /// a stretch too short to lay.
    mutating func realTrack(_ window: Map3DRealTrains.Stretch, system: String, structures: RealRailStructures?,
                            frame: RealWorldFrame, clearOf player: Map3DRealTrains.PlayerTrack) -> Map3DRealTrains.Track? {
        let stretch = window.points
        let path = WorldPath(stretch.map(\.point))
        guard path.points.count == stretch.count, path.length > 0 else { return nil }
        let carried = structures?.stretches(along: path, frame: frame, system: system) ?? []
        let rise = TrackRise(path: path, ground: { Double(ground(x: $0.x, y: $0.y)) * Self.metre }, water: { _ in false }, levels: [],
                             carried: carried)
        let spacing = Map3DRealTrains.spacing * Self.metre
        let sampled = rise?.distances ?? stride(from: 0, through: path.length, by: spacing).map { $0 } + [path.length]
        // How far along the line each sample is.
        var along: [Double] = []
        var segment = 0
        for distance in sampled {
            while segment + 1 < path.distances.count - 1, path.distances[segment + 1] < distance { segment += 1 }
            let a = path.distances[segment], b = path.distances[segment + 1]
            let share = b > a ? min(max((distance - a) / (b - a), 0), 1) : 0
            along.append(stretch[segment].km + (stretch[segment + 1].km - stretch[segment].km) * share)
        }
        // Decision 358: laid over the window's core, from the last sample
        // at or before its start to the first at or after its end, so the
        // windows either side meet it.
        let first = along.lastIndex { $0 <= window.core.lowerBound } ?? 0
        let last = along.firstIndex { $0 >= window.core.upperBound } ?? (along.count - 1)
        guard first < last else { return nil }
        let laid = first...last
        let distances = Array(sampled[laid])
        var km: [Double] = [], points: [Map3DPoint] = [], kinds: [TrackSectionKind] = [], shown: [Bool] = []
        for (index, distance) in zip(laid, distances) {
            km.append(along[index])
            let at = path.point(at: distance)
            let flat = point(x: at.x, y: at.y, height: 0)
            let drawn = drawnGround(x: flat.x, z: flat.z)
            let height = rise.map { Float($0.heights[index] / Self.metre) } ?? drawn
            let under = rise.map { Float($0.ground[index] / Self.metre) } ?? drawn
            let inTunnel = height < under - Map3DRealTrains.tunnelDepth
                || carried.contains { $0.kind == .tunnel && $0.range.contains(distance) && height < under }
            let rail = Map3DPoint(flat.x, max(height, drawn), flat.z) + Self.lifted
            let lift = max(height, drawn) - drawn
            kinds.append(inTunnel ? .tunnel : lift > Map3DRealTrains.viaductHeight ? .viaduct
                         : lift > Map3DRealTrains.embankmentHeight ? .embankment : .surface)
            points.append(rail)
            shown.append(!inTunnel && !player.isNear(rail, within: Map3DRealTrains.playerClearance))
        }
        // Laid in runs of one kind, every other sample, where a car shows.
        var run: [Int] = []
        func lay() {
            defer { run = [] }
            guard run.count > 1, let first = run.first else { return }
            let kind = kinds[first]
            guard kind != .tunnel else { return }
            var kept = stride(from: 0, to: run.count, by: 2).map { points[run[$0]] }
            if run.count % 2 == 0, let last = run.last { kept.append(points[last]) }
            for piece in Self.pieces(of: kept) { addTrackPiece(piece, kind: kind) }
            let cell = Double(Land.cellLength)
            for index in run {
                let at = path.point(at: distances[index])
                realTrackCells.insert(Map3DScene.ChunkKey(column: Int((at.x / cell).rounded(.down)), row: Int((at.y / cell).rounded(.down))))
            }
        }
        for index in distances.indices {
            if let last = run.last, !shown[index] || kinds[index] != kinds[last] {
                // A run ends where the next begins, so they meet.
                if shown[index] { run.append(index) }
                lay()
            }
            if shown[index] { run.append(index) }
        }
        lay()
        return Map3DRealTrains.Track(km: km, points: points, shown: shown)
    }
}

// MARK: - Decision 402: the real tracks as they run

extension Map3DRealTrains {
    /// The real tracks laid in a scene, as segments between their samples,
    /// by system: where a line's trains find the track they run on.
    struct Laid {
        static let cell: Float = 48

        struct Segment {
            let a: Map3DPoint
            let b: Map3DPoint
            /// Whether a car shows on it: out of a tunnel, clear of the
            /// player's track.
            let shown: Bool
            /// Which track it is of (``RealRailTracks/tracks``).
            let track: Int
        }

        var segments: [String: [Int64: [Segment]]] = [:]

        mutating func add(_ segment: Segment, system: String) {
            let low = (x: min(segment.a.x, segment.b.x), z: min(segment.a.z, segment.b.z))
            let high = (x: max(segment.a.x, segment.b.x), z: max(segment.a.z, segment.b.z))
            for column in Self.index(low.x)...Self.index(high.x) {
                for row in Self.index(low.z)...Self.index(high.z) {
                    segments[system, default: [:]][PlayerTrack.key(column, row), default: []].append(segment)
                }
            }
        }

        static func index(_ v: Float) -> Int { Int((v / cell).rounded(.down)) }

        /// The rails a train of `system` at scene point `p` (on the
        /// ground), its line running along `along` (across the ground),
        /// runs on each way, and whether a car there shows: of the tracks
        /// of `system` within ``Map3DRealTrains/laneReach`` running along
        /// it, those within ``Map3DRealTrains/laneSpread`` of the nearest
        /// across it are the line's; a train going along takes the
        /// nearest the middle on the side its system keeps to
        /// (``Map3DRealTrains/rightHand``), the other way the other side's;
        /// on single track, both the one. `nil` with no track there.
        func lanes(at p: Map3DPoint, along: Map3DPoint, system: String) -> [(point: Map3DPoint, shown: Bool)]? {
            guard let cells = segments[system] else { return nil }
            let length = (along.x * along.x + along.z * along.z).squareRoot()
            guard length > 0 else { return nil }
            let tx = along.x / length, tz = along.z / length
            // The nearest point of each track: how far across (left of
            // `along` positive; the scene's z is south), how far off.
            var nearest: [Int: (across: Float, off: Float, point: Map3DPoint, shown: Bool)] = [:]
            let column = Self.index(p.x), row = Self.index(p.z)
            for c in column - 1...column + 1 {
                for r in row - 1...row + 1 {
                    for segment in cells[PlayerTrack.key(c, r)] ?? [] {
                        let dx = segment.b.x - segment.a.x, dz = segment.b.z - segment.a.z
                        let squared = dx * dx + dz * dz
                        guard squared > 0, abs(dx * tx + dz * tz) >= Map3DRealTrains.laneAlong * squared.squareRoot() else { continue }
                        let t = max(0, min(1, ((p.x - segment.a.x) * dx + (p.z - segment.a.z) * dz) / squared))
                        let q = segment.a + (segment.b - segment.a) * t
                        let ox = q.x - p.x, oz = q.z - p.z
                        let off = (ox * ox + oz * oz).squareRoot()
                        guard off <= Map3DRealTrains.laneReach else { continue }
                        if let known = nearest[segment.track], known.off <= off { continue }
                        nearest[segment.track] = (-(tx * oz - tz * ox), off, q, segment.shown)
                    }
                }
            }
            // Ties by track, so the choice is the same whatever order the
            // cells hold them in.
            let found = nearest.sorted { $0.value.off != $1.value.off ? $0.value.off < $1.value.off : $0.key < $1.key }.map(\.value)
            guard let closest = found.first else { return nil }
            // The line's tracks, one each (two ways meeting at a node are
            // one track there).
            var line: [(across: Float, off: Float, point: Map3DPoint, shown: Bool)] = []
            for candidate in found where abs(candidate.across - closest.across) <= Map3DRealTrains.laneSpread {
                if !line.contains(where: { abs($0.across - candidate.across) < 1.5 }) { line.append(candidate) }
            }
            let middle = (line.map(\.across).min()! + line.map(\.across).max()!) / 2
            let keepsRight = Map3DRealTrains.rightHand.contains(system)
            func lane(leftward: Bool) -> (point: Map3DPoint, shown: Bool) {
                let side = line.filter { leftward ? $0.across > middle : $0.across < middle }
                let pick = (side.isEmpty ? line : side).min { abs($0.across - middle) < abs($1.across - middle) }!
                return (pick.point, pick.shown)
            }
            // Going along, a train keeping to the left runs left of the
            // middle; going back, right of it (left of its own way).
            return [lane(leftward: !keepsRight), lane(leftward: keepsRight)]
        }

        /// `window` of a line of `system` (``Map3DRealTrains/stretches``),
        /// every ``Map3DRealTrains/spacing`` metres of its core, on the
        /// tracks its trains run on each way (``lanes``); `nil` for a
        /// window too short, or with none of `system`'s tracks.
        func track(along window: Map3DRealTrains.Stretch, system: String, builder: Map3DScene.Builder) -> Map3DRealTrains.Track? {
            guard segments[system] != nil else { return nil }
            let stretch = window.points
            let path = WorldPath(stretch.map(\.point))
            guard path.points.count == stretch.count, path.length > 0 else { return nil }
            let metre = Map3DScene.Builder.metre
            let sampled = stride(from: 0, through: path.length, by: Map3DRealTrains.spacing * metre).map { $0 } + [path.length]
            var along: [Double] = []
            var segment = 0
            for distance in sampled {
                while segment + 1 < path.distances.count - 1, path.distances[segment + 1] < distance { segment += 1 }
                let a = path.distances[segment], b = path.distances[segment + 1]
                let share = b > a ? min(max((distance - a) / (b - a), 0), 1) : 0
                along.append(stretch[segment].km + (stretch[segment + 1].km - stretch[segment].km) * share)
            }
            let first = along.lastIndex { $0 <= window.core.lowerBound } ?? 0
            let last = along.firstIndex { $0 >= window.core.upperBound } ?? (along.count - 1)
            guard first < last else { return nil }
            var km: [Double] = [], lanes: [[Map3DPoint]] = [[], []], shown: [[Bool]] = [[], []]
            for index in first...last {
                let at = path.point(at: sampled[index])
                let ahead = path.point(at: min(sampled[index] + metre, path.length)), behind = path.point(at: max(sampled[index] - metre, 0))
                let p = builder.point(x: at.x, y: at.y, height: 0)
                let direction = builder.point(x: ahead.x, y: ahead.y, height: 0) - builder.point(x: behind.x, y: behind.y, height: 0)
                km.append(along[index])
                let found = self.lanes(at: p, along: direction, system: system)
                for lane in 0..<2 {
                    lanes[lane].append(found?[lane].point ?? p)
                    shown[lane].append(found?[lane].shown ?? false)
                }
            }
            return Map3DRealTrains.Track(km: km, lanes: lanes, shown: shown)
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 402: each track of `tracks` of `systems` within
    /// ``Map3DRealTrains/margin`` of the region, every
    /// ``Map3DRealTrains/spacing`` metres (and at each of its points) at
    /// its height over the ground: on its viaducts and banks, on the
    /// ground, nothing in its tunnels; laid in windows of
    /// ``Map3DRealTrains/window`` km of its own length, the same whatever
    /// the region (decision 358). Not where it lies within
    /// ``Map3DRealTrains/overlap`` of `player`'s track, nor within
    /// ``Map3DRealTrains/playerClearance`` of a line of its system the
    /// player bought (`bought`). Returns where they are laid, for the
    /// trains.
    mutating func realTracks(_ tracks: RealRailTracks, systems: Set<String>, frame: RealWorldFrame,
                             clearOf player: Map3DRealTrains.PlayerTrack,
                             bought: [String: Map3DRealTrains.PlayerTrack] = [:]) -> Map3DRealTrains.Laid {
        var laid = Map3DRealTrains.Laid()
        let margin = Map3DRealTrains.margin * Self.metre
        let near = (minX: region.minX - margin, minY: region.minY - margin, maxX: region.maxX + margin, maxY: region.maxY + margin)
        let windowLength = Map3DRealTrains.window * 1_000
        for (number, track) in tracks.tracks.enumerated() where systems.contains(track.system) {
            let world = track.points.map { frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude) }
            guard world.contains(where: { $0.x >= near.minX - windowLength * Self.metre && $0.x <= near.maxX + windowLength * Self.metre
                && $0.y >= near.minY - windowLength * Self.metre && $0.y <= near.maxY + windowLength * Self.metre }) else { continue }
            // Its samples: each point, and every 8 m between; how far
            // along it each is, metres.
            var samples: [(x: Double, y: Double, height: Double, along: Double)] = []
            var travelled = 0.0
            for index in world.indices {
                guard index > 0 else {
                    samples.append((world[0].x, world[0].y, track.heights[0], 0))
                    continue
                }
                let a = world[index - 1], b = world[index]
                let length = ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() / Self.metre
                let steps = max(1, Int((length / Map3DRealTrains.spacing).rounded(.up)))
                for step in 1...steps {
                    let share = Double(step) / Double(steps)
                    samples.append((a.x + (b.x - a.x) * share, a.y + (b.y - a.y) * share,
                                    track.heights[index - 1] + (track.heights[index] - track.heights[index - 1]) * share, travelled + length * share))
                }
                travelled += length
            }
            // The windows with a sample near the region, each laid to the
            // next's first sample, so they meet.
            func window(_ sample: Int) -> Int { Int((samples[sample].along / windowLength).rounded(.down)) }
            var wanted = Set<Int>()
            for index in samples.indices
            where samples[index].x >= near.minX && samples[index].x <= near.maxX && samples[index].y >= near.minY && samples[index].y <= near.maxY {
                wanted.insert(window(index))
            }
            guard !wanted.isEmpty else { continue }
            let siteBought = bought[track.system]
            var points: [Map3DPoint?] = Array(repeating: nil, count: samples.count)
            var kinds: [TrackSectionKind] = Array(repeating: .tunnel, count: samples.count)
            var shown: [Bool] = Array(repeating: false, count: samples.count)
            var first = 0
            while first < samples.count {
                var end = first
                while end + 1 < samples.count, window(end + 1) == window(first) { end += 1 }
                let range = first...min(end + 1, samples.count - 1)
                defer { first = end + 1 }
                guard wanted.contains(window(first)) else { continue }
                for index in range where points[index] == nil {
                    let sample = samples[index]
                    let flat = point(x: sample.x, y: sample.y, height: 0)
                    let drawn = drawnGround(x: flat.x, z: flat.z)
                    let height = Float(sample.height)
                    let inTunnel = track.kind == .tunnel || height < -Map3DRealTrains.tunnelDepth
                    let rail = Map3DPoint(flat.x, drawn + (inTunnel ? height : max(height, 0)), flat.z) + Self.lifted
                    points[index] = rail
                    kinds[index] = inTunnel ? .tunnel : height > Map3DRealTrains.viaductHeight ? .viaduct
                        : height > Map3DRealTrains.embankmentHeight ? .embankment : .surface
                    shown[index] = !inTunnel && !player.isNear(rail, within: Map3DRealTrains.overlap)
                        && !(siteBought?.isNear(rail, within: Map3DRealTrains.playerClearance) ?? false)
                }
                for index in range.dropFirst() {
                    guard let a = points[index - 1], let b = points[index] else { continue }
                    laid.add(.init(a: a, b: b, shown: shown[index - 1] && shown[index], track: number), system: track.system)
                }
                layRealRun(range, points: points, kinds: kinds, shown: shown, cells: samples.map { ($0.x, $0.y) })
            }
        }
        return laid
    }

    /// Decision 402: the samples `range` of a real track laid as track in
    /// runs of one kind, every other sample, where a car shows; the city
    /// grid's cells it crosses kept clear of the seeded city.
    private mutating func layRealRun(_ range: ClosedRange<Int>, points: [Map3DPoint?], kinds: [TrackSectionKind], shown: [Bool],
                                     cells: [(x: Double, y: Double)]) {
        var run: [Int] = []
        func lay() {
            defer { run = [] }
            guard run.count > 1, let first = run.first else { return }
            let kind = kinds[first]
            guard kind != .tunnel else { return }
            var kept = stride(from: 0, to: run.count, by: 2).compactMap { points[run[$0]] }
            if run.count % 2 == 0, let last = run.last, let point = points[last] { kept.append(point) }
            for piece in Self.pieces(of: kept) { addTrackPiece(piece, kind: kind) }
            let cell = Double(Land.cellLength)
            for index in run {
                realTrackCells.insert(Map3DScene.ChunkKey(column: Int((cells[index].x / cell).rounded(.down)),
                                                          row: Int((cells[index].y / cell).rounded(.down))))
            }
        }
        for index in range {
            if let last = run.last, !shown[index] || kinds[index] != kinds[last] {
                if shown[index] { run.append(index) }
                lay()
            }
            if shown[index] { run.append(index) }
        }
        lay()
    }
}
