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
//
// Decision 447: Taiwan's rules for the paint (道路交通標誌標線號誌設置規則,
// "the rules" below). The zebra's bars 0.4 m with 0.4 m between (第 185
// 條: 40 cm, 40–80 cm apart), standing 3 m back from the crossing road's
// kerb (3–5 m); a scooter box (機車停等區, 第 174-2 條) between the stop
// line and the crossing on the wider roads; a two-stage turn box (機車待
// 轉區, 第 191 條) in the corner before the crossing; and the kerb lines
// (第 168、169 條): red (no stopping) along the trunk and primary roads
// and within 10 m of a junction, yellow (no parking) along the others.
// After TW3D's `road-paint.js` (the owner's reference, slop-newyork's
// Taiwan edition, MIT, Copyright (c) 2026 Mr.doob: red kerbs along the
// main roads and yellow along the others, the scooter box over the
// incoming kerb-side lanes) and shwang1979/slop-taipei's `js/road-paint.js`
// (MIT, the same notice: the box's back line and its side line).

/// What the paint and the signals of a set of roads are: worked out from
/// the roads alone, the same every time.
struct Map3DRoadMarkings {
    enum Kind: Equatable {
        case crosswalk
        case stopLine
        /// Lane arrows: through, or through and left.
        case arrow(left: Bool)
        /// Decision 447: a line of a scooter box (機車停等區) before the
        /// stop line, or of a two-stage turn box (機車待轉區) in the
        /// junction's corner.
        case scooterBox(turn: Bool)
        /// Decision 447: a kerb line, red (no stopping) or yellow (no
        /// parking).
        case kerb(red: Bool)
        /// Decision 447 (continued): a painted walkway (標線型人行道) on a
        /// lane: its green band, or one of the white lines either side.
        case walkway(line: Bool)
    }

    /// Decision 447 (continued): where a road's pedestrians walk, by its
    /// class (TAIWAN_STREETSCAPE §2; hebe13579/slop-taipei's
    /// `pedestrianLayout`): a raised pavement along the main roads (an
    /// arcade where a row of shops meets it, decision 385), a painted
    /// walkway along a lane, the whole way shared on a service road;
    /// none on a bridge, a ramp or a motorway.
    enum Walkway: Equatable {
        case pavement
        case painted
        case shared
        case none
    }

    static func walkway(_ road: Map3DBaseMap.Road) -> Walkway {
        guard !road.isRamp, road.bridgeLevel == 0 else { return .none }
        switch road.kind {
        case .trunk, .primary, .secondary, .tertiary: return .pavement
        case .minor: return .painted
        case .service: return .shared
        case .motorway: return .none
        }
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
        /// Review H6: whether its road is a bridge's (on its deck).
        var onDeck = false
    }

    /// A signal at an approach's kerb: its foot, the way the traffic it
    /// faces goes, and (decision 429) whether that is the junction's main
    /// road or its crossing road, and the junction's offset in the
    /// signals' cycle (``Map3DSignalTiming``).
    struct Signal {
        let foot: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let road: Map3DSignalTiming.Road
        let group: Int
    }

    /// Decision 445: a pedestrian signal at a crossing's end: its foot,
    /// the way it looks (across the road, to the other end), the road
    /// whose traffic its pedestrians walk alongside (the other one than
    /// the road they cross) and its junction's group.
    struct Walk {
        let foot: Map3DBaseMap.Point
        let facing: Map3DBaseMap.Point
        let road: Map3DSignalTiming.Road
        let group: Int
    }

    /// How deep a zebra crossing is along the road, how far its bars stand
    /// back from the crossing road's kerb, and the stop line's gap before
    /// it and its own depth.
    /// Decision 447: 3 m back from the crossing road's kerb (the rules,
    /// 第 185 條: 3–5 m), where 355 had 0.6 m past its pavement.
    static let crosswalkDepth = 3.6
    static let kerbGap = 3.0
    static let stopGap = 2.0
    static let stopDepth = 0.4
    /// Decision 447: the zebra's bars, a bar and a gap each this wide
    /// (第 185 條: bars 40 cm, 40–80 cm apart).
    static let crosswalkPitch = 0.8
    /// Decision 447: the scooter box (第 174-2 條: 2.5–6 m deep, its cross
    /// lines 20 cm, its sides 10 or 15 cm) on an arm at least this wide
    /// each way (a secondary road's 8 m and up).
    static let scooterBoxDepth = 3.0
    static let scooterBoxFront = 0.2
    static let scooterBoxSide = 0.15
    static let scooterBoxHalf = 4.0
    /// Decision 447: the turn box (第 191 條: lines 15 cm, at least 50 cm
    /// before the crossing), this deep along the arm and at most this wide.
    static let turnBoxDepth = 2.0
    static let turnBoxWidth = 3.0
    static let turnBoxGap = 0.5
    /// Decision 447: the kerb lines (第 168、169 條: 10 cm), this far in
    /// from the carriageway's edge (to the line's middle); red this far
    /// on from where they stop at a junction (道路交通安全規則第 111 條:
    /// no stopping within 10 m of a junction).
    static let kerbWidth = 0.1
    static let kerbInset = 0.15
    static let redNearJunction = 10.0
    /// A lane arrow's size, and its gap behind the stop line.
    static let arrowLength = 5.0
    static let arrowWidth = 1.7
    static let arrowGap = 3.0

    var marks: [Mark] = []
    var signals: [Signal] = []
    var walks: [Walk] = []
    /// Decision 445: how far past the crossing's outer edge the pedestrian
    /// signals stand, along the road.
    static let walkGap = 0.4
    /// The junctions marked.
    var junctions: [Map3DBaseMap.Point] = []
    /// Per road (by index), the stretches of its length (metres from its
    /// first point) where its centre line is left out.
    var cuts: [Int: [ClosedRange<Double>]] = [:]
    /// Decision 447: per road, where its kerb lines are left out across
    /// a crossing road's mouth (and, by ``cuts``, the paint before it).
    var kerbCuts: [Int: [ClosedRange<Double>]] = [:]

    /// One way out of a junction along a road.
    struct Arm {
        let road: Int
        let kind: Map3DBaseMap.RoadKind
        /// Review H6: whether the road is a bridge's.
        var onDeck = false
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

    /// The marks of `roads`, their points in metres from `origin` (metres
    /// east and south of the world's origin: where the scene is, so a
    /// junction's signals keep their offset whatever scene draws them).
    init(_ roads: [Map3DBaseMap.Road], origin: Map3DBaseMap.Point = Map3DBaseMap.Point(x: 0, z: 0)) {
        // Every point of a marked road, by its half metre (as
        // Builder.junctions(of:) keys them).
        let at = Self.points(of: roads) { Map3DScene.Builder.hasCentreLine($0) }
        // The roads' lengths up to each point.
        var along: [Int: [Double]] = [:]
        func lengths(_ road: Int) -> [Double] {
            if let known = along[road] { return known }
            var sums = [0.0]
            for (a, b) in zip(roads[road].points, roads[road].points.dropFirst()) { sums.append(sums.last! + Self.distance(a, b)) }
            along[road] = sums
            return sums
        }
        func arms(_ entries: [(road: Int, index: Int)]) -> [Arm] {
            var arms: [Arm] = []
            for (road, index) in entries {
                let points = roads[road].points, sums = lengths(road)
                for forward in [true, false] {
                    let way = forward ? Array(points[index...]) : Array(points[...index].reversed())
                    guard way.count >= 2 else { continue }
                    let arm = Arm(road: road, kind: roads[road].kind, onDeck: roads[road].bridgeLevel > 0, points: way, at: sums[index], forward: forward)
                    // The same road from two tiles: one arm.
                    guard let out = arm.place(min(6, arm.length))?.out,
                          !arms.contains(where: { other in other.place(min(6, other.length)).map { Self.dot($0.out, out) > 0.98 } ?? false })
                    else { continue }
                    arms.append(arm)
                }
            }
            return arms
        }
        for key in at.keys.sorted() {
            guard let (point, entries) = at[key].map({ ($0.point, $0.entries) }), entries.count >= 2,
                  entries.contains(where: { Self.inside(point, roads[$0.road].bounds) }) else { continue }
            let arms = arms(entries)
            guard arms.count >= 3 else { continue }
            junctions.append(point)
            add(arms, group: Map3DSignalTiming.group(at: Map3DBaseMap.Point(x: point.x + origin.x, z: point.z + origin.z)))
        }
        // Decision 447: where any road on the ground (a lane too) meets a
        // kerbed one, its kerb lines stop across the mouth.
        let ground = Self.points(of: roads) { $0.bridgeLevel == 0 }
        for key in ground.keys.sorted() {
            guard let (point, entries) = ground[key].map({ ($0.point, $0.entries) }), entries.count >= 2,
                  entries.contains(where: { Self.inside(point, roads[$0.road].bounds) }) else { continue }
            let arms = arms(entries)
            guard arms.count >= 3 else { continue }
            let outs = arms.map { $0.place(min(6, $0.length))?.out ?? Map3DBaseMap.Point(x: 1, z: 0) }
            for (number, arm) in arms.enumerated() where Self.kerbed(roads[arm.road]) || Self.walkway(roads[arm.road]) == .painted {
                var mouth = 0.0
                for (other, crossing) in arms.enumerated() where other != number && Self.dot(outs[number], outs[other]) >= -0.9 {
                    let sine = max(0.5, abs(outs[number].x * outs[other].z - outs[number].z * outs[other].x))
                    mouth = max(mouth, (crossing.half + 1) / sine)
                }
                let cut = min(arm.length, mouth)
                kerbCuts[arm.road, default: []].append(arm.forward ? arm.at...(arm.at + cut) : (arm.at - cut)...arm.at)
            }
        }
        for (number, road) in roads.enumerated() where Self.kerbed(road) {
            addKerbs(road, number: number, lengths: lengths(number))
        }
        for (number, road) in roads.enumerated() where Self.walkway(road) == .painted && road.points.count >= 2 {
            addWalkway(road, number: number, lengths: lengths(number), origin: origin)
        }
    }

    /// Decision 447 (continued): the painted walkway's green band and its
    /// white lines (hebe13579/slop-taipei `js/taipei-painted.js`: the band
    /// on one side of the lane, a white line either side, stopping at the
    /// junctions), metres. The band as wide as the narrowest pavement of a
    /// road 12 m wide or less (市區道路及附屬工程設計標準第 16 條: 1.2 m).
    static let walkwayBand = 1.2
    static let walkwayLine = 0.1
    static let walkwayInset = 0.05

    /// Which side of `road` its painted walkway is on, from where the road
    /// starts in the world (the same from every tile): 1 its right, −1
    /// its left.
    static func walkwaySide(_ road: Map3DBaseMap.Road, origin: Map3DBaseMap.Point) -> Double {
        let start = road.points[0]
        let x = Int32(truncatingIfNeeded: Int(((start.x + origin.x) * 2).rounded())), z = Int32(truncatingIfNeeded: Int(((start.z + origin.z) * 2).rounded()))
        return map3DRandom(x, z, salt: 447) < 0.5 ? 1 : -1
    }

    /// Decision 447 (continued): `road`'s painted walkway, segment by
    /// segment, left out across the mouths of the roads meeting it.
    private mutating func addWalkway(_ road: Map3DBaseMap.Road, number: Int, lengths sums: [Double], origin: Map3DBaseMap.Point) {
        let cut = kerbCuts[number] ?? [], side = Self.walkwaySide(road, origin: origin)
        let half = Double(road.kind.width(ramp: false)) / 2
        let outer = half - Self.walkwayInset - Self.walkwayLine / 2, inner = outer - Self.walkwayLine - Self.walkwayBand
        let band = (outer + inner) / 2
        for (index, (a, b)) in zip(road.points, road.points.dropFirst()).enumerated() {
            let length = Self.distance(a, b), start = sums[index]
            guard length > 0.01 else { continue }
            var stops = [0.0, length]
            for range in cut {
                for edge in [range.lowerBound, range.upperBound] where edge > start && edge < start + length { stops.append(edge - start) }
            }
            stops.sort()
            let way = Map3DBaseMap.Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length), right = Map3DBaseMap.Point(x: -way.z * side, z: way.x * side)
            for (from, to) in zip(stops, stops.dropFirst()) where to - from > 0.5 {
                let centre = Map3DBaseMap.Point(x: a.x + way.x * (from + to) / 2, z: a.z + way.z * (from + to) / 2)
                guard !cut.contains(where: { $0.contains(start + (from + to) / 2) }), Self.inside(centre, road.bounds) else { continue }
                func at(_ by: Double) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: centre.x + right.x * by, z: centre.z + right.z * by) }
                marks.append(Mark(kind: .walkway(line: false), centre: at(band), along: way, length: to - from, width: Self.walkwayBand))
                for edge in [outer, inner] {
                    marks.append(Mark(kind: .walkway(line: true), centre: at(edge), along: way, length: to - from, width: Self.walkwayLine))
                }
            }
        }
    }

    /// Every point of the roads `including` takes, by its half metre (as
    /// Builder.junctions(of:) keys them), with the roads through it.
    private static func points(of roads: [Map3DBaseMap.Road], including: (Map3DBaseMap.Road) -> Bool)
        -> [Int64: (point: Map3DBaseMap.Point, entries: [(road: Int, index: Int)])] {
        var at: [Int64: (point: Map3DBaseMap.Point, entries: [(road: Int, index: Int)])] = [:]
        for (number, road) in roads.enumerated() where including(road) && road.points.count >= 2 {
            var seen = Set<Int64>()
            for (index, point) in road.points.enumerated() {
                let key = Self.key(point)
                guard seen.insert(key).inserted else { continue }
                at[key, default: (point, [])].entries.append((number, index))
            }
        }
        return at
    }

    /// Decision 447: whether a road has kerb lines: the two-way roads
    /// with a centre line, on the ground.
    static func kerbed(_ road: Map3DBaseMap.Road) -> Bool {
        Map3DScene.Builder.hasCentreLine(road) && road.bridgeLevel == 0
    }

    /// Decision 447: `road`'s kerb lines both sides, in pieces no longer
    /// than a segment or ``kerbPiece``, left out where ``kerbCuts`` (and
    /// the centre line's ``cuts``, the paint at a marked junction) are,
    /// red along a trunk or primary road and for ``redNearJunction``
    /// either side of where they are left out.
    private mutating func addKerbs(_ road: Map3DBaseMap.Road, number: Int, lengths sums: [Double]) {
        let cut = (kerbCuts[number] ?? []) + (cuts[number] ?? [])
        let red = cut.map { ($0.lowerBound - Self.redNearJunction)...($0.upperBound + Self.redNearJunction) }
        let allRed = road.kind == .trunk || road.kind == .primary
        let offset = Double(road.kind.width(ramp: false)) / 2 - Self.kerbInset
        for (index, (a, b)) in zip(road.points, road.points.dropFirst()).enumerated() {
            let length = Self.distance(a, b), start = sums[index]
            guard length > 0.01 else { continue }
            var stops = [0.0, length]
            for range in cut + red {
                for edge in [range.lowerBound, range.upperBound] where edge > start && edge < start + length { stops.append(edge - start) }
            }
            var piece = 0.0
            while piece + Self.kerbPiece < length { piece += Self.kerbPiece; stops.append(piece) }
            stops.sort()
            let way = Map3DBaseMap.Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length), right = Map3DBaseMap.Point(x: -way.z, z: way.x)
            for (from, to) in zip(stops, stops.dropFirst()) where to - from > 0.05 {
                let middle = start + (from + to) / 2
                let centre = Map3DBaseMap.Point(x: a.x + way.x * (from + to) / 2, z: a.z + way.z * (from + to) / 2)
                guard !cut.contains(where: { $0.contains(middle) }), Self.inside(centre, road.bounds) else { continue }
                let isRed = allRed || red.contains { $0.contains(middle) }
                for side in [1.0, -1.0] {
                    marks.append(Mark(kind: .kerb(red: isRed), centre: Map3DBaseMap.Point(x: centre.x + right.x * side * offset, z: centre.z + right.z * side * offset),
                                      along: way, length: to - from, width: Self.kerbWidth))
                }
            }
        }
    }

    /// Decision 447: the longest piece of a kerb line, metres.
    static let kerbPiece = 64.0

    private mutating func add(_ arms: [Arm], group: Int) {
        let outs = arms.map { $0.place(min(6, $0.length))?.out ?? Map3DBaseMap.Point(x: 1, z: 0) }
        // The main road: the widest arm (the first of the widest), its way
        // and the opposite (decision 355 showed them green; decision 429
        // turns them with the crossing road).
        let main = arms.indices.max { arms[$0].half < arms[$1].half || (arms[$0].half == arms[$1].half && $0 > $1) } ?? 0
        for (number, arm) in arms.enumerated() {
            // Clear of the crossing roads and their pavements, more where
            // they cross at a slant.
            // Decision 447: from the crossing roads' kerbs (355 went on
            // past their pavements).
            var clear = 0.0
            for (other, crossing) in arms.enumerated() where other != number {
                let sine = max(0.5, abs(outs[number].x * outs[other].z - outs[number].z * outs[other].x))
                // An arm straight on (the same road beyond) is not crossed.
                if Self.dot(outs[number], outs[other]) < -0.9 { continue }
                clear = max(clear, crossing.half / sine)
            }
            let crosswalk = clear + Self.kerbGap + Self.crosswalkDepth / 2
            // Decision 447: on a wide arm the scooters wait in their box
            // ahead of the cars' stop line.
            let boxed = arm.half >= Self.scooterBoxHalf
            let front = crosswalk + Self.crosswalkDepth / 2 + Self.stopGap
            let stop = front + (boxed ? Self.scooterBoxDepth : 0) + Self.stopDepth / 2
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
            marks.append(Mark(kind: .crosswalk, centre: zebra.point, along: toward(zebra.out), length: Self.crosswalkDepth, width: 2 * half,
                              onDeck: arm.onDeck))
            let way = toward(line.out)
            marks.append(Mark(kind: .stopLine, centre: moved(line.point, right(way), half / 2), along: way, length: Self.stopDepth,
                              width: half - 0.3, onDeck: arm.onDeck))
            // Decision 447: the scooter box, over the incoming half from
            // the centre line to the kerb line: its front line, its two
            // sides back to the stop line.
            let inner = 0.3, outer = half - Self.kerbInset - Self.kerbWidth / 2 - 0.1
            if boxed, let ahead = arm.place(front + Self.scooterBoxFront / 2), let middle = arm.place(front + Self.scooterBoxDepth / 2) {
                let way = toward(ahead.out)
                marks.append(Mark(kind: .scooterBox(turn: false), centre: moved(ahead.point, right(way), (inner + outer) / 2), along: way,
                                  length: Self.scooterBoxFront, width: outer - inner, onDeck: arm.onDeck))
                for edge in [inner + Self.scooterBoxSide / 2, outer - Self.scooterBoxSide / 2] {
                    marks.append(Mark(kind: .scooterBox(turn: false), centre: moved(middle.point, right(toward(middle.out)), edge),
                                      along: toward(middle.out), length: Self.scooterBoxDepth, width: Self.scooterBoxSide, onDeck: arm.onDeck))
                }
            }
            // Decision 447: the turn box, in the corner between the
            // crossing road's kerb and this crossing, by the kerb of the
            // incoming half: where a scooter turning left from the road
            // on its right waits for this road's green.
            if boxed, outs.indices.contains(where: { $0 != number && abs(Self.dot(outs[$0], outs[number])) < 0.7 }),
               let box = arm.place(crosswalk - Self.crosswalkDepth / 2 - Self.turnBoxGap - Self.turnBoxDepth / 2) {
                let way = toward(box.out), width = min(Self.turnBoxWidth, outer - inner), edge = Self.scooterBoxSide
                let middle = outer - width / 2
                for (ahead, across, length, wide) in [(Self.turnBoxDepth / 2 - edge / 2, middle, edge, width),
                                                      (-Self.turnBoxDepth / 2 + edge / 2, middle, edge, width),
                                                      (0, outer - edge / 2, Self.turnBoxDepth, edge),
                                                      (0, outer - width + edge / 2, Self.turnBoxDepth, edge)] {
                    marks.append(Mark(kind: .scooterBox(turn: true), centre: moved(moved(box.point, right(way), across), way, ahead), along: way,
                                      length: length, width: wide, onDeck: arm.onDeck))
                }
            }
            if length >= arrow + Self.arrowLength / 2 + 3, let place = arm.place(arrow) {
                let way = toward(place.out)
                // Two lanes each way on a road this wide, the inner one
                // through and left.
                let lanes = half >= 5 ? 2 : 1, lane = half / Double(lanes)
                for index in 0..<lanes {
                    marks.append(Mark(kind: .arrow(left: lanes > 1 && index == 0), centre: moved(place.point, right(way), (Double(index) + 0.5) * lane),
                                      along: way, length: Self.arrowLength, width: Self.arrowWidth, onDeck: arm.onDeck))
                }
            }
            // The signal at the kerb by the stop line, on the pavement.
            let kerb = half + max(0.5, min(1, Double(Map3DScene.Builder.sidewalk(of: arm.kind)) * 0.3))
            let road: Map3DSignalTiming.Road = abs(Self.dot(outs[number], outs[main])) >= 0.7 ? .main : .cross
            signals.append(Signal(foot: moved(line.point, right(way), kerb), along: way, road: road, group: group))
            // Decision 445: a pedestrian signal at each end of the
            // crossing, on the pavement just past its outer edge, looking
            // across at the other end; who crosses this road walks with
            // the other road's traffic.
            if let end = arm.place(crosswalk + Self.crosswalkDepth / 2 + Self.walkGap) {
                let across = right(toward(end.out))
                for side in [1.0, -1.0] {
                    walks.append(Walk(foot: moved(end.point, across, side * kerb), facing: Map3DBaseMap.Point(x: -across.x * side, z: -across.z * side),
                                      road: road == .main ? .cross : .main, group: group))
                }
            }
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
                // Decision 447: a bar and its gap 0.8 m (355: 0.9 m); the
                // layer's bar is half of it.
                addMark(mark, colour: Map3DPalette.road(.primary), layer: Float(Map3DSurface.crosswalk.rawValue),
                        u: (0, max(1, (mark.width / Map3DRoadMarkings.crosswalkPitch).rounded())), v: (0, 1))
            case .stopLine, .scooterBox:
                addMark(mark, colour: Self.paint, layer: Map3DVertex.plain, u: (0, 1), v: (0, 1))
            case .kerb(let red):
                addMark(mark, colour: red ? Self.kerbRed : Map3DPalette.centreLine, layer: Map3DVertex.plain, u: (0, 1), v: (0, 1))
            case .walkway(let line):
                addMark(mark, colour: line ? Self.paint : Self.walkwayGreen, layer: Map3DVertex.plain, u: (0, 1), v: (0, 1))
            case .arrow(let left):
                addMark(mark, colour: Map3DPalette.road(.primary), layer: Float(Map3DSurface.laneArrows.rawValue),
                        u: left ? (0.5, 1) : (0, 0.5), v: (0, 1))
            }
        }
    }

    /// The road paint's white, a little warm.
    static let paint = Map3DColor.rgb(0xEEEEE8)
    /// Decision 447: the red kerb line, the level crossing barrier's red;
    /// the yellow one is the centre line's.
    static let kerbRed = Self.barrierRed
    /// Decision 447 (continued): the painted walkway's green, the trees'
    /// darker green (``Map3DProp/greens``, before their matte look).
    static let walkwayGreen = Map3DColor.rgb(0x4E9E3E)

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
        // Decision 391: none on a bridge's deck (a junction there is rare),
        // at the road's height on a ramp; decision 375: none where the road
        // gives way to a trench. Review H6: on its own road's deck only, not
        // one over it.
        let way = (mark.along.x, mark.along.z)
        let raised = roadRise(at: mark.centre, along: way, onDeck: mark.onDeck)
        guard !raised.onBridge, !givesWay(at: mark.centre, along: way) else { return }
        let lift = Self.centreLineLift + raised.rise
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
    /// Decision 429: a signal stands as it shows when the clock does not
    /// turn it (``Map3DSignalTiming/steady(_:)``: the main road's green,
    /// the crossing road's red), with its junction's group, and the
    /// renderer draws the light the clock shows
    /// (``Map3DSignalTiming/Models``).
    mutating func addStreetStops(_ roads: [Map3DBaseMap.Road], markings: Map3DRoadMarkings) {
        for signal in markings.signals {
            guard let model = Self.propModels[signal.road == .main ? .signalGo : .signalStop] else { continue }
            place(model, at: signal.foot, forward: signal.along, clearing: 1.5, tint: Map3DColor.rgb(0xFFFFFF), group: signal.group)
        }
        // Decision 445: each pedestrian signal its face and its countdown's
        // two digits, in one place, looking across the road (the model
        // looks toward its left).
        if let walking = Self.walkModels {
            let placed = walking.placed
            for walk in markings.walks {
                let forward = Map3DBaseMap.Point(x: -walk.facing.z, z: walk.facing.x), group = Map3DPedestrianSignal.group(walk.group, road: walk.road)
                place(placed.head, at: walk.foot, forward: forward, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF), group: group)
                place(placed.tens, at: walk.foot, forward: forward, clearing: 0, tint: Map3DColor.rgb(0xFFFFFF), group: group)
                place(placed.ones, at: walk.foot, forward: forward, clearing: 0, tint: Map3DColor.rgb(0xFFFFFF), group: group)
            }
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
                        place(model, at: out(width / 2 + pavement - 1.05), forward: forward, clearing: 3, tint: Map3DColor.rgb(0xFFFFFF),
                              onDeck: road.bridgeLevel > 0)
                        guard map3DRandom(seed.0, seed.1, salt: 356) < 0.4 else { continue }
                    }
                    if let model = Self.propModels[.vending] {
                        let tint = Self.pick(Self.vendingColours, map3DRandom(seed.0, seed.1, salt: 357))
                        place(model, at: out(width / 2 + pavement - 0.6, ahead: pavement >= 2.5 ? 3.4 : 0), forward: forward, clearing: 1.2, tint: tint,
                              onDeck: road.bridgeLevel > 0)
                    }
                }
            }
        }
    }

    /// Decision 445: the pedestrian signals' models in ``Map3DModelPack/standard``.
    static let walkModels = Map3DPedestrianSignal.Models(pack: .standard)

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
    private mutating func place(_ model: Int, at: Map3DBaseMap.Point, forward: Map3DBaseMap.Point, clearing: Float, tint: UInt32,
                                onDeck: Bool = false, group: Int = 0) {
        // Decision 391: none on a bridge or its ramp.
        guard roadRise(at: at, along: nil, onDeck: onDeck).rise < Self.propRise else { return }
        let x = Float(at.x), z = Float(at.z)
        let foot = Map3DPoint(x, drawnGround(x: x, z: z) + Self.sidewalkLift, z)
        let key = key(of: foot)
        let streetFurniture = Set([Map3DProp.tree, .lamp, .pole].compactMap { Self.propModels[$0] })
        props[key] = props[key]?.filter { instance in
            guard streetFurniture.contains(instance.model) else { return true }
            let dx = instance.transform[12] - x, dz = instance.transform[14] - z
            return dx * dx + dz * dz >= clearing * clearing
        }
        var instance = Map3DInstance.prop(model, at: foot, forward: Map3DPoint(Float(forward.x), 0, Float(forward.z)), scale: 1, tint: tint)
        instance.group = group
        props[key, default: []].append(instance)
    }
}
