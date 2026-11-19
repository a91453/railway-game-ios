import Foundation
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
        /// Decision 732: `mirrored`, left for right (Hong Kong's inner
        /// lane, through and right).
        case arrow(left: Bool, mirrored: Bool = false)
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
        /// Decision 846's second later note: one triangle of a give-way
        /// line (Traficom L2), its point toward the traffic coming and its
        /// base across the lane at the ring's edge.
        case giveWay
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
        /// Review K2-3: a point on its line its road's segment starts
        /// from, so it is cut near a raised road where the road is
        /// (``Map3DScene/Builder/raisedCuts(from:to:anchor:along:onDeck:)``);
        /// `nil`, its far end back.
        var anchor: Map3DBaseMap.Point?
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

    /// Decision 846's third later note: a street name sign at a
    /// junction's corner: its post's foot on the pavement, the way along
    /// the road it names (its plate's face across it, read from either
    /// side) and the name.
    struct StreetName {
        let foot: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let name: String
    }

    /// Decision 846's later note: a pedestrian crossing's sign: its foot on
    /// the pavement and the way the traffic it faces goes.
    struct CrossingSign {
        let foot: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
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

    /// Decision 596: where an approach's traffic stops for its signal: the
    /// stop line's point on the road's middle line, the way the traffic
    /// goes (toward the junction), its road and its junction's group.
    struct Stop {
        let point: Map3DBaseMap.Point
        let along: Map3DBaseMap.Point
        let road: Map3DSignalTiming.Road
        let group: Int
    }

    /// Decision 596: a zebra crossing with signals: its middle on the
    /// crossed road's middle line, the way out of the junction along that
    /// road, the road's half width, the road whose traffic the people
    /// crossing walk alongside (as ``Walk/road``) and the junction's group.
    struct Crossing {
        let centre: Map3DBaseMap.Point
        let out: Map3DBaseMap.Point
        let half: Double
        let road: Map3DSignalTiming.Road
        let group: Int
    }

    /// Decision 732: whose roads they are: which side the traffic keeps
    /// to, and whether there are scooter boxes, red kerbs and painted
    /// walkways (``Map3DStreetRegion``).
    var region: Map3DStreetRegion = .taiwan
    var marks: [Mark] = []
    var signals: [Signal] = []
    var walks: [Walk] = []
    var stops: [Stop] = []
    var crossings: [Crossing] = []
    /// Decision 846's later note: the pedestrian crossing's signs
    /// (``Map3DFinlandStreet/Unit/crossingSign``) at a crossing with no
    /// signal, one a way the traffic comes, where the region stands them.
    var crossingSigns: [CrossingSign] = []
    /// Decision 846's fourth later note: the give-way signs
    /// (``Map3DFinlandStreet/Unit/giveWaySign``) where a road comes to a
    /// roundabout, on the kerb of the traffic coming in, at its give-way
    /// line, looking at that traffic.
    var giveWaySigns: [CrossingSign] = []
    /// Decision 846's third later note: the street name signs, where the
    /// region stands them.
    var streetNames: [StreetName] = []
    /// Decision 445: how far past the crossing's outer edge the pedestrian
    /// signals stand, along the road.
    static let walkGap = 0.4
    /// The junctions marked.
    var junctions: [Map3DBaseMap.Point] = []
    /// Decision 846: the junctions found on a roundabout's ring (where the
    /// region's roundabouts have no signals).
    var roundabouts: [Ring] = []
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
        /// Decision 846's second later note: its road taken one way only,
        /// the way its points run (``Map3DBaseMap/Road/oneway``).
        var oneway = false
        /// Decision 846's third later note: its road's name.
        var name: String?

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
    /// Decision 732: in `region` (traffic on the left in Hong Kong, the
    /// stop lines, arrows and signals on that side; no scooter boxes, red
    /// kerbs or painted walkways there).
    init(_ roads: [Map3DBaseMap.Road], origin: Map3DBaseMap.Point = Map3DBaseMap.Point(x: 0, z: 0), region: Map3DStreetRegion = .taiwan) {
        self.region = region
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
                    let arm = Arm(road: road, kind: roads[road].kind, onDeck: roads[road].bridgeLevel > 0, points: way, at: sums[index], forward: forward,
                                  oneway: roads[road].oneway, name: roads[road].name)
                    // The same road from two tiles: one arm.
                    guard let out = arm.place(min(6, arm.length))?.out,
                          !arms.contains(where: { other in other.place(min(6, other.length)).map { Self.dot($0.out, out) > 0.98 } ?? false })
                    else { continue }
                    arms.append(arm)
                }
            }
            return arms
        }
        // Decision 846: the roads' segments by square, for whether a ring
        // goes round (made only when a junction might be on one).
        var near = Segments(roads)
        var found: [(point: Map3DBaseMap.Point, arms: [Arm])] = []
        for key in at.keys.sorted() {
            guard let (point, entries) = at[key].map({ ($0.point, $0.entries) }), entries.count >= 2,
                  entries.contains(where: { Self.inside(point, roads[$0.road].bounds) }) else { continue }
            let arms = arms(entries)
            guard arms.count >= 3 else { continue }
            junctions.append(point)
            found.append((point, arms))
            // Decision 846: the roundabouts, where the region's have no
            // signals: each ring once, from the first junction it is read at.
            guard !region.signalsRoundabouts,
                  let ring = Self.ring(at: point, arms: arms, near: { near.near($0, within: $1) }),
                  !roundabouts.contains(where: { Self.distance($0.centre, ring.centre) < Self.ringSame }) else { continue }
            roundabouts.append(ring)
        }
        for (point, arms) in found {
            let group = Map3DSignalTiming.group(at: Map3DBaseMap.Point(x: point.x + origin.x, z: point.z + origin.z))
            add(arms, group: group, layout: Self.layout(at: point, arms: arms, rings: roundabouts))
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
        for (number, road) in roads.enumerated() where region.hasPaintedWalkways && Self.walkway(road) == .painted && road.points.count >= 2 {
            addWalkway(road, number: number, lengths: lengths(number))
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

    /// Which side of a stretch of lane going `way` its painted walkway is
    /// on: 1 its right, −1 its left. From the way alone, so the lane's
    /// copies in every tile, and the lane drawn either way, agree: the
    /// side to the right of a heading a little north of east (a lane
    /// along a street grid never turns the band over between blocks).
    static func walkwaySide(_ way: Map3DBaseMap.Point) -> Double {
        way.x * 0.94 - way.z * 0.34 >= 0 ? 1 : -1
    }

    /// Review K2-5: which side of `road`, as its points run, its painted
    /// walkway is on (1 its right, −1 its left): ``walkwaySide(_:)`` of
    /// the way from its first point to its last, once for the whole road,
    /// so a lane bending through a heading near the dividing one keeps its
    /// band on one side; of its first segment's way when it ends where it
    /// starts.
    static func walkwaySide(of road: Map3DBaseMap.Road) -> Double {
        guard let first = road.points.first, let last = road.points.last else { return 1 }
        var dx = last.x - first.x, dz = last.z - first.z
        if (dx * dx + dz * dz).squareRoot() < 1,
           let (a, b) = zip(road.points, road.points.dropFirst()).first(where: { distance($0.0, $0.1) > 0.01 }) {
            (dx, dz) = (b.x - a.x, b.z - a.z)
        }
        return walkwaySide(Map3DBaseMap.Point(x: dx, z: dz))
    }

    /// Decision 447 (continued): `road`'s painted walkway, segment by
    /// segment, left out across the mouths of the roads meeting it.
    private mutating func addWalkway(_ road: Map3DBaseMap.Road, number: Int, lengths sums: [Double]) {
        let cut = kerbCuts[number] ?? []
        let half = Double(road.kind.width(ramp: false)) / 2
        let side = Self.walkwaySide(of: road)
        let outer = half - Self.walkwayInset - Self.walkwayLine / 2, inner = outer - Self.walkwayLine - Self.walkwayBand
        let band = (outer + inner) / 2
        for (index, (a, b)) in zip(road.points, road.points.dropFirst()).enumerated() {
            let length = Self.distance(a, b), start = sums[index]
            guard length > 0.01 else { continue }
            var stops = [0.0, length]
            for range in cut {
                for edge in [range.lowerBound, range.upperBound] where edge > start && edge < start + length { stops.append(edge - start) }
            }
            // As the kerb lines: no piece longer than a tile's own.
            var piece = 0.0
            while piece + Self.kerbPiece < length { piece += Self.kerbPiece; stops.append(piece) }
            stops.sort()
            let way = Map3DBaseMap.Point(x: (b.x - a.x) / length, z: (b.z - a.z) / length)
            let right = Map3DBaseMap.Point(x: -way.z * side, z: way.x * side)
            for (from, to) in zip(stops, stops.dropFirst()) where to - from > 0.5 {
                let centre = Map3DBaseMap.Point(x: a.x + way.x * (from + to) / 2, z: a.z + way.z * (from + to) / 2)
                guard !cut.contains(where: { $0.contains(start + (from + to) / 2) }), Self.inside(centre, road.bounds) else { continue }
                func at(_ by: Double, from p: Map3DBaseMap.Point = centre) -> Map3DBaseMap.Point {
                    Map3DBaseMap.Point(x: p.x + right.x * by, z: p.z + right.z * by)
                }
                marks.append(Mark(kind: .walkway(line: false), centre: at(band), along: way, length: to - from, width: Self.walkwayBand,
                                  anchor: at(band, from: a)))
                for edge in [outer, inner] {
                    marks.append(Mark(kind: .walkway(line: true), centre: at(edge), along: way, length: to - from, width: Self.walkwayLine,
                                      anchor: at(edge, from: a)))
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
        // Decision 802: none on Finland's kerbs.
        guard region.hasKerbLines else { return }
        let cut = (kerbCuts[number] ?? []) + (cuts[number] ?? [])
        let red = cut.map { ($0.lowerBound - Self.redNearJunction)...($0.upperBound + Self.redNearJunction) }
        // Decision 732: Hong Kong's kerbs, yellow all along.
        let allRed = region.hasRedKerbs && (road.kind == .trunk || road.kind == .primary)
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
                let isRed = allRed || (region.hasRedKerbs && red.contains { $0.contains(middle) })
                for side in [1.0, -1.0] {
                    marks.append(Mark(kind: .kerb(red: isRed), centre: Map3DBaseMap.Point(x: centre.x + right.x * side * offset, z: centre.z + right.z * side * offset),
                                      along: way, length: to - from, width: Self.kerbWidth,
                                      anchor: Map3DBaseMap.Point(x: a.x + right.x * side * offset, z: a.z + right.z * side * offset)))
                }
            }
        }
    }

    /// Decision 447: the longest piece of a kerb line, metres.
    static let kerbPiece = 64.0

    // MARK: Roundabouts (decision 846)

    /// Decision 846: a roundabout's ring: its middle and radius.
    struct Ring: Sendable, Equatable {
        let centre: Map3DBaseMap.Point
        let radius: Double
    }

    /// Decision 846: what a junction gets.
    enum Layout: Equatable {
        /// Decision 355's: crossings, stop lines, arrows and signals (and
        /// decision 447's scooter boxes where the region has them).
        case signals
        /// On a roundabout's ring: the arms `along` it nothing; the roads
        /// coming in a crossing alone, no stop line, arrows, scooter box,
        /// signal or pedestrian signal, nor a place to wait at a light.
        case ring(along: Set<Int>)
        /// Where a road coming to a roundabout splits round its island
        /// (``ringApproach``): nothing, its crossings being the ring's.
        case bare
    }

    /// Rings read at two junctions this near are one, metres.
    static let ringSame = 5.0
    /// How far beyond a ring a junction is taken to be the split of a road
    /// coming in round its island, metres.
    static let ringApproach = 60.0

    /// How far off a ring a point on it may be read, metres: a quarter of
    /// its radius, at least 3 m.
    static func ringSlack(_ ring: Ring) -> Double { max(3, ring.radius / 4) }

    /// Decision 846: the layout of the junction at `point` of `arms`, with
    /// the roundabouts `rings` found: on a ring (within its slack), its
    /// arms that run on along it (6 m out still on it); within
    /// ``ringApproach`` beyond one, bare; else signals.
    static func layout(at point: Map3DBaseMap.Point, arms: [Arm], rings: [Ring]) -> Layout {
        var approach = false
        for ring in rings {
            let off = distance(point, ring.centre) - ring.radius, slack = ringSlack(ring)
            if abs(off) <= slack {
                let along = arms.indices.filter { index in
                    guard let out = arms[index].place(min(6, arms[index].length))?.point else { return false }
                    return abs(distance(out, ring.centre) - ring.radius) <= slack
                }
                return .ring(along: Set(along))
            }
            if off > 0, off <= ringApproach { approach = true }
        }
        return approach ? .bare : .signals
    }

    /// The radii a roundabout's ring is taken to have, metres: from a
    /// small town's (Finland's guide has 10–20 m rings in towns) to a big
    /// city's; a road bending tighter or wider is not one.
    static let ringRadii = 5.0...60.0
    /// How far along an arm its bend is read, metres.
    static let ringReach = 16.0
    /// How many points round a ring are looked for road at, and how many
    /// must have it.
    static let ringSamples = 12
    static let ringFound = 10

    /// The circle through `a`, `b` and `c`; `nil` when they are (nearly)
    /// in a line.
    static func circle(_ a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point, _ c: Map3DBaseMap.Point) -> (centre: Map3DBaseMap.Point, radius: Double)? {
        let bx = b.x - a.x, bz = b.z - a.z, cx = c.x - a.x, cz = c.z - a.z
        let d = 2 * (bx * cz - bz * cx)
        guard abs(d) > 1e-6 else { return nil }
        let b2 = bx * bx + bz * bz, c2 = cx * cx + cz * cz
        let ux = (cz * b2 - bz * c2) / d, uz = (bx * c2 - cx * b2) / d
        return (Map3DBaseMap.Point(x: a.x + ux, z: a.z + uz), (ux * ux + uz * uz).squareRoot())
    }

    /// The circle `points` lie nearest (Kåsa's least squares, round the
    /// first point); `nil` for fewer than three, or in a line.
    static func fit(_ points: [Map3DBaseMap.Point]) -> (centre: Map3DBaseMap.Point, radius: Double)? {
        guard points.count >= 3, let origin = points.first else { return nil }
        // Sums for x² + z² + D x + E z + F = 0.
        var m = [[Double]](repeating: [0, 0, 0], count: 3), v = [0.0, 0, 0]
        for p in points {
            let x = p.x - origin.x, z = p.z - origin.z, row = [x, z, 1.0], r = -(x * x + z * z)
            for a in 0..<3 {
                v[a] += row[a] * r
                for b in 0..<3 { m[a][b] += row[a] * row[b] }
            }
        }
        // Cramer's rule.
        func det(_ m: [[Double]]) -> Double {
            m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) - m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0])
                + m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-9 else { return nil }
        let solved = (0..<3).map { column -> Double in
            var replaced = m
            for row in 0..<3 { replaced[row][column] = v[row] }
            return det(replaced) / d
        }
        let cx = -solved[0] / 2, cz = -solved[1] / 2, squared = cx * cx + cz * cz - solved[2]
        guard squared > 0 else { return nil }
        return (Map3DBaseMap.Point(x: origin.x + cx, z: origin.z + cz), squared.squareRoot())
    }

    /// Decision 846: whether the junction at `point` of `arms` is on a
    /// roundabout's ring. The map's roads carry no tag for it (the tiles'
    /// schema has none), so it is read from their shape: two of the arms
    /// bend round one middle, within ``ringRadii``, and road is found all
    /// the way round that circle (``ringFound`` of ``ringSamples`` points
    /// within a fifth of its radius, at least 3 m, of a road), which a
    /// road bending through a junction does not have.
    static func ring(at point: Map3DBaseMap.Point, arms: [Arm], near: (Map3DBaseMap.Point, Double) -> Bool) -> Ring? {
        let circles = arms.map { arm -> (centre: Map3DBaseMap.Point, radius: Double)? in
            let reach = min(ringReach, arm.length)
            guard reach >= 6, let middle = arm.place(reach / 2)?.point, let end = arm.place(reach)?.point,
                  let circle = circle(point, middle, end), ringRadii.contains(circle.radius) else { return nil }
            return circle
        }
        for i in arms.indices {
            guard let a = circles[i] else { continue }
            for j in arms.indices where j > i {
                guard let b = circles[j] else { continue }
                let larger = max(a.radius, b.radius)
                guard distance(a.centre, b.centre) <= 2 + 0.25 * larger, abs(a.radius - b.radius) <= 0.3 * larger else { continue }
                // The circle that fits the two arms best, from a point
                // every 2 m along each (three points read it roughly).
                var samples = [point]
                for arm in [arms[i], arms[j]] {
                    let reach = min(ringReach, arm.length)
                    samples += stride(from: 2.0, through: reach, by: 2).compactMap { arm.place($0)?.point }
                }
                guard let (centre, radius) = fit(samples), ringRadii.contains(radius) else { continue }
                let reach = max(3, radius / 5)
                let found = (0..<ringSamples).filter { index in
                    let angle = Double(index) / Double(ringSamples) * 2 * .pi
                    return near(Map3DBaseMap.Point(x: centre.x + cos(angle) * radius, z: centre.z + sin(angle) * radius), reach)
                }.count
                guard found >= ringFound else { continue }
                return Ring(centre: centre, radius: radius)
            }
        }
        return nil
    }

    /// Decision 846: the roads' segments by 32 m square, made the first
    /// time it is asked, for whether a point is near a road.
    struct Segments {
        private let roads: [Map3DBaseMap.Road]
        private var squares: [Int64: [(Map3DBaseMap.Point, Map3DBaseMap.Point)]]?
        static let side = 32.0

        init(_ roads: [Map3DBaseMap.Road]) { self.roads = roads }

        private static func square(_ column: Int, _ row: Int) -> Int64 { Int64(column) << 32 ^ (Int64(row) & 0xFFFF_FFFF) }

        /// Whether a road's middle line passes within `reach` metres of `p`.
        mutating func near(_ p: Map3DBaseMap.Point, within reach: Double) -> Bool {
            if squares == nil {
                var made: [Int64: [(Map3DBaseMap.Point, Map3DBaseMap.Point)]] = [:]
                for road in roads where road.points.count >= 2 {
                    for (a, b) in zip(road.points, road.points.dropFirst()) {
                        let columns = Int((min(a.x, b.x) / Self.side).rounded(.down))...Int((max(a.x, b.x) / Self.side).rounded(.down))
                        let rows = Int((min(a.z, b.z) / Self.side).rounded(.down))...Int((max(a.z, b.z) / Self.side).rounded(.down))
                        // A long segment (a motorway's) in no more than a
                        // few hundred squares.
                        guard columns.count * rows.count <= 400 else { continue }
                        for column in columns {
                            for row in rows { made[Self.square(column, row), default: []].append((a, b)) }
                        }
                    }
                }
                squares = made
            }
            let columns = Int(((p.x - reach) / Self.side).rounded(.down))...Int(((p.x + reach) / Self.side).rounded(.down))
            let rows = Int(((p.z - reach) / Self.side).rounded(.down))...Int(((p.z + reach) / Self.side).rounded(.down))
            for column in columns {
                for row in rows {
                    for (a, b) in squares?[Self.square(column, row)] ?? [] where Map3DRoadMarkings.distance(p, toSegment: a, b) <= reach {
                        return true
                    }
                }
            }
            return false
        }
    }

    /// How far `p` is from the segment `a`–`b`, metres.
    static func distance(_ p: Map3DBaseMap.Point, toSegment a: Map3DBaseMap.Point, _ b: Map3DBaseMap.Point) -> Double {
        let dx = b.x - a.x, dz = b.z - a.z, length = dx * dx + dz * dz
        let t = length > 1e-12 ? min(1, max(0, ((p.x - a.x) * dx + (p.z - a.z) * dz) / length)) : 0
        return distance(p, Map3DBaseMap.Point(x: a.x + dx * t, z: a.z + dz * t))
    }

    /// The marks, signals and crossings of a junction of `arms`, as its
    /// `layout` has them (decision 846).
    private mutating func add(_ arms: [Arm], group: Int, layout: Layout = .signals) {
        let outs = arms.map { $0.place(min(6, $0.length))?.out ?? Map3DBaseMap.Point(x: 1, z: 0) }
        if region.hasStreetNameSigns, layout != .bare { addStreetNames(arms, outs: outs) }
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
            // Decision 732: none in Hong Kong.
            let boxed = region.hasScooterBoxes && arm.half >= Self.scooterBoxHalf
            let front = crosswalk + Self.crosswalkDepth / 2 + Self.stopGap
            let stop = front + (boxed ? Self.scooterBoxDepth : 0) + Self.stopDepth / 2
            let arrow = stop + Self.stopDepth / 2 + Self.arrowGap + Self.arrowLength / 2
            let length = arm.length
            // The centre line stops where the crossing starts.
            let cut = min(length, crosswalk + Self.crosswalkDepth / 2)
            cuts[arm.road, default: []].append(arm.forward ? arm.at...(arm.at + cut) : (arm.at - cut)...arm.at)
            switch layout {
            case .signals:
                break
            case .ring(let along):
                // Decision 846: the ring itself unmarked; a road coming in
                // its crossing, clear of the ring.
                guard !along.contains(number), length >= crosswalk + Self.crosswalkDepth + 4, let zebra = arm.place(crosswalk) else { continue }
                marks.append(Mark(kind: .crosswalk, centre: zebra.point, along: Map3DBaseMap.Point(x: -zebra.out.x, z: -zebra.out.z),
                                  length: Self.crosswalkDepth, width: 2 * arm.half, onDeck: arm.onDeck))
                // Decision 846's second later note: Finland's give-way
                // line across the lanes coming in, at the ring's edge.
                if region.paintsGiveWayLines {
                    addGiveWay(arm, at: clear)
                }
                // Decision 846's later note: Finland's sign at the
                // crossing, on the pavement where each way's traffic
                // reaches it, on the side that traffic keeps to.
                if region.hasFinnishFurniture {
                    let kerb = arm.half + max(0.5, min(1, Double(Map3DScene.Builder.sidewalk(of: arm.kind)) * 0.3)), keep = Double(region.trafficSide)
                    for way in [Map3DBaseMap.Point(x: -zebra.out.x, z: -zebra.out.z), zebra.out] {
                        // Half a metre before the crossing's bars, the way
                        // that traffic comes.
                        let back = Self.crosswalkDepth / 2 + 0.5
                        let foot = Map3DBaseMap.Point(x: zebra.point.x - way.x * back - way.z * keep * kerb,
                                                      z: zebra.point.z - way.z * back + way.x * keep * kerb)
                        crossingSigns.append(CrossingSign(foot: foot, along: way))
                    }
                }
                continue
            case .bare:
                continue
            }
            // Room for the crossing and the stop line before the arm ends
            // (at its next junction, or the map's edge).
            guard length >= stop + Self.stopDepth + 8, let zebra = arm.place(crosswalk), let line = arm.place(stop) else { continue }
            let half = arm.half
            // The traffic coming in goes back along the arm; its right
            // (Taiwan keeps right) is the right of that. Decision 732:
            // in Hong Kong, which keeps left, its left: `right` is the
            // side the incoming traffic keeps to.
            func toward(_ out: Map3DBaseMap.Point) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: -out.x, z: -out.z) }
            let keep = Double(region.trafficSide)
            func right(_ way: Map3DBaseMap.Point) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: -way.z * keep, z: way.x * keep) }
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
                // through and left (decision 732: through and right in
                // Hong Kong).
                let lanes = half >= 5 ? 2 : 1, lane = half / Double(lanes)
                for index in 0..<lanes {
                    marks.append(Mark(kind: .arrow(left: lanes > 1 && index == 0, mirrored: region.keepsLeft), centre: moved(place.point, right(way), (Double(index) + 0.5) * lane),
                                      along: way, length: Self.arrowLength, width: Self.arrowWidth, onDeck: arm.onDeck))
                }
            }
            // The signal at the kerb by the stop line, on the pavement.
            let kerb = half + max(0.5, min(1, Double(Map3DScene.Builder.sidewalk(of: arm.kind)) * 0.3))
            let road: Map3DSignalTiming.Road = abs(Self.dot(outs[number], outs[main])) >= 0.7 ? .main : .cross
            signals.append(Signal(foot: moved(line.point, right(way), kerb), along: way, road: road, group: group))
            // Decision 596: the traffic coming in waits at the stop line; who
            // crosses here waits at the crossing's ends.
            stops.append(Stop(point: line.point, along: way, road: road, group: group))
            crossings.append(Crossing(centre: zebra.point, out: zebra.out, half: half, road: road == .main ? .cross : .main, group: group))
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

    /// Decision 846's third later note: at a junction of two or more named
    /// roads, a sign for each name, on the first of its arms (as the
    /// junction lists them): at the corner on that arm's left as one
    /// leaves the junction along it (the signals stand on the right of the
    /// traffic coming in, decision 846), ``streetNameBack`` past the
    /// crossing roads' kerbs and ``streetNameOut`` past its own; its plate
    /// along the road it names.
    private mutating func addStreetNames(_ arms: [Arm], outs: [Map3DBaseMap.Point]) {
        let names = arms.compactMap(\.name)
        guard Set(names).count >= 2 else { return }
        var done = Set<String>()
        for (number, arm) in arms.enumerated() {
            guard let name = arm.name, done.insert(name).inserted else { continue }
            var clear = 0.0
            for (other, crossing) in arms.enumerated() where other != number && Self.dot(outs[number], outs[other]) >= -0.9 {
                let sine = max(0.5, abs(outs[number].x * outs[other].z - outs[number].z * outs[other].x))
                clear = max(clear, crossing.half / sine)
            }
            let back = clear + Self.streetNameBack
            guard arm.length >= back + 2, let place = arm.place(back) else { continue }
            let keep = Double(region.trafficSide)
            // Left of the way out, where traffic keeps right.
            let left = Map3DBaseMap.Point(x: place.out.z * keep, z: -place.out.x * keep)
            let out = arm.half + Self.streetNameOut
            let foot = Map3DBaseMap.Point(x: place.point.x + left.x * out, z: place.point.z + left.z * out)
            // One a name round a junction drawn as several (a divided
            // road's two carriageways meet a road at two points).
            guard !streetNames.contains(where: { $0.name == name && Self.distance($0.foot, foot) < Self.streetNameApart }) else { continue }
            streetNames.append(StreetName(foot: foot, along: place.out, name: name))
        }
    }

    /// Decision 846's third later note: how far along its road from the
    /// crossing roads' kerbs a street name sign stands, and how far out
    /// from its own road's carriageway.
    static let streetNameBack = 1.2
    static let streetNameOut = 1.0
    /// How far apart two signs of one name stand at least.
    static let streetNameApart = 40.0

    /// Decision 846's second later note: the give-way line (Traficom's
    /// L2: triangles 0.5 m wide at the base and 0.6 m long, 0.3–0.5 m
    /// apart) across the lanes of `arm` that come into the ring, its
    /// triangles' bases `edge` metres out from the junction (the ring's
    /// kerb) and a little more. A road taken both ways: from its centre
    /// line to the kerb its incoming traffic keeps to; one taken only
    /// into the ring: kerb to kerb; one taken only out of it: none.
    private mutating func addGiveWay(_ arm: Arm, at edge: Double) {
        // Out from the junction with the road's points: the traffic of a
        // one-way road goes out.
        if arm.oneway && arm.forward { return }
        let middle = edge + Self.giveWayGap + Self.giveWayLength / 2
        guard arm.length >= middle + Self.giveWayLength, let place = arm.place(middle) else { return }
        let way = Map3DBaseMap.Point(x: -place.out.x, z: -place.out.z), keep = Double(region.trafficSide)
        let right = Map3DBaseMap.Point(x: -way.z * keep, z: way.x * keep)
        let inner = arm.oneway ? -arm.half + Self.giveWayInset : Self.giveWayInset, outer = arm.half - Self.giveWayInset
        // As many triangles as fit, the gaps shared out evenly.
        let count = Int(((outer - inner) + Self.giveWayGapAcross) / (Self.giveWayWidth + Self.giveWayGapAcross))
        guard count >= 1 else { return }
        let pitch = count > 1 ? (outer - inner - Self.giveWayWidth) / Double(count - 1) : 0
        for index in 0..<count {
            let across = count > 1 ? inner + Self.giveWayWidth / 2 + Double(index) * pitch : (inner + outer) / 2
            marks.append(Mark(kind: .giveWay, centre: Map3DBaseMap.Point(x: place.point.x + right.x * across, z: place.point.z + right.z * across),
                              along: way, length: Self.giveWayLength, width: Self.giveWayWidth, onDeck: arm.onDeck))
        }
        // Decision 846's fourth later note: and its sign on the pavement
        // beside the line, on the side the traffic coming in keeps to.
        if region.hasFinnishFurniture {
            let kerb = arm.half + max(0.5, min(1, Double(Map3DScene.Builder.sidewalk(of: arm.kind)) * 0.3))
            giveWaySigns.append(CrossingSign(foot: Map3DBaseMap.Point(x: place.point.x + right.x * kerb, z: place.point.z + right.z * kerb), along: way))
        }
    }

    /// Decision 846's second later note: the give-way line's triangles
    /// (Traficom, 2021, tiemerkintöjen mitoitus L2: base 0.5 m, length
    /// 0.6 m, 0.3–0.5 m apart), how far their bases stand back from the
    /// ring's kerb, and how far in from the kerb and the centre line the
    /// row stops.
    static let giveWayWidth = 0.5
    static let giveWayLength = 0.6
    static let giveWayGapAcross = 0.4
    static let giveWayGap = 0.3
    static let giveWayInset = 0.3

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
            case .giveWay:
                // Decision 846's second later note: a triangle, its point
                // back toward the traffic coming.
                addMark(mark, colour: Self.paint, layer: Map3DVertex.plain, u: (0, 1), v: (0, 1), pointed: true)
            case .arrow(let left, let mirrored):
                // Decision 732: mirrored, the layer read right to left.
                let u = left ? (0.5, 1.0) : (0, 0.5)
                addMark(mark, colour: Map3DPalette.road(.primary), layer: Float(Map3DSurface.laneArrows.rawValue),
                        u: mirrored ? (u.1, u.0) : u, v: (0, 1))
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
    /// Decision 846's second later note: `pointed`, a triangle, from a
    /// point at its back end to its full width at its front.
    private mutating func addMark(_ mark: Map3DRoadMarkings.Mark, colour: UInt32, layer: Float, u: (Double, Double), v: (Double, Double),
                                  pointed: Bool = false) {
        let along = mark.along, right = Map3DBaseMap.Point(x: -along.z, z: along.x)
        let halfLength = mark.length / 2, halfWidth = mark.width / 2
        func texture(_ p: Map3DBaseMap.Point) -> (Float, Float) {
            let dx = p.x - mark.centre.x, dz = p.z - mark.centre.z
            let across = (dx * right.x + dz * right.z) / mark.width + 0.5
            let forth = (dx * along.x + dz * along.z) / mark.length + 0.5
            return (Float(u.0 + (u.1 - u.0) * across), Float(v.0 + (v.1 - v.0) * (1 - forth)))
        }
        // Decision 391: none on a bridge's deck (a junction there is rare),
        // at the road's height on a ramp; decision 375: none where the road
        // gives way to a trench. Review H6: on its own road's deck only, not
        // one over it. Review K2-3: a long one (a kerb line, a walkway) cut
        // where the road's rise bends, as the road is
        // (``addStrip(_:bounds:width:lift:color:paint:water:raised:onDeck:taking:)``),
        // each piece's ends at the road's height there and each piece left
        // out on its own.
        let way = (mark.along.x, mark.along.z)
        let back = Map3DBaseMap.Point(x: mark.centre.x - along.x * halfLength, z: mark.centre.z - along.z * halfLength)
        let front = Map3DBaseMap.Point(x: mark.centre.x + along.x * halfLength, z: mark.centre.z + along.z * halfLength)
        func at(_ t: Double) -> Map3DBaseMap.Point { Map3DBaseMap.Point(x: back.x + (front.x - back.x) * t, z: back.z + (front.z - back.z) * t) }
        // Decision 865: and where its road's bed bends.
        let cuts = merged(merged([0, 1], raisedCuts(from: back, to: front, anchor: mark.anchor ?? back, along: way, onDeck: mark.onDeck)),
                          bedCuts(from: back, to: front, along: way, onDeck: mark.onDeck))
        for (t0, t1) in zip(cuts, cuts.dropFirst()) where t1 - t0 > 1e-9 {
            let middle = at((t0 + t1) / 2)
            guard !roadRise(at: middle, along: way, onDeck: mark.onDeck).onBridge, !givesWay(at: middle, along: way) else { continue }
            let riseA = roadRise(at: at(t0), along: way, onDeck: mark.onDeck).rise, riseB = roadRise(at: at(t1), along: way, onDeck: mark.onDeck).rise
            let from = (t0 - 0.5) * mark.length, to = (t1 - 0.5) * mark.length
            // How wide it is at `b` along it, of its half width.
            func share(_ b: Double) -> Double { pointed ? min(1, max(0, (b + halfLength) / mark.length)) : 1 }
            var corners = [(-share(from), from), (share(from), from), (share(to), to), (-share(to), to)].map { a, b in
                Map3DBaseMap.Point(x: mark.centre.x + right.x * a * halfWidth + along.x * b,
                                   z: mark.centre.z + right.z * a * halfWidth + along.z * b)
            }
            // A triangle's point: one corner, not two.
            if share(from) == 0 { corners.removeFirst() }
            // The rise at a point of the piece, from its back end's to its front's.
            func lift(_ p: Map3DBaseMap.Point) -> Float {
                let share = to - from > 1e-9 ? (((p.x - mark.centre.x) * along.x + (p.z - mark.centre.z) * along.z) - from) / (to - from) : 0
                return Self.centreLineLift + riseA + (riseB - riseA) * Float(min(1, max(0, share)))
            }
            // Decision 865: on its road's bed, level across, from its back
            // end's height to its front's.
            var bed: ((Map3DBaseMap.Point) -> Float)?
            if let bedA = roadBed.level(at: at(t0), along: way, onDeck: mark.onDeck), let bedB = roadBed.level(at: at(t1), along: way, onDeck: mark.onDeck) {
                bed = { p in
                    let share = to - from > 1e-9 ? (((p.x - mark.centre.x) * along.x + (p.z - mark.centre.z) * along.z) - from) / (to - from) : 0
                    return bedA + (bedB - bedA) * Float(min(1, max(0, share)))
                }
            }
            addMarkPiece(corners, colour: colour, layer: layer, texture: texture, lift: lift, bed: bed)
        }
    }

    /// The quadrilateral `corners` of a mark laid on the drawn ground,
    /// `lift(p)` over it, cut at the ground's grid lines and diagonals.
    /// A mark's piece `points` (convex), each triangle facing up.
    private static func addMarkFan(_ points: [Map3DVertex], to mesh: inout Map3DMesh) {
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

    /// Decision 865: on `bed` when given (its road's bed, the height at
    /// each point), in one piece.
    private mutating func addMarkPiece(_ corners: [Map3DBaseMap.Point], colour: UInt32, layer: Float,
                                       texture: (Map3DBaseMap.Point) -> (Float, Float), lift: (Map3DBaseMap.Point) -> Float,
                                       bed: ((Map3DBaseMap.Point) -> Float)? = nil) {
        if let bed {
            let points = corners.map { p -> Map3DVertex in
                let (tu, tv) = texture(p)
                return Map3DVertex(Map3DPoint(Float(p.x), bed(p) + lift(p), Float(p.z)), normal: .up, color: colour, u: tu, v: tv, layer: layer)
            }
            let middle = Map3DPoint(Float(corners.map(\.x).reduce(0, +) / Double(corners.count)), 0, Float(corners.map(\.z).reduce(0, +) / Double(corners.count)))
            mesh(at: middle) { mesh in Self.addMarkFan(points, to: &mesh) }
            return
        }
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
                        return Map3DVertex(Map3DPoint(x, drawnGround(x: x, z: z) + lift(p), z), normal: .up, color: colour, u: tu, v: tv, layer: layer)
                    }
                    let middle = Map3DPoint(Float((west + east) / 2), 0, Float((top + bottom) / 2))
                    mesh(at: middle) { mesh in Self.addMarkFan(points, to: &mesh) }
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
            // Decision 732: Hong Kong's own on its map. Decision 846: and
            // on Finland's, whose signals stand at the kerb too.
            // Its later note: Finland's own, where the pack has them.
            let finland = markings.region.hasFinnishFurniture ? Self.finlandSignals[signal.road] : nil
            let hongKong = markings.region.standsSignalsAtKerb ? Self.hongKongSignals[signal.road] : nil
            guard let model = finland ?? hongKong ?? Self.propModels[signal.road == .main ? .signalGo : .signalStop] else { continue }
            place(model, at: signal.foot, forward: signal.along, clearing: 1.5, tint: Map3DColor.rgb(0xFFFFFF), group: signal.group)
        }
        // Decision 846's later note: Finland's sign at a crossing with no
        // signal, looking at the traffic that comes to it.
        if let model = Self.finlandModels[.crossingSign] {
            for sign in markings.crossingSigns {
                place(model, at: sign.foot, forward: sign.along, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF))
            }
        }
        // Decision 846's fourth later note: the give-way sign where a road
        // comes to a roundabout.
        if let model = Self.finlandModels[.giveWaySign] {
            for sign in markings.giveWaySigns {
                place(model, at: sign.foot, forward: sign.along, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF))
            }
        }
        // Decision 445: each pedestrian signal its face and its countdown's
        // two digits, in one place, looking across the road (the model
        // looks toward its left).
        if let walking = Self.walkModels {
            let placed = walking.placed
            // Decision 846: Hong Kong's and Finland's the two lights alone,
            // with no countdown.
            let countdown = markings.region.hasCountdownBoxes
            for walk in markings.walks {
                let forward = Map3DBaseMap.Point(x: -walk.facing.z, z: walk.facing.x), group = Map3DPedestrianSignal.group(walk.group, road: walk.road)
                guard countdown else {
                    place(walking.placedPlain(markings.region), at: walk.foot, forward: forward, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF), group: group)
                    continue
                }
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
                    // Decision 846's later note: Finland's stop is its sign
                    // on a post by the kerb, with no shelter of Taiwan's.
                    let finnish = markings.region.hasFinnishFurniture ? Self.finlandModels[.busStop] : nil
                    let sheltered = pavement >= 2.5 && finnish == nil
                    if let finnish {
                        place(finnish, at: out(width / 2 + 0.45, ahead: -1.5), forward: forward, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF),
                              onDeck: road.bridgeLevel > 0)
                        // Decision 846's fourth later note: and its glass
                        // shelter beside the sign where the pavement is
                        // wide enough, open toward the road, its back at
                        // the pavement's back.
                        if pavement >= Self.finnishShelterPavement, let shelter = Self.finlandModels[.shelter] {
                            place(shelter, at: out(width / 2 + pavement - Self.finnishShelterBack, ahead: Self.finnishShelterAhead), forward: forward,
                                  clearing: 2.6, tint: Map3DColor.rgb(0xFFFFFF), onDeck: road.bridgeLevel > 0)
                        }
                    } else if sheltered, let model = Self.propModels[.busStop] {
                        // The shelter stands back from the kerb.
                        place(model, at: out(width / 2 + pavement - 1.05), forward: forward, clearing: 3, tint: Map3DColor.rgb(0xFFFFFF),
                              onDeck: road.bridgeLevel > 0)
                    } else if !sheltered, let model = Self.sceneryModels[.busStopPole] {
                        // Decision 467: the sign alone, by the kerb.
                        place(model, at: out(width / 2 + 0.45, ahead: -1.5), forward: forward, clearing: 1, tint: Map3DColor.rgb(0xFFFFFF),
                              onDeck: road.bridgeLevel > 0)
                    }
                    // Decision 467: post boxes by some of the stops, at the
                    // back of the pavement, clear of the shelter's sign
                    // (2.75 m along it) on the other side from the vending
                    // machine.
                    // Decision 743: not in Hong Kong.
                    if streetLife.region.hasTaiwanPostBoxes, map3DRandom(seed.0, seed.1, salt: 358) < Self.postBoxShare,
                       let model = Self.sceneryModels[.postBoxes] {
                        place(model, at: out(width / 2 + pavement - 0.4, ahead: sheltered ? -3.6 : -3), forward: forward, clearing: 1.2,
                              tint: Map3DColor.rgb(0xFFFFFF), onDeck: road.bridgeLevel > 0)
                    }
                    if sheltered {
                        guard map3DRandom(seed.0, seed.1, salt: 356) < 0.4 else { continue }
                    }
                    // Decision 846: none in Finland.
                    if markings.region.hasVendingMachines, let model = Self.propModels[.vending] {
                        let tint = Self.pick(Self.vendingColours, map3DRandom(seed.0, seed.1, salt: 357))
                        place(model, at: out(width / 2 + pavement - 0.6, ahead: pavement >= 2.5 ? 3.4 : 0), forward: forward, clearing: 1.2, tint: tint,
                              onDeck: road.bridgeLevel > 0)
                    }
                }
            }
        }
    }

    /// Decision 846's fourth later note: Finland's shelter stands where the
    /// pavement is this wide, metres, its middle this far in from the
    /// pavement's back (half its 1.8 m depth and a little) and this far on
    /// from the stop's sign (clear of the sign 1.5 m back and of its 4.7 m
    /// length).
    static let finnishShelterPavement = 2.5
    static let finnishShelterBack = 1.0
    static let finnishShelterAhead = 2.2

    /// Decision 732: Hong Kong's traffic signals' models in
    /// ``Map3DModelPack/standard``, by the road they face (each placed as
    /// it shows while the lights do not change).
    static let hongKongSignals: [Map3DSignalTiming.Road: Int] = Dictionary(uniqueKeysWithValues: [Map3DSignalTiming.Road.main, .cross].compactMap { road in
        Map3DModelCatalog.standard.index(of: Map3DHongKongSignal.placedName(road)).map { (road, $0) }
    })

    /// Decision 846's later note: Finland's street furniture's models in
    /// ``Map3DModelPack/standard``, and its signals' by the road they face
    /// (as ``hongKongSignals``).
    static let finlandModels: [Map3DFinlandStreet.Unit: Int] = Dictionary(uniqueKeysWithValues: Map3DFinlandStreet.Unit.allCases.compactMap { unit in
        Map3DModelCatalog.standard.index(of: unit.rawValue).map { (unit, $0) }
    })
    static let finlandSignals: [Map3DSignalTiming.Road: Int] = Dictionary(uniqueKeysWithValues: [Map3DSignalTiming.Road.main, .cross].compactMap { road in
        Map3DModelCatalog.standard.index(of: Map3DFinlandStreet.placedName(road)).map { (road, $0) }
    })

    /// Decision 445: the pedestrian signals' models in ``Map3DModelPack/standard``.
    /// Decision 820: from ``Map3DModelCatalog``, not waiting for the pack.
    static let walkModels = Map3DPedestrianSignal.Models(index: Map3DModelCatalog.standard.index(of:))

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

    /// Decision 467: how many of the stops have a pair of post boxes by
    /// them.
    static let postBoxShare: Float = 0.3

    /// The vending machines' bodies (props.js `VENDING_BODY`), in the
    /// palette's softer tones: white, red, blue, cream.
    /// Decision 370: in the model look (``Map3DLook``).
    static let vendingColours: [UInt32] = [0xECEDEA, 0xC8433F, 0x3F6FA8, 0xE8DDBF].map { Map3DLook.colour(Map3DColor.rgb($0)) }

    /// `model` standing on the pavement at `at`, its left toward the road
    /// along level `forward`, no tree, light or pole within `clearing`
    /// metres of it.
    /// The trees, street lights and poles within `clearing` of `foot`
    /// taken away, for what stands there.
    private mutating func clearStreetFurniture(at foot: Map3DPoint, within clearing: Float) {
        let key = key(of: foot)
        let streetFurniture = Set([Map3DProp.tree, .lamp, .pole].compactMap { Self.propModels[$0] } + [Self.finlandModels[.lamp]].compactMap { $0 })
        props[key] = props[key]?.filter { instance in
            guard streetFurniture.contains(instance.model) else { return true }
            let dx = instance.transform[12] - foot.x, dz = instance.transform[14] - foot.z
            return dx * dx + dz * dz >= clearing * clearing
        }
    }

    /// Decision 846's third later note: the street name signs of
    /// `markings`, in the closest detail: a galvanised post, on top of it a
    /// blue plate along the road it names with a thin white edge and the
    /// name in white on both faces (``Map3DBoardGlyphs``, decision 882),
    /// as long as the name needs, up to ``streetNamePlateLongest``.
    mutating func addStreetNameSigns(_ markings: Map3DRoadMarkings) {
        let kept = target
        target = .close
        defer { target = kept }
        for sign in markings.streetNames {
            guard roadRise(at: sign.foot, along: nil, onDeck: false).rise < Self.propRise,
                  let along = Map3DPoint(Float(sign.along.x), 0, Float(sign.along.z)).normalized else { continue }
            let text = Map3DBoardGlyphs.layout(sign.name)
            guard text.width > 0 else { continue }
            let foot = Map3DPoint(Float(sign.foot.x), roadGround(at: sign.foot, onDeck: false, beyond: 2.5) + Self.sidewalkLift, Float(sign.foot.z))
            clearStreetFurniture(at: foot, within: 1)
            mesh(at: foot) { mesh in Self.addStreetNameSign(&mesh, foot: foot, along: along, text: text) }
        }
    }

    /// Decision 846's third later note: a street name sign's sizes,
    /// metres: Finland's plates (Rovaniemi's, on their own post at the
    /// corner) about 0.3 m tall, as long as the name, the letters about
    /// two thirds of it; the plate's foot at 2.3 m.
    static let streetNamePlateHeight: Float = 0.3
    static let streetNamePlateDepth: Float = 0.03
    static let streetNamePlateFoot: Float = 2.3
    static let streetNamePlateLongest: Float = 1.4
    static let streetNamePlateShortest: Float = 0.5
    static let streetNameLetters: Float = 0.2
    static let streetNameEdge: Float = 0.02
    static let streetNameMargin: Float = 0.06

    /// One street name sign at `foot`, its plate along `along`.
    static func addStreetNameSign(_ mesh: inout Map3DMesh, foot: Map3DPoint, along: Map3DPoint,
                                  text: (width: Int, rectangles: [Map3DBoardGlyphs.Rectangle])) {
        let grid = Float(Map3DBoardGlyphs.grid)
        let cell = min(streetNameLetters / grid, (streetNamePlateLongest - 2 * streetNameMargin) / Float(text.width))
        let length = max(streetNamePlateShortest, Float(text.width) * cell + 2 * streetNameMargin)
        let height = streetNamePlateHeight, depth = streetNamePlateDepth
        mesh.addBox(base: foot, forward: along, length: 0.06, width: 0.06, height: streetNamePlateFoot + height,
                    top: Map3DPalette.steel, side: Map3DPalette.steel)
        let plate = foot + Map3DPoint(0, streetNamePlateFoot, 0)
        mesh.addBox(base: plate, forward: along, length: length, width: depth, height: height, top: Map3DPalette.canopy, side: Map3DPalette.canopy)
        // Each face: its white edge and the name, a little proud of it.
        for side: Float in [1, -1] {
            let out = Map3DPoint(-along.z * side, 0, along.x * side)
            // The reader, facing the plate, reads to their right.
            let right = Map3DPoint(out.z, 0, -out.x)
            let face = plate + out * (depth / 2 + 0.004)
            func quad(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) {
                func corner(_ x: Float, _ y: Float) -> Map3DPoint { face + right * x + Map3DPoint(0, y, 0) }
                mesh.addQuad(corner(x0, y0), corner(x1, y0), corner(x1, y1), corner(x0, y1), color: Map3DPalette.sidewalk)
            }
            let half = length / 2, edge = streetNameEdge, inset: Float = 0.015
            quad(-half + inset, height - inset - edge, half - inset, height - inset)
            quad(-half + inset, inset, half - inset, inset + edge)
            quad(-half + inset, inset + edge, -half + inset + edge, height - inset - edge)
            quad(half - inset - edge, inset + edge, half - inset, height - inset - edge)
            let left = -Float(text.width) * cell / 2, top = height / 2 + grid * cell / 2
            for r in text.rectangles {
                let x0 = left + Float(r.x) * cell, y1 = top - Float(r.y) * cell
                quad(x0, y1 - Float(r.height) * cell, x0 + Float(r.width) * cell, y1)
            }
        }
    }

    private mutating func place(_ model: Int, at: Map3DBaseMap.Point, forward: Map3DBaseMap.Point, clearing: Float, tint: UInt32,
                                onDeck: Bool = false, group: Int = 0) {
        // Decision 391: none on a bridge or its ramp.
        guard roadRise(at: at, along: nil, onDeck: onDeck).rise < Self.propRise else { return }
        let x = Float(at.x), z = Float(at.z)
        // Decision 865: on the road's bed.
        let foot = Map3DPoint(x, roadGround(at: at, onDeck: onDeck, beyond: 2.5) + Self.sidewalkLift, z)
        let key = key(of: foot)
        clearStreetFurniture(at: foot, within: clearing)
        var instance = Map3DInstance.prop(model, at: foot, forward: Map3DPoint(Float(forward.x), 0, Float(forward.z)), scale: 1, tint: tint)
        instance.group = group
        props[key, default: []].append(instance)
    }
}
