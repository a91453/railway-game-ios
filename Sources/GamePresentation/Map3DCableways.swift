import Foundation
import GameCore

// Decision 575 續 (CABLEMAP): the player's cable cars in the 3D map. Each
// stop's hall stands on the ground at its cell's middle, towers stand
// evenly along each span (no farther apart than ``towerSpacing``), the two
// ropes hang between them a little sagged, and the cabins of
// ``CablewayCabins`` ride them: outbound on the rope to the right of the
// way to the last stop, back on the other. Decision 358's rule for what is
// far: whole near the eye, the far model farther, nothing beyond; the
// cabins in front of the camera and nearest first, at most
// ``mostNearCabins`` near and ``mostFarCabins`` far (Maokong's 184 cabins
// all near would be some 590,000 triangles).
//
// Laid once for a world's cable cars and a scene (``init(world:scene:)``),
// then asked each frame (``instances(second:eye:target:reach:)``): no
// state kept between frames.

/// Decision 583 (CABLEFOLLOW): one cabin of a player's cable car: the
/// same cabin from one moment to the next (``CablewayCabins/Cabin/number``).
public struct CabinID: Hashable, Sendable {
    public let cableway: CablewayID
    public let number: Int

    public init(cableway: CablewayID, number: Int) {
        self.cableway = cableway
        self.number = number
    }
}

/// The player's cable cars laid in a 3D scene.
public struct Map3DCableways: Sendable {
    /// One stop's hall: where its foot is, the way its +x points, its kind.
    struct Hall: Sendable {
        let foot: Map3DPoint
        let along: Map3DPoint
        let kind: Map3DCableCar.Station
    }

    /// One span: its supports' rope points (the middle line between the
    /// two ropes, the first and last in the halls), evenly apart; the
    /// towers' feet between; the way along it and its left.
    struct Span: Sendable {
        let supports: [Map3DPoint]
        let towers: [Map3DPoint]
        let along: Map3DPoint
        let left: Map3DPoint
    }

    struct Line: Sendable {
        let id: CablewayID
        let cableway: Cableway
        let halls: [Hall]
        let spans: [Span]
    }

    let lines: [Line]
    let world: GameWorld
    /// The cable cars it was laid from, to know when to lay them again.
    public let cableways: [Cableway]

    /// The farthest apart two towers stand: Maokong's 47 towers over some
    /// 4 km are about 85 m apart.
    public static let towerSpacing: Float = 90
    /// How far the rope sags between two supports, of their distance.
    public static let sagShare: Float = 0.012
    /// Within this of the eye a cabin, tower or hall is drawn whole
    /// (decision 417's far models come nearer on a weak device: `reach`).
    public static let nearReach: Float = 350
    /// Within this the far models, and the ropes; beyond, nothing.
    public static let farReach: Float = 1_600
    /// The most cabins drawn whole and far in a frame: 24 × 3,268 and
    /// 60 × 1,632 triangles at most, about 176,000.
    public static let mostNearCabins = 24
    public static let mostFarCabins = 60
    /// The most cabins drawn in a station's side at once, a cabin length
    /// and a gap apart (while the cable car stands still, half its cabins
    /// wait in each end hall).
    public static let mostInHall = 5
    /// How many pieces a rope between two supports is drawn in.
    public static let ropePieces = 6

    public init(world: GameWorld, scene: Map3DScene) {
        self.world = world
        cableways = world.cableways
        func foot(_ plan: PlanPoint) -> Map3DPoint {
            let flat = scene.point(worldX: Double(plan.x), worldY: Double(plan.y), height: 0)
            return Map3DPoint(flat.x, scene.drawnGround.height(x: flat.x, z: flat.z, world: world), flat.z)
        }
        lines = world.cableways.compactMap { cableway in
            guard cableway.stops.count >= 2 else { return nil }
            let feet = cableway.stops.map { foot($0.cell.middle) }
            func direction(_ leg: Int) -> Map3DPoint {
                let d = feet[leg + 1] - feet[leg]
                return Map3DPoint(d.x, 0, d.z).normalized ?? Map3DPoint(1, 0, 0)
            }
            let last = feet.count - 1
            let halls = feet.indices.map { stop -> Hall in
                if stop == 0 { return Hall(foot: feet[0], along: -direction(0), kind: .terminal) }
                if stop == last { return Hall(foot: feet[last], along: direction(last - 1), kind: .terminal) }
                let both = direction(stop - 1) + direction(stop)
                let along = Map3DPoint(both.x, 0, both.z).normalized ?? direction(stop)
                return cableway.stops[stop].boards ? Hall(foot: feet[stop], along: along, kind: .through)
                    : Hall(foot: feet[stop], along: direction(stop - 1), kind: .corner)
            }
            let spans = (0..<last).map { leg -> Span in
                let a = feet[leg], b = feet[leg + 1]
                let along = direction(leg), left = Map3DPoint(along.z, 0, -along.x)
                let flat = Map3DPoint(b.x - a.x, 0, b.z - a.z).length
                let pieces = max(1, Int((flat / Self.towerSpacing).rounded(.up)))
                var supports = [a + Map3DPoint(0, Map3DCableCar.stationRopeHeight, 0)]
                var towers: [Map3DPoint] = []
                for i in 1..<pieces {
                    let t = Float(i) / Float(pieces)
                    let p = a + (b - a) * t
                    let tower = Map3DPoint(p.x, scene.drawnGround.height(x: p.x, z: p.z, world: world), p.z)
                    towers.append(tower)
                    supports.append(tower + Map3DPoint(0, Map3DCableCar.ropeHeight(ofTower: Map3DCableCar.towerHeight), 0))
                }
                supports.append(b + Map3DPoint(0, Map3DCableCar.stationRopeHeight, 0))
                return Span(supports: supports, towers: towers, along: along, left: left)
            }
            return Line(id: cableway.id, cableway: cableway, halls: halls, spans: spans)
        }
    }

    /// Whether there is anything to draw.
    public var isEmpty: Bool { lines.isEmpty }

    /// The rope's middle line `share` (0–1) along `span`, sagging between
    /// supports.
    static func ropePoint(_ span: Span, share: Float) -> Map3DPoint {
        let pieces = span.supports.count - 1
        let at = min(max(share, 0), 1) * Float(pieces)
        let i = min(Int(at), pieces - 1), s = at - Float(i)
        let a = span.supports[i], b = span.supports[i + 1]
        let sag = Map3DPoint(b.x - a.x, 0, b.z - a.z).length * sagShare
        return a + (b - a) * s + Map3DPoint(0, -4 * sag * s * (1 - s), 0)
    }

    /// Model `index` at `point` facing `along` (horizontal), as a prop.
    static func placed(_ index: Int, at point: Map3DPoint, along: Map3DPoint) -> Map3DInstance {
        .prop(index, at: point, forward: along, scale: 1, tint: 0xFFFFFF)
    }

    /// A rope from `a` to `b`: the metre of rope stretched.
    static func rope(_ index: Int, from a: Map3DPoint, to b: Map3DPoint, left: Map3DPoint) -> Map3DInstance {
        let x = b - a
        let z = (x.cross(left)).normalized ?? Map3DPoint(0, 1, 0)
        return Map3DInstance(model: index, transform: [x.x, x.y, x.z, 0, left.x, left.y, left.z, 0, z.x, z.y, z.z, 0, a.x, a.y, a.z, 1],
                             stripe: (1, 1, 1))
    }

    /// The models' indices in `pack`, or `nil` when it lacks any.
    struct Models {
        let cabin: [Map3DCableCar.Cabin: (near: Int, far: Int)]
        let tower: (near: Int, far: Int)
        let hall: [Map3DCableCar.Station: (near: Int, far: Int)]
        let rope: Int

        init?(_ pack: Map3DModelPack) {
            func pair(_ name: String) -> (near: Int, far: Int)? {
                guard let near = pack.index(of: name), let far = pack.index(of: name + "-far") else { return nil }
                return (near, far)
            }
            var cabin: [Map3DCableCar.Cabin: (near: Int, far: Int)] = [:]
            for kind in Map3DCableCar.Cabin.allCases {
                guard let p = pair("cablecar-cabin-" + kind.rawValue) else { return nil }
                cabin[kind] = p
            }
            var hall: [Map3DCableCar.Station: (near: Int, far: Int)] = [:]
            for kind in Map3DCableCar.Station.allCases {
                guard let p = pair("cablecar-station-" + kind.rawValue) else { return nil }
                hall[kind] = p
            }
            guard let tower = pair("cablecar-tower"), let rope = pack.index(of: "cablecar-rope") else { return nil }
            self.cabin = cabin
            self.tower = tower
            self.hall = hall
            self.rope = rope
        }
    }

    /// One frame's cable cars.
    public struct Frame: Sendable {
        public var instances: [Map3DInstance] = []
        /// The cabins drawn whole, and far.
        public var nearCabins = 0
        public var farCabins = 0
    }

    /// Everything seen from `eye` looking at `target` at game second
    /// `second` (since the game began), with `pack`'s models; `reach`
    /// brings the near models nearer (``Map3DModelReach/farModel``).
    ///
    /// Decision 583 (CABLEFOLLOW): the cabin `following` is drawn whole
    /// wherever it is, first, at its ``pose(of:second:)``; and with
    /// `ahead` (the way the followed cabin runs, level), what counts as
    /// behind is behind it on its way, not behind the camera, so the
    /// cabins it runs towards come first even while the window view looks
    /// out at the side.
    public func frame(second: Double, eye: Map3DPoint, target: Map3DPoint, pack: Map3DModelPack, reach: Float = 1,
                      following: CabinID? = nil, ahead: Map3DPoint? = nil) -> Frame {
        var frame = Frame()
        guard !lines.isEmpty, let models = Models(pack) else { return frame }
        let near = Self.nearReach * reach, far = Self.farReach
        let look = ahead.flatMap { Map3DPoint($0.x, 0, $0.z).normalized } ?? Map3DPoint(target.x - eye.x, 0, target.z - eye.z).normalized
        var followed: CabinID?
        if let following, let pose = pose(of: following, second: second),
           let pair = models.cabin[Self.isCrystal(following.number) ? .crystal : .standard] {
            frame.instances.append(Self.placed(pair.near, at: pose.rail, along: pose.forward))
            frame.nearCabins += 1
            followed = following
        }
        /// How far `p` counts as: its distance, three times it behind the
        /// camera.
        func weight(_ p: Map3DPoint) -> Float {
            let d = (p - eye).length
            guard let look, Map3DPoint(p.x - eye.x, 0, p.z - eye.z).dot(look) < 0 else { return d }
            return d * 3
        }
        let whole = Int64(second.rounded(.down))
        var cabins: [(weight: Float, distance: Float, point: Map3DPoint, along: Map3DPoint, kind: Map3DCableCar.Cabin)] = []
        for line in lines {
            for hall in line.halls {
                let d = (hall.foot - eye).length
                guard d < far, let pair = models.hall[hall.kind] else { continue }
                frame.instances.append(Self.placed(d < near ? pair.near : pair.far, at: hall.foot, along: hall.along))
            }
            for span in line.spans {
                for tower in span.towers {
                    let d = (tower - eye).length
                    guard d < far else { continue }
                    frame.instances.append(Self.placed(d < near ? models.tower.near : models.tower.far, at: tower, along: span.along))
                }
                for side: Float in [-1, 1] {
                    let offset = span.left * (side * Map3DCableCar.ropeSpacing / 2)
                    for support in 0..<(span.supports.count - 1) {
                        let first = Float(support) / Float(span.supports.count - 1)
                        let share = 1 / Float(span.supports.count - 1)
                        let middle = Self.ropePoint(span, share: first + share / 2)
                        guard (middle - eye).length < far else { continue }
                        var from = Self.ropePoint(span, share: first)
                        for piece in 1...Self.ropePieces {
                            let to = Self.ropePoint(span, share: first + share * Float(piece) / Float(Self.ropePieces))
                            frame.instances.append(Self.rope(models.rope, from: from + offset, to: to + offset, left: span.left))
                            from = to
                        }
                    }
                }
            }
            let open = CablewayCabins.runs(line.id, in: world, at: GameTime(seconds: whole))
            var inHall: [Int: Int] = [:]
            for cabin in CablewayCabins.cabins(of: line.cableway, atSecond: whole, open: open)
                where followed != CabinID(cableway: line.id, number: cabin.number) {
                let point: Map3DPoint, along: Map3DPoint
                switch cabin.place {
                case .span(let leg, let permille, let outbound):
                    let span = line.spans[leg]
                    // Within the permille, the fraction of a second the
                    // clock has gone on, so cabins glide.
                    let seconds = Float(CablewayCabins.spanSeconds(line.cableway.legMetres[leg]))
                    let glide = Float(second - Double(whole)) / max(seconds, 1) * (outbound ? 1 : -1)
                    let share = Float(permille) / 1_000 + glide
                    along = outbound ? span.along : -span.along
                    point = Self.ropePoint(span, share: share) + span.left * ((outbound ? -1 : 1) * Map3DCableCar.ropeSpacing / 2)
                case .station(let stop, let outbound):
                    let key = stop * 2 + (outbound ? 1 : 0)
                    let slot = inHall[key, default: 0]
                    inHall[key] = slot + 1
                    guard slot < Self.mostInHall else { continue }
                    let hall = line.halls[stop]
                    // On the rope to the right of the way it goes on; in
                    // an end hall facing the line it turns back to.
                    let left = Map3DPoint(hall.along.z, 0, -hall.along.x)
                    let side: Float = (stop == 0) == outbound ? 1 : -1
                    along = hall.kind == .terminal || !outbound ? -hall.along : hall.along
                    let step = (Float(slot) - Float(Self.mostInHall - 1) / 2) * (Map3DCableCar.cabinLength + 1.4)
                    point = hall.foot + Map3DPoint(0, Map3DCableCar.stationRopeHeight, 0) + left * (side * Map3DCableCar.ropeSpacing / 2)
                        + hall.along * (step - (hall.kind == .terminal ? 3.4 : 0))
                }
                let d = (point - eye).length
                guard d < far else { continue }
                cabins.append((weight(point), d, point, along, cabin.crystal ? .crystal : .standard))
            }
        }
        cabins.sort { $0.weight < $1.weight }
        for cabin in cabins {
            guard let pair = models.cabin[cabin.kind] else { continue }
            if cabin.distance < near, frame.nearCabins < Self.mostNearCabins {
                frame.instances.append(Self.placed(pair.near, at: cabin.point, along: cabin.along))
                frame.nearCabins += 1
            } else if frame.farCabins < Self.mostFarCabins {
                frame.instances.append(Self.placed(pair.far, at: cabin.point, along: cabin.along))
                frame.farCabins += 1
            }
        }
        return frame
    }

    // MARK: - Following a cabin (decision 583)

    static func isCrystal(_ number: Int) -> Bool { CablewayCabins.isCrystal(number) }

    /// Decision 583: a cabin body's height over its floor, for the view
    /// beside it (the cabin of #1791, about 2 m).
    public static let cabinHeight: Float = 2
    /// Decision 583: the window view's seat in a cabin: a seated eye
    /// 1.15 m over the floor, 0.45 m in from the middle towards the left
    /// side, so the walls, the floor and the hanger by it stand within the
    /// near plane (1.2 m, ``Map3DCamera/depthRange``) and are not drawn
    /// over the view. Looking a little down from the rope's height; from a
    /// crystal cabin a little more, through its glass floor, with the
    /// horizon still a third of the way down the view (the window's lens
    /// is 68° tall: tan 13° is a third of tan 34°).
    public static let cabinSeatHeight: Float = 1.15
    public static let cabinSeatAcross: Float = 0.45
    public static let cabinLookDown: Float = 10 * .pi / 180
    public static let crystalLookDown: Float = 13 * .pi / 180

    /// The cabins' rope point and level way on `line` at `glide`.
    func place(_ glide: CablewayCabins.Glide, on line: Line) -> (point: Map3DPoint, along: Map3DPoint) {
        func onRope(leg: Int, share: Float, outbound: Bool) -> (point: Map3DPoint, along: Map3DPoint) {
            let span = line.spans[leg]
            let point = Self.ropePoint(span, share: share) + span.left * ((outbound ? -1 : 1) * Map3DCableCar.ropeSpacing / 2)
            return (point, outbound ? span.along : -span.along)
        }
        switch glide {
        case .span(let leg, let share, let outbound):
            return onRope(leg: leg, share: Float(share), outbound: outbound)
        case .station(let stop, let share, let arrived, let leaves):
            // Where it came in and where it goes on: the ends of the two
            // ropes in this hall.
            let a = arrived ? onRope(leg: stop - 1, share: 1, outbound: true) : onRope(leg: stop, share: 0, outbound: false)
            let b = leaves ? onRope(leg: stop, share: 0, outbound: true) : onRope(leg: stop - 1, share: 1, outbound: false)
            let s = Float(min(max(share, 0), 1))
            guard arrived != leaves else {
                // Through the hall from one rope's end to the next.
                let along = (a.along * (1 - s) + b.along * s).normalized ?? b.along
                return (a.point + (b.point - a.point) * s, along)
            }
            // Turning round at an end: half a circle round the wheel, from
            // the one rope to the other.
            let middle = (a.point + b.point) * 0.5
            let out = a.point - middle
            let angle = Float.pi * s
            let radius = out.length
            let point = middle + out * cosf(angle) + a.along * (radius * sinf(angle))
            let along = (a.along * cosf(angle) - (out.normalized ?? .zero) * sinf(angle)).normalized ?? a.along
            return (point, along)
        }
    }

    /// Decision 583: what the follow camera needs of cabin `id` at game
    /// second `second` (with its fraction): its grip on the rope
    /// (``Map3DFollow/Pose/rail``), its floor's middle, the way it runs,
    /// and its seat for the window view. `nil` when its cable car is gone
    /// or stands still then (``CablewayCabins/runs(_:in:at:)``), or there
    /// is no such cabin. Its place moves on without a jump, through the
    /// stops too (``CablewayCabins/glide(of:on:atSecond:)``).
    public func pose(of id: CabinID, second: Double) -> Map3DFollow.Pose? {
        guard let line = lines.first(where: { $0.id == id.cableway }), id.number >= 0,
              id.number < CablewayCabins.count(of: line.cableway),
              CablewayCabins.runs(id.cableway, in: world, at: GameTime(seconds: Int64(second.rounded(.down)))) else { return nil }
        let at = place(CablewayCabins.glide(of: id.number, on: line.cableway, atSecond: second), on: line)
        let floor = at.point - Map3DPoint(0, Map3DCableCar.cabinDrop, 0)
        let crystal = Self.isCrystal(id.number)
        return Map3DFollow.Pose(forward: at.along, nose: floor + at.along * (Map3DCableCar.cabinLength / 2), rail: at.point, middle: floor,
                                length: Map3DCableCar.cabinLength, ground: nil, inTunnel: false, eyeHeight: Self.cabinSeatHeight,
                                bodyHeight: Self.cabinHeight,
                                window: .init(across: Self.cabinSeatAcross, height: Self.cabinSeatHeight,
                                              lookDown: crystal ? Self.crystalLookDown : Self.cabinLookDown))
    }

    /// Decision 583: the hall's foot of the stop cabin `id` comes to next
    /// at `second`, for the 3D map to build round before it is there
    /// (decision 578's stops ahead); `nil` as ``pose(of:second:)``.
    public func stopAhead(of id: CabinID, second: Double) -> Map3DPoint? {
        guard pose(of: id, second: second) != nil, let line = lines.first(where: { $0.id == id.cableway }) else { return nil }
        let next = CablewayCabins.stops(of: CablewayCabins.glide(of: id.number, on: line.cableway, atSecond: second), on: line.cableway).next
        return line.halls[next].foot
    }

    /// Decision 583: the running cabin drawn nearest the finger at (`x`,
    /// `y`) in `camera`'s view, within `reach` points, at `second`, for a
    /// tap on the 3D map; only those within ``nearReach`` of the eye,
    /// drawn whole.
    public func cabin(atX x: Float, y: Float, camera: Map3DCamera, second: Double, within reach: Float) -> CabinID? {
        var best: (away: Float, id: CabinID)?
        let eye = camera.eye
        for line in lines {
            guard CablewayCabins.runs(line.id, in: world, at: GameTime(seconds: Int64(second.rounded(.down)))) else { continue }
            for number in 0..<CablewayCabins.count(of: line.cableway) {
                let at = place(CablewayCabins.glide(of: number, on: line.cableway, atSecond: second), on: line)
                let body = at.point - Map3DPoint(0, Map3DCableCar.cabinDrop - Self.cabinHeight / 2, 0)
                guard (body - eye).length < Self.nearReach, let screen = camera.screenPoint(of: body) else { continue }
                let away = ((screen.x - x) * (screen.x - x) + (screen.y - y) * (screen.y - y)).squareRoot()
                if away <= reach, best.map({ away < $0.away }) ?? true { best = (away, CabinID(cableway: line.id, number: number)) }
            }
        }
        return best?.id
    }
}
