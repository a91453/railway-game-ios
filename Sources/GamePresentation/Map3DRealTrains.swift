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
    /// shape each sample is (rising), where its rails are, and whether a
    /// car there shows.
    struct Track: Sendable {
        let km: [Double]
        let points: [Map3DPoint]
        let shown: [Bool]
        /// From the first sample a car shows at to the last, if any.
        let shownKm: ClosedRange<Double>?

        init(km: [Double], points: [Map3DPoint], shown: [Bool]) {
            self.km = km
            self.points = points
            self.shown = shown
            shownKm = shown.firstIndex(of: true).flatMap { first in shown.lastIndex(of: true).map { km[first]...km[$0] } }
        }

        /// The rails `km` along the line, if this stretch has it and a car
        /// there shows.
        func point(atKm km: Double) -> Map3DPoint? {
            guard let first = self.km.first, let last = self.km.last, km >= first, km <= last else { return nil }
            var lo = 0, hi = self.km.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if self.km[mid] <= km { lo = mid } else { hi = mid }
            }
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
    /// How close to the player's track a car is not drawn, nor the real
    /// track laid, metres: there the player's track is the line, and the
    /// player's own trains run on it. The TRA demo's track, traced from
    /// another survey of the Yilan Line, lies up to 16 m from the
    /// timetables' shape of it, and none 16 to 32 m.
    static let playerClearance: Float = 16
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
    /// scene's edge).
    init(traffic: RealTrainTraffic, structures: RealRailStructures?, frame: RealWorldFrame, snapshot: RailwaySnapshot,
         builder: inout Map3DScene.Builder) {
        self.traffic = traffic
        formations = traffic.lines.map { Self.formation(system: $0.system, line: $0.line) }
        stripes = traffic.lines.map { Map3DColor.rgb(UInt32($0.color.red) << 16 | UInt32($0.color.green) << 8 | UInt32($0.color.blue)) }
        let player = PlayerTrack(snapshot.edges.map { $0.geometry.points.map(builder.point) })
        tracks = traffic.lines.map { line in
            Self.stretches(of: line, frame: frame, region: builder.region).compactMap { stretch in
                builder.realTrack(stretch, system: RealRailwayOperations.siteSystems[line.system] ?? line.system, structures: structures,
                                  frame: frame, clearOf: player)
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
            for line in lines {
                for (a, b) in zip(line, line.dropFirst()) {
                    let low = (x: min(a.x, b.x), z: min(a.z, b.z)), high = (x: max(a.x, b.x), z: max(a.z, b.z))
                    for column in Self.index(low.x)...Self.index(high.x) {
                        for row in Self.index(low.z)...Self.index(high.z) {
                            segments[Self.key(column, row), default: []].append((a, b))
                        }
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
                            if let point = track.point(atKm: km) { return point }
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
