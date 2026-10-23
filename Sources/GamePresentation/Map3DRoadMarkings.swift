import GameCore

// Decision 355: the paint on the 3D map's roads and the small things beside
// them. Where three or more arms of two-way main roads (those with a yellow
// centre line, decision 241) meet, each arm gets a zebra crossing, a stop
// line across its incoming lanes, lane arrows and a traffic signal at its
// kerb; the centre line stops where the crossing starts. Along the main
// roads, now and then a bus stop and a vending machine.
//
// After this repository's 3D city view (MIT, decision 152):
// `Web/CityView/tools/pipeline/markings.mjs` (junctions where three or more
// road ends meet, zebra bars 0.45 m at a 0.9 m pitch, the stop line before
// the bars across the incoming half, one signal an approach at the kerb a
// few metres before the junction) and `Web/CityView/src/world/decals.js`
// (arrows 1.7 × 5 m). The city view reads OSM's crossings, signals and lane
// tags; the base map here has none, so everything is placed by the roads'
// classes alone. Taiwan keeps right.

/// What the paint and the signals of a set of roads are: worked out from
/// the roads alone, the same every time.
struct Map3DRoadMarkings {
    enum Kind: Equatable {
        case crosswalk
        case stopLine
        /// Lane arrows: through, or through and left.
        case arrow(left: Bool)
    }

    /// One painted rectangle on a road: its middle, the way the traffic
    /// reading it goes (a unit vector, toward the junction), how long it
    /// is that way and how wide across.
    struct Mark {
        let kind: Kind
        let centre: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let length: Double
        let width: Double
    }

    /// A signal at an approach's kerb: its foot, the way the traffic it
    /// faces goes, and whether it shows green (the main road) or red.
    struct Signal {
        let foot: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let go: Bool
    }

    /// How deep a zebra crossing is along the road, how far its bars stand
    /// back from the crossing road's kerb, and the stop line's gap before
    /// it and its own depth.
    static let crosswalkDepth = 3.6
    static let kerbGap = 0.6
    static let stopGap = 2.0
    static let stopDepth = 0.4
    /// A lane arrow's size, and its gap behind the stop line.
    static let arrowLength = 5.0
    static let arrowWidth = 1.7
    static let arrowGap = 3.0

    var marks: [Mark] = []
    var signals: [Signal] = []
    /// The junctions marked.
    var junctions: [Map3DBaseMap.Point] = []
    /// Per road (by index), the stretches of its length (metres from its
    /// first point) where its centre line is left out.
    var cuts: [Int: [ClosedRange<Double>]] = [:]

    /// One way out of a junction along a road.
    struct Arm {
        let road: Int
        let kind: Map3DBaseMap.RoadKind
        /// From the junction outward.
        let points: [Map3DBaseMap.Point]
        /// Where the junction is along the road, and which way out.
        let at: Double
        let forward: Bool

        var half: Double { Double(kind.width(ramp: false)) / 2 }
        var length: Double { zip(points, points.dropFirst()).reduce(0) { $0 + Map3DRoadMarkings.distance($1.0, $1.1) } }

        /// The point `d` metres out and the way out there.
        func place(_ d: Double) -> (point: Map3DBaseMap.Point, out: Map3DBaseMap.Point)? {
            var left = d
            for (a, b) in zip(points, points.dropFirst()) {
                let length = Map3DRoadMarkings.distance(a, b)
                guard length > 1e-6 else { continue }
                let out = Map3DBaseMap.Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length)
                if left <= length { return (Map3DBaseMap.Point(x: a.x + out.x * left, z: a.z + out.z * left), out) }
                left -= length
            }
            return nil
        }
    }

    init() {}

    init(_ roads: [Map3DBaseMap.Road]) {
        // Every point of a marked road, by its half metre (as
        // Builder.junctions(of:) keys them).
        var at: [Int64: (point: Map3DBaseMap.Point, entries: [(road: Int, index: Int)])] = [:]
        for (number, road) in roads.enumerated() where Map3DScene.Builder.hasCentreLine(road) && road.points.count >= 2 {
            var seen = Set<Int64>()
            for (index, point) in road.points.enumerated() {
                let key = Self.key(point)
                guard seen.insert(key).inserted else { continue }
                at[key, default: (point, [])].entries.append((number, index))
            }
        }
        // The roads' lengths up to each point.
        var along: [Int: [Double]] = [:]
        func lengths(_ road: Int) -> [Double] {
            if let known = along[road] { return known }
            var sums = [0.0]
            for (a, b) in zip(roads[road].points, roads[road].points.dropFirst()) { sums.append(sums.last! + Self.distance(a, b)) }
            along[road] = sums
            return sums
        }
        for key in at.keys.sorted() {
            guard let (point, entries) = at[key].map({ ($0.point, $0.entries) }), entries.count >= 2,
                  entries.contains(where: { Self.inside(point, roads[$0.road].bounds) }) else { continue }
            var arms: [Arm] = []
            for (road, index) in entries {
                let points = roads[road].points, sums = lengths(road)
                for forward in [true, false] {
                    let way = forward ? Array(points[index...]) : Array(points[...index].reversed())
                    guard way.count >= 2 else { continue }
                    let arm = Arm(road: road, kind: roads[road].kind, points: way, at: sums[index], forward: forward)
                    // The same road from two tiles: one arm.
                    guard let out = arm.place(min(6, arm.length))?.out,
                          !arms.contains(where: { other in other.place(min(6, other.length)).map { Self.dot($0.out, out) > 0.98 } ?? false })
                    else { continue }
                    arms.append(arm)
                }
            }
            guard arms.count >= 3 else { continue }
            junctions.append(point)
            add(arms)
        }
    }

    private mutating func add(_ arms: [Arm]) {
        let outs = arms.map { $0.place(min(6, $0.length))?.out ?? Map3DBaseMap.Point(x: 1, z: 0) }
        // The main road: the widest arm (the first of the widest); its way
        // and the opposite show green.
        let main = arms.indices.max { arms[$0].half < arms[$1].half || (arms[$0].half == arms[$1].half && $0 > $1) } ?? 0
        for (number, arm) in arms.enumerated() {
            // Clear of the crossing roads and their pavements, more where
            // they cross at a slant.
            var clear = 0.0
            for (other, crossing) in arms.enumerated() where other != number {
                let sine = max(0.5, abs(outs[number].x * outs[other].z - outs[number].z * outs[other].x))
                let reach = crossing.half + Double(Map3DScene.Builder.sidewalk(of: crossing.kind))
                // An arm straight on (the same road beyond) is not crossed.
                if Self.dot(outs[number], outs[other]) < -0.9 { continue }
                clear = max(clear, reach / sine)
            }
            let crosswalk = clear + Self.kerbGap + Self.crosswalkDepth / 2
            let stop = crosswalk + Self.crosswalkDepth / 2 + Self.stopGap + Self.stopDepth / 2
            let arrow = stop + Self.stopDepth / 2 + Self.arrowGap + Self.arrowLength / 2
            let length = arm.length
            // The centre line stops where the crossing starts.
            let cut = min(length, crosswalk + Self.crosswalkDepth / 2)
            cuts[arm.road, default: []].append(arm.forward ? arm.at...(arm.at + cut) : (arm.at - cut)...arm.at)
            // Room for the crossing and the stop line before the arm ends
            // (at its next junction, or the map's edge).
            guard length >= stop + Self.stopDepth + 8, let zebra = arm.place(crosswalk), let line = arm.place(stop) else { continue }
            let half = arm.half
            // The traffic coming in goes back along the arm; its right
            // (Taiwan keeps right) is the right of that.
            func toward(_ out: Map3DBaseMap.Point) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: -out.x, z: -out.z) }
            func right(_ way: Map3DBaseMap.Point) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: -way.z, z: way.x) }
            func moved(_ p: Map3DBaseMap.Point, _ way: Map3DBaseMap.Point, _ by: Double) -> Map3DBaseMap.Point {
                Map3DBaseMap.Point(x: p.x + way.x * by, z: p.z + way.z * by)
            }
            marks.append(Mark(kind: .crosswalk, centre: zebra.point, along: toward(zebra.out), length: Self.crosswalkDepth, width: 2 * half))
            let way = toward(line.out)
            marks.append(Mark(kind: .stopLine, centre: moved(line.point, right(way), half / 2), along: way, length: Self.stopDepth,
                              width: half - 0.3))
            if length >= arrow + Self.arrowLength / 2 + 3, let place = arm.place(arrow) {
                let way = toward(place.out)
                // Two lanes each way on a road this wide, the inner one
                // through and left.
                let lanes = half >= 5 ? 2 : 1, lane = half / Double(lanes)
                for index in 0..<lanes {
                    marks.append(Mark(kind: .arrow(left: lanes > 1 && index == 0), centre: moved(place.point, right(way), (Double(index) + 0.5) * lane),
                                      along: way, length: Self.arrowLength, width: Self.arrowWidth))
                }
            }
            // The signal at the kerb by the stop line, on the pavement.
            let kerb = half + max(0.5, min(1, Double(Map3DScene.Builder.sidewalk(of: arm.kind)) * 0.3))
            signals.append(Signal(foot: moved(line.point, right(way), kerb), along: way, go: abs(Self.dot(outs[number], outs[main])) >= 0.7))
        }
    }

    /// `road`'s centre line (road number `number`), less the stretches cut
    /// at its junctions: the pieces left.
    func centreLines(of road: Map3DBaseMap.Road, number: Int) -> [[Map3DBaseMap.Point]] {
        guard let cut = cuts[number], !cut.isEmpty else { return [road.points] }
        var pieces: [[Map3DBaseMap.Point]] = [], piece: [Map3DBaseMap.Point] = []
        func isCut(_ d: Double) -> Bool { cut.contains { $0.contains(d) } }
        var travelled = 0.0
        for (a, b) in zip(road.points, road.points.dropFirst()) {
            let length = Self.distance(a, b)
            // Where the stretch's cuts begin and end along this segment.
            var stops = [0.0, length]
            for range in cut {
                for edge in [range.lowerBound, range.upperBound] where edge > travelled && edge < travelled + length { stops.append(edge - travelled) }
            }
            stops.sort()
            for (from, to) in zip(stops, stops.dropFirst()) where to - from > 1e-6 {
                func point(_ d: Double) -> Map3DBaseMap.Point {
                    let t = length > 0 ? d / length : 0
                    return Map3DBaseMap.Point(x: a.x + (b.x - a.x) * t, z: a.z + (b.z - a.z) * t)
                }
                if isCut(travelled + (from + to) / 2) {
                    if piece.count >= 2 { pieces.append(piece) }
                    piece = []
                } else {
                    if piece.isEmpty { piece.append(point(from)) }
                    piece.append(point(to))
                }
            }
            travelled += length
        }
        if piece.count >= 2 { pieces.append(piece) }
        return pieces
    }

    static func key(_ point: Map3DBaseMap.Point) -> Int64 {
        Int64((point.x * 2).rounded()) << 32 ^ Int64((point.z * 2).rounded()) & 0xFFFF_FFFF
    }

    static func distance(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> Double {
        ((b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z)).squareRoot()
    }

    static func dot(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> Double { a.x * b.x + a.z * b.z }

    static func inside(_ p: Map3DBaseMap.Point, _ bounds: Map3DBaseMap.Bounds) -> Bool {
        p.x >= bounds.minX && p.x < bounds.maxX && p.z >= bounds.minZ && p.z < bounds.maxZ
    }
}

extension Map3DScene.Builder {
    /// Decision 355: `markings` painted on the roads, near detail only,
    /// over every road (with the centre lines, which they never meet).
    mutating func addRoadMarkings(_ markings: Map3DRoadMarkings) {
        let kept = target
        target = .near
        defer { target = kept }
        for mark in markings.marks {
            switch mark.kind {
            case .crosswalk:
                // As many bars as fit across, a half gap at each kerb.
                addMark(mark, colour: Map3DPalette.road(.primary), layer: Float(Map3DSurface.crosswalk.rawValue),
                        u: (0, max(1, (mark.width / 0.9).rounded())), v: (0, 1))
            case .stopLine:
                addMark(mark, colour: Self.paint, layer: Map3DVertex.plain, u: (0, 1), v: (0, 1))
            case .arrow(let left):
                addMark(mark, colour: Map3DPalette.road(.primary), layer: Float(Map3DSurface.laneArrows.rawValue),
                        u: left ? (0.5, 1) : (0, 0.5), v: (0, 1))
            }
        }
    }

    /// The road paint's white, a little warm.
    static let paint = Map3DColor.rgb(0xEEEEE8)

    /// One mark laid on the drawn ground at the centre line's height, cut
    /// at the ground's grid lines and diagonals (as ``addArea`` cuts) so
    /// it never sinks into it: `u` across it left to right as its traffic
    /// sees it, `v` from its far end back.
    private mutating func addMark(_ mark: Map3DRoadMarkings.Mark, colour: UInt32, layer: Float, u: (Double, Double), v: (Double, Double)) {
        let along = mark.along, right = Map3DBaseMap.Point(x: -along.z, z: along.x)
        let halfLength = mark.length / 2, halfWidth = mark.width / 2
        let corners = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { a, b in
            Map3DBaseMap.Point(x: mark.centre.x + right.x * a * halfWidth + along.x * b * halfLength,
                               z: mark.centre.z + right.z * a * halfWidth + along.z * b * halfLength)
        }
        func texture(_ p: Map3DBaseMap.Point) -> (Float, Float) {
            let dx = p.x - mark.centre.x, dz = p.z - mark.centre.z
            let across = (dx * right.x + dz * right.z) / mark.width + 0.5
            let forth = (dx * along.x + dz * along.z) / mark.length + 0.5
            return (Float(u.0 + (u.1 - u.0) * across), Float(v.0 + (v.1 - v.0) * (1 - forth)))
        }
        // Decision 375: none where the road gives way to a trench.
        guard !givesWay(at: mark.centre, along: (mark.along.x, mark.along.z)) else { return }
        let lift = Self.centreLineLift
        for row in gridCell(corners.map(\.z).min()!, origin: originY)...gridCell(corners.map(\.z).max()!, origin: originY) {
            let top = gridLine(row, origin: originY), bottom = gridLine(row + 1, origin: originY)
            for column in gridCell(corners.map(\.x).min()!, origin: originX)...gridCell(corners.map(\.x).max()!, origin: originX) {
                let west = gridLine(column, origin: originX), east = gridLine(column + 1, origin: originX)
                for side in [1.0, -1.0] {
                    let piece = Self.clipRings([corners], by: [{ $0.z - top }, { bottom - $0.z }, { $0.x - west }, { east - $0.x },
                                                                { side * (($0.z - top) - ($0.x - west)) }])
                    guard let ring = piece.first, ring.count >= 3 else { continue }
                    let points = ring.map { p -> Map3DVertex in
                        let x = Float(p.x), z = Float(p.z), (tu, tv) = texture(p)
                        return Map3DVertex(Map3DPoint(x, drawnGround(x: x, z: z) + lift, z), normal: .up, color: colour, u: tu, v: tv, layer: layer)
                    }
                    let middle = Map3DPoint(Float((west + east) / 2), 0, Float((top + bottom) / 2))
                    mesh(at: middle) { mesh in
                        for index in 1..<(points.count - 1) {
                            var triangle = [points[0], points[index], points[index + 1]]
                            guard var normal = (triangle[1].position - triangle[0].position).cross(triangle[2].position - triangle[0].position).normalized
                            else { continue }
                            if normal.y < 0 {
                                triangle.swapAt(1, 2)
                                normal = normal * -1
                            }
                            mesh.appendTriangle(triangle.map { vertex in
                                var faced = vertex
                                (faced.nx, faced.ny, faced.nz) = (normal.x, normal.y, normal.z)
                                return faced
                            })
                        }
                    }
                }
            }
        }
    }

    /// Decision 355: the signals of `markings`, and along `roads` a bus
    /// stop now and then with a vending machine beside some; each clears
    /// the trees and lights where it stands.
    mutating func addStreetStops(_ roads: [Map3DBaseMap.Road], markings: Map3DRoadMarkings) {
        for signal in markings.signals {
            guard let model = Self.propModels[signal.go ? .signalGo : .signalStop] else { continue }
            place(model, at: signal.foot, forward: signal.along, clearing: 1.5, tint: Map3DColor.rgb(0xFFFFFF))
        }
        let east = originX / Double(WorldCoordinate.unitsPerMetre), south = originY / Double(WorldCoordinate.unitsPerMetre)
        func nearJunction(_ p: Map3DBaseMap.Point) -> Bool {
            markings.junctions.contains { Map3DRoadMarkings.distance($0, p) < Self.stopClearOfJunctions }
        }
        for road in roads where !road.isRamp && road.points.count >= 2 && Self.stopSpacing(road.kind) != nil {
            let spacing = Self.stopSpacing(road.kind)!, width = Double(road.kind.width(ramp: false)), pavement = Double(Self.sidewalk(of: road.kind))
            let start = road.points[0]
            let phase = Double(map3DRandom(Int32(truncatingIfNeeded: Int((start.x + east).rounded())),
                                           Int32(truncatingIfNeeded: Int((start.z + south).rounded())), salt: 355))
            var travelled = 0.0
            for (a, b) in zip(road.points, road.points.dropFirst()) {
                let length = Map3DRoadMarkings.distance(a, b)
                defer { travelled += length }
                guard length > 0.01 else { continue }
                let along = Map3DBaseMap.Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length)
                let left = Map3DBaseMap.Point(x: along.z, z: -along.x)
                var spot = ((travelled - phase * spacing) / spacing).rounded(.up) * spacing + phase * spacing
                while spot < travelled + length {
                    defer { spot += spacing }
                    let t = spot - travelled
                    let centre = Map3DBaseMap.Point(x: a.x + along.x * t, z: a.z + along.z * t)
                    guard Map3DRoadMarkings.inside(centre, road.bounds), !nearJunction(centre) else { continue }
                    let side: Double = Int((spot / spacing).rounded()) % 2 == 0 ? 1 : -1
                    // Facing the road: its left toward it.
                    let forward = side > 0 ? Map3DBaseMap.Point(x: -along.x, z: -along.z) : along
                    func out(_ by: Double, ahead: Double = 0) -> Map3DBaseMap.Point {
                        Map3DBaseMap.Point(x: centre.x + left.x * by * side + along.x * ahead, z: centre.z + left.z * by * side + along.z * ahead)
                    }
                    let seed = (Int32(truncatingIfNeeded: Int(((centre.x + east) * 2).rounded())), Int32(truncatingIfNeeded: Int(((centre.z + south) * 2).rounded())))
                    if pavement >= 2.5, let model = Self.propModels[.busStop] {
                        // The shelter stands back from the kerb.
                        place(model, at: out(width / 2 + pavement - 1.05), forward: forward, clearing: 3, tint: Map3DColor.rgb(0xFFFFFF))
                        guard map3DRandom(seed.0, seed.1, salt: 356) < 0.4 else { continue }
                    }
                    if let model = Self.propModels[.vending] {
                        let tint = Self.pick(Self.vendingColours, map3DRandom(seed.0, seed.1, salt: 357))
                        place(model, at: out(width / 2 + pavement - 0.6, ahead: pavement >= 2.5 ? 3.4 : 0), forward: forward, clearing: 1.2, tint: tint)
                    }
                }
            }
        }
    }

    /// How far apart the bus stops are along a road (vending machines
    /// alone along a smaller one), in metres; `nil` for none. Taiwan's city
    /// buses stop every 300–500 m.
    static func stopSpacing(_ kind: Map3DBaseMap.RoadKind) -> Double? {
        switch kind {
        case .trunk, .primary, .secondary: 420
        case .tertiary: 260
        case .motorway, .minor, .service: nil
        }
    }

    /// No stop this near a marked junction (its crossing and its signals).
    static let stopClearOfJunctions = 30.0

    /// The vending machines' bodies (props.js `VENDING_BODY`), in the
    /// palette's softer tones: white, red, blue, cream.
    /// Decision 370: in the model look (``Map3DLook``).
    static let vendingColours: [UInt32] = [0xECEDEA, 0xC8433F, 0x3F6FA8, 0xE8DDBF].map { Map3DLook.colour(Map3DColor.rgb($0)) }

    /// `model` standing on the pavement at `at`, its left toward the road
    /// along level `forward`, no tree, light or pole within `clearing`
    /// metres of it.
    private mutating func place(_ model: Int, at: Map3DBaseMap.Point, forward: Map3DBaseMap.Point, clearing: Float, tint: UInt32) {
        let x = Float(at.x), z = Float(at.z)
        let foot = Map3DPoint(x, drawnGround(x: x, z: z) + Self.sidewalkLift, z)
        let key = key(of: foot)
        let streetFurniture = Set([Map3DProp.tree, .lamp, .pole].compactMap { Self.propModels[$0] })
        props[key] = props[key]?.filter { instance in
            guard streetFurniture.contains(instance.model) else { return true }
            let dx = instance.transform[12] - x, dz = instance.transform[14] - z
            return dx * dx + dz * dz >= clearing * clearing
        }
        props[key, default: []].append(.prop(model, at: foot, forward: Map3DPoint(Float(forward.x), 0, Float(forward.z)), scale: 1, tint: tint))
    }
}
