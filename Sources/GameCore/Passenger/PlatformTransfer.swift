// Decision 912 (CROSS-PLATFORM-TRANSFER): a change of line within one
// station costs what the two lines' platforms make it cost. Before it every
// change at one station counted as the reference's `same-platform` change,
// wherever the two trains stopped; now, when both lines name the platform
// they stop at (``LineRoutePreference``, decision 61 and 740), the change is
// across one island platform, a walk over to another platform on the same
// level, or a climb to another level. Derived from the track, the platforms
// and the lines' preferences; never saved.

/// How a change between two platforms of one station is made (decision 912).
public enum PlatformChangeKind: String, CaseIterable, Sendable {
    /// Across one island platform (or on the same platform): the two
    /// tracks run side by side with a platform wide enough between them
    /// and no other track in the way, as decision 392 draws an island.
    case acrossPlatform
    /// To another platform on the same level, over a footbridge or through
    /// an underpass.
    case sameLevel
    /// To a platform on another level (a viaduct, the ground, underground).
    case otherLevel
    /// One of the two lines does not name its platform: counted as before
    /// decision 912, the reference's `same-platform` change.
    case unspecified
}

/// A change between two platforms of one station (decision 912): its kind,
/// the walk between them and the climb, and from those its perceived cost
/// in route choice and the least time before the passenger can board.
public struct PlatformChange: Hashable, Sendable {
    public let kind: PlatformChangeKind
    /// The walk between the platforms' middles at
    /// ``PassengerTransferRules/walkingMetresPerHour``; 0 across a platform.
    public let walkSeconds: Int64
    /// The stairs or escalators between levels
    /// (``PlatformTransferRules/climbSecondsPerStep`` a step); 0 on one level.
    public let climbSeconds: Int64

    public init(kind: PlatformChangeKind, walkSeconds: Int64 = 0, climbSeconds: Int64 = 0) {
        self.kind = kind
        self.walkSeconds = walkSeconds
        self.climbSeconds = climbSeconds
    }

    /// The change between lines that do not both name their platform: as
    /// before decision 912, the reference's `same-platform` cost with the
    /// reference's least change time.
    public static let unknown = PlatformChange(kind: .unspecified)

    /// The perceived cost in route choice: the `same-platform` penalty
    /// across a platform; otherwise the `passage` penalty plus the walk and
    /// the climb.
    public var penaltySeconds: Int64 {
        switch kind {
        case .acrossPlatform, .unspecified: PassengerTransferTier.samePlatform.penaltySeconds
        case .sameLevel, .otherLevel: PassengerTransferTier.passage.penaltySeconds + walkSeconds + climbSeconds
        }
    }

    /// The least time between getting off and boarding:
    /// ``PlatformTransferRules/acrossPlatformSeconds`` across a platform,
    /// the reference's least change time when a platform is not named,
    /// otherwise the reference's least change time or
    /// the walk and climb, whichever is longer.
    public var minimumSeconds: Int64 {
        switch kind {
        case .acrossPlatform: PlatformTransferRules.acrossPlatformSeconds
        case .unspecified: PassengerTransferRules.minimumChangeSeconds
        case .sameLevel, .otherLevel: max(PassengerTransferRules.minimumChangeSeconds, walkSeconds + climbSeconds)
        }
    }
}

/// The constants of decision 912. The reference has the tier factors and
/// one least change time (``PassengerTransferRules``); these are the
/// project's own values where it has none.
public enum PlatformTransferRules {
    /// The least change across one island platform: 60 s, half the
    /// reference's 120 s (a dozen steps across the platform and the doors
    /// of the other train).
    public static let acrossPlatformSeconds: Int64 = 60
    /// Platforms whose middles stand this far apart in height or more are
    /// on different levels: 4 m.
    public static let levelMetres: Int64 = 4
    /// The climb between levels: 30 s for each 4 m step, or part of one.
    public static let climbSecondsPerStep: Int64 = 30
    /// An island's two tracks stand at least this far apart: the narrowest
    /// platform decision 392 draws (2 m) plus a platform edge (1.6 m) each
    /// side.
    public static let islandMinimumCentimetres: Int64 = 520
    /// And at most this far: decision 392 looks no farther for the other
    /// half of an island.
    public static let islandMaximumMetres: Int64 = 15
    /// Tracks of other levels this far above or below do not stand between
    /// two platforms: decision 392's 3 m.
    public static let besideHeightMetres: Int64 = 3
}

extension GameWorld {
    /// Decision 912: the change between platforms `a` and `b` of one
    /// station. `nil` when either platform is not on this world's track or
    /// they are of different stations.
    public func platformChange(from a: TrackPlatform, to b: TrackPlatform) -> PlatformChange? {
        guard a.station == b.station,
              let geometryA = trackGeometry(of: a.edge), let geometryB = trackGeometry(of: b.edge),
              a.end <= geometryA.length, b.end <= geometryB.length else { return nil }
        if a == b { return PlatformChange(kind: .acrossPlatform) }
        let middleA = geometryA.location(at: (a.start + a.end) / 2).position
        let middleB = geometryB.location(at: (b.start + b.end) / 2).position
        let unit = WorldCoordinate.unitsPerMetre
        let rise = abs(middleA.z - middleB.z)
        let dx = middleA.x - middleB.x
        let dy = middleA.y - middleB.y
        let walk = PassengerTransferTier.walkSeconds(squaredDistance: dx * dx + dy * dy)
        if rise >= PlatformTransferRules.levelMetres * unit {
            let step = PlatformTransferRules.levelMetres * unit
            let steps = (rise + step - 1) / step
            return PlatformChange(kind: .otherLevel, walkSeconds: walk, climbSeconds: steps * PlatformTransferRules.climbSecondsPerStep)
        }
        if a.edge != b.edge, isIsland(a, geometryA, middleA, b, geometryB, middleB) {
            return PlatformChange(kind: .acrossPlatform)
        }
        return PlatformChange(kind: .sameLevel, walkSeconds: walk)
    }

    /// Whether `a` and `b` are the two sides of one island platform: their
    /// tracks run side by side (within 20°), a platform's middle is
    /// ``PlatformTransferRules/islandMinimumCentimetres`` to
    /// ``PlatformTransferRules/islandMaximumMetres`` across from the other's
    /// track, and no other track on their level crosses the way between.
    private func isIsland(_ a: TrackPlatform, _ geometryA: TrackGeometry, _ middleA: WorldCoordinate,
                          _ b: TrackPlatform, _ geometryB: TrackGeometry, _ middleB: WorldCoordinate) -> Bool {
        let lineA = geometryA.points(from: a.start, to: a.end).map(\.plan)
        let lineB = geometryB.points(from: b.start, to: b.end).map(\.plan)
        guard let first = lineA.first, let last = lineA.last, let firstB = lineB.first, let lastB = lineB.last,
              Self.isParallel(PlanVector(dx: last.x - first.x, dy: last.y - first.y),
                              PlanVector(dx: lastB.x - firstB.x, dy: lastB.y - firstB.y)) else { return false }
        // Across: the middle of one stands beside the other's stretch, not
        // beyond its ends.
        let across: (from: PlanPoint, to: PlanPoint)
        if let foot = Self.foot(of: middleA.plan, on: lineB) {
            across = (middleA.plan, foot)
        } else if let foot = Self.foot(of: middleB.plan, on: lineA) {
            across = (foot, middleB.plan)
        } else {
            return false
        }
        let unit = WorldCoordinate.unitsPerMetre
        let gapX = across.to.x - across.from.x
        let gapY = across.to.y - across.from.y
        let gap = gapX * gapX + gapY * gapY
        let least = PlatformTransferRules.islandMinimumCentimetres * unit / 100
        let most = PlatformTransferRules.islandMaximumMetres * unit
        guard gap >= least * least, gap <= most * most else { return false }
        // No other track on this level crosses the way across.
        let height = (middleA.z + middleB.z) / 2
        let beside = PlatformTransferRules.besideHeightMetres * unit
        // The box round the way across, a metre wider each side; an edge
        // lies within the box of its ends and control points.
        let minX = min(across.from.x, across.to.x) - unit, maxX = max(across.from.x, across.to.x) + unit
        let minY = min(across.from.y, across.to.y) - unit, maxY = max(across.from.y, across.to.y) + unit
        for edge in network.edges where edge.id != a.edge && edge.id != b.edge {
            guard let from = network.node(edge.from)?.position, let to = network.node(edge.to)?.position else { continue }
            let corners = [from.plan, to.plan] + edge.curve.controlPoints
            guard corners.contains(where: { $0.x >= minX }), corners.contains(where: { $0.x <= maxX }),
                  corners.contains(where: { $0.y >= minY }), corners.contains(where: { $0.y <= maxY }),
                  let geometry = trackGeometry(of: edge.id) else { continue }
            for (p, q) in zip(geometry.points, geometry.points.dropFirst()) where abs((p.z + q.z) / 2 - height) <= beside {
                if Self.cross(across.from, across.to, p.plan, q.plan) { return false }
            }
        }
        return true
    }

    /// Whether two directions are within about 20° of each other, either
    /// way round (cos² ≥ 0.88).
    private static func isParallel(_ u: PlanVector, _ v: PlanVector) -> Bool {
        func small(_ w: PlanVector) -> PlanVector {
            var (x, y) = (w.dx, w.dy)
            while abs(x) > 10_000 || abs(y) > 10_000 { x /= 2; y /= 2 }
            return PlanVector(dx: x, dy: y)
        }
        let (a, b) = (small(u), small(v))
        let dot = a.dx * b.dx + a.dy * b.dy
        let lengths = (a.dx * a.dx + a.dy * a.dy) * (b.dx * b.dx + b.dy * b.dy)
        guard lengths > 0 else { return false }
        return 100 * dot * dot >= 88 * lengths
    }

    /// The point of `line` nearest `point`, when it is not one of the
    /// line's two ends (the point stands beside the line, not beyond it).
    private static func foot(of point: PlanPoint, on line: [PlanPoint]) -> PlanPoint? {
        var best: (squared: Int64, foot: PlanPoint, inside: Bool)?
        for (index, (p, q)) in zip(line, line.dropFirst()).enumerated() {
            let ux = q.x - p.x, uy = q.y - p.y
            let wx = point.x - p.x, wy = point.y - p.y
            let length = ux * ux + uy * uy
            guard length > 0 else { continue }
            let along = wx * ux + wy * uy
            let foot: PlanPoint
            var inside = true
            if along <= 0 {
                foot = p
                inside = index > 0
            } else if along >= length {
                foot = q
                inside = index < line.count - 2
            } else {
                foot = PlanPoint(x: p.x + ux * along / length, y: p.y + uy * along / length)
            }
            let fx = point.x - foot.x, fy = point.y - foot.y
            let squared = fx * fx + fy * fy
            if best == nil || squared < best!.squared { best = (squared, foot, inside) }
        }
        guard let best, best.inside else { return nil }
        return best.foot
    }

    /// Whether segments `a`–`b` and `c`–`d` cross at a point inside both.
    private static func cross(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint, _ d: PlanPoint) -> Bool {
        func side(_ p: PlanPoint, _ q: PlanPoint, _ r: PlanPoint) -> Int64 {
            let value = (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
            return value > 0 ? 1 : value < 0 ? -1 : 0
        }
        let (s1, s2) = (side(a, b, c), side(a, b, d))
        let (s3, s4) = (side(c, d, a), side(c, d, b))
        return s1 * s2 < 0 && s3 * s4 < 0
    }

    /// Decision 912: the platform the trains of `line`'s service `service`
    /// running `direction` stand at when they call at stop `stop`: the one
    /// its preference for the leg into that stop names (decision 61), or at
    /// the first call of that direction the one the leg the other way into
    /// it names (the train turned there). `nil` when no preference names
    /// one, or when it names a list (decision 740), which leaves the train
    /// free among several.
    func designatedPlatform(of line: ServiceLine, service: Int, direction: LineDirection, stop: Int) -> TrackPlatform? {
        let order: [Int]
        if line.isRing {
            order = line.ringCalls(direction == .outbound ? .inner : .outer)
        } else {
            let calls = line.calls(ofService: service)
            order = direction == .outbound ? calls : calls.reversed()
        }
        let routes = line.routes(ofService: service)
        guard !routes.isEmpty else { return nil }
        let previous: Int
        if let index = order.indices.first(where: { $0 > 0 && order[$0] == stop }) {
            previous = order[index - 1]
        } else if order.count > 1, order[0] == stop {
            previous = order[1]
        } else {
            return nil
        }
        guard let route = routes.first(where: { $0.from == previous && $0.to == stop }), route.alternates.isEmpty else { return nil }
        return route.platform
    }

    /// Decision 912: the platform `leg`'s trains stand at at station
    /// `station`, the leg's `from` or `to` (see
    /// ``designatedPlatform(of:service:direction:stop:)``).
    public func designatedPlatform(of leg: PassengerJourneyLeg, at station: StationID) -> TrackPlatform? {
        guard let line = line(id: leg.line), let service = line.service(leg.pattern) else { return nil }
        let calls = line.isRing ? Array(line.stops.indices) : line.calls(ofService: service)
        guard let stop = calls.first(where: { line.stops[$0] == station }) else { return nil }
        return designatedPlatform(of: line, service: service, direction: leg.direction, stop: stop)
    }

    /// Decision 912: the change at one station from `arriving`, the leg
    /// just ridden, to `departing`, the next one: ``PlatformChange/unknown``
    /// unless both name their platform there.
    func platformChange(from arriving: PassengerJourneyLeg, to departing: PassengerJourneyLeg) -> PlatformChange {
        guard let a = designatedPlatform(of: arriving, at: arriving.to),
              let b = designatedPlatform(of: departing, at: departing.from) else { return .unknown }
        return platformChange(from: a, to: b) ?? .unknown
    }

    /// ``platformChange(from:to:)`` of two legs, kept in `memo`.
    func memoizedPlatformChange(from arriving: PassengerJourneyLeg, to departing: PassengerJourneyLeg,
                                memo: inout DispatchMemo) -> PlatformChange {
        let key = PlatformChangeLegs(arriving: arriving, departing: departing)
        if let known = memo.platformChanges[key] { return known }
        let change = platformChange(from: arriving, to: departing)
        memo.platformChanges[key] = change
        return change
    }
}

/// Decision 912: one way a line's trains call at a station, and the
/// platform they stand at there when the line names it.
public struct LinePlatformCall: Hashable, Sendable {
    public let line: LineID
    /// `nil` for the line's own service; otherwise its pattern index.
    public let pattern: Int?
    public let direction: LineDirection
    public let platform: TrackPlatform?
}

extension GameWorld {
    /// Decision 912: each passenger line's calls at station `station`, a
    /// call for each service and direction that stops there, by line,
    /// service and direction (outbound first). Freight lines are left out.
    public func platformCalls(at station: StationID) -> [LinePlatformCall] {
        var calls: [LinePlatformCall] = []
        for line in lines where !line.isFreight {
            for service in 0..<line.serviceCount {
                let stops = line.isRing ? Array(line.stops.indices) : line.calls(ofService: service)
                guard let stop = stops.first(where: { line.stops[$0] == station }) else { continue }
                for direction in [LineDirection.outbound, .inbound] {
                    calls.append(LinePlatformCall(line: line.id, pattern: service == 0 ? nil : service - 1, direction: direction,
                                                  platform: designatedPlatform(of: line, service: service, direction: direction, stop: stop)))
                }
                if line.isRing { break }
            }
        }
        return calls
    }
}

/// Decision 912: a leg ridden and the next one, the key of
/// ``GameWorld/DispatchMemo/platformChanges``.
struct PlatformChangeLegs: Hashable {
    let arriving: PassengerJourneyLeg
    let departing: PassengerJourneyLeg
}
