/// The authoritative game state and the only entry point for changing it.
///
/// `GameWorld` is a value type: every command validates its inputs before
/// touching any state, so a thrown ``GameError`` always leaves the world
/// exactly as it was. Copies are independent snapshots, which also gives
/// future undo/redo and background work a cheap starting point.
///
/// Presentation and rendering layers read from a world and send it commands;
/// they must not keep a separate copy of game state as the source of truth.
public struct GameWorld: Equatable, Sendable {
    /// How far the world reaches (Stage F3d): every track node and station
    /// stands in it. The railway is the ``network``, and stations stand at
    /// points (Stage F1); the world has no cells.
    public private(set) var bounds: WorldBounds
    /// All stations, ordered by ascending ``StationID``.
    public private(set) var stations: [Station]
    /// All trains, ordered by ascending ``TrainID``.
    public private(set) var trains: [Train]
    /// All service lines, ordered by ascending ``LineID``.
    public private(set) var lines: [ServiceLine]
    /// Which service level each minute of the day has, for every line.
    public private(set) var serviceDay: ServiceDay
    public private(set) var clock: GameClock
    public internal(set) var economy: GameEconomy
    /// The railway (Phase 4.5 Stage S3): the one record of all track, the
    /// network's nodes and edges. Empty in a new world.
    public private(set) var network: RailwayNetwork
    /// Whether traffic control is on (Phase 4.6 Stage T, ARCHITECTURE
    /// decision 32): every train takes the whole of a route before it starts
    /// along it, no two trains hold the same track, and a service or a line
    /// whose route is held waits for it (see ``setTrafficControl(_:)`` and
    /// ``reservedResources(of:)``). Off in a new world, so every rule of the
    /// stages before it holds unchanged; a new game in the app turns it on.
    public private(set) var isTrafficControlEnabled: Bool
    /// The passengers of every station that has any (G1a, ARCHITECTURE
    /// decision 34): its demand, the groups waiting there and the
    /// conservation audit, by ascending ``StationID``. Empty in a new world,
    /// where no station has demand. Set by the passenger rules
    /// (`PassengerDemand.swift`) only.
    public internal(set) var passengers: [StationPassengers]
    /// The passengers riding each train that carries any (G1b, ARCHITECTURE
    /// decision 35), by ascending ``TrainID``. Set by the passenger rules
    /// (`Boarding.swift`) only.
    public internal(set) var riders: [TrainRiders]
    /// Legacy saves keep direct-trip demand; network games select a complete
    /// journey at release. A change affects future releases only.
    public internal(set) var passengerRoutingMode: PassengerRoutingMode
    /// Whether each day's demand follows the reference's weekday factors
    /// and weekends its weekend hours (item 4 of the author's order). Off in
    /// a new world and in saves from before it; the app's new games turn it
    /// on. Set by ``setWeeklyDemand(_:)`` only.
    public internal(set) var weeklyDemand: Bool = false
    /// The demand events and the seed they are drawn from, or `nil` for a
    /// world without them (item 4; see ``DemandEventSchedule``). Off in a
    /// new world and in saves from before them; the app's new games turn
    /// them on. Set by ``setDemandEvents(seed:)`` and every midnight only.
    public internal(set) var demandEvents: DemandEventSchedule?
    /// How the towns round the stations grow, or `nil` for a world whose
    /// ridership stays as set (item 5; see ``TownGrowth``). Off in a new
    /// world and in saves from before it; the app's new games turn it on.
    /// Set by ``setTownGrowth(_:)`` and every midnight only.
    public internal(set) var townGrowth: TownGrowth?
    /// Fractions left after deterministic OD route choice, by origin and
    /// destination. They are saved so advancing in batches changes nothing.
    var passengerRouteBalances: [PassengerRouteBalance]
    /// The company's accounts (G1c, ARCHITECTURE decision 36): its economy
    /// mode and fare rules, the hour being accrued and the ledger. Free and
    /// empty in a new world. Set by the economy rules (`Economy/`) only.
    public internal(set) var accounts: CompanyAccounts
    /// Where the map lies on the Earth, for a real-world game (Stage E2,
    /// ARCHITECTURE decision 50); `nil`, a blank map, in a new world. No
    /// rule reads it. Set by ``setGeoAnchor(_:)`` only.
    public internal(set) var geoAnchor: GeoAnchor?
    /// The trips that release passengers, derived from the demands and the
    /// lines' stops and kept between calls of ``advance(ticks:)``; not game
    /// state (see ``PassengerPlanCache``).
    var passengerPlan = PassengerPlanCache()
    /// The network route choices the last plan used, kept while the derived
    /// route graph stays the same; not game state (see
    /// ``PassengerRouteMemo``).
    var passengerRouteMemo = PassengerRouteMemo()

    /// The next ID to hand out to a station, a train or a line (see
    /// `allocateID(from:)`).
    private var nextStationID: Int
    private var nextTrainID: Int
    private var nextLineID: Int

    /// Creates an empty world reaching as far as `bounds`.
    public init(
        bounds: WorldBounds,
        economy: GameEconomy,
        clock: GameClock = GameClock()
    ) {
        self.bounds = bounds
        self.stations = []
        self.trains = []
        self.lines = []
        self.serviceDay = .standard
        self.clock = clock
        self.economy = economy
        self.network = RailwayNetwork()
        self.isTrafficControlEnabled = false
        self.passengers = []
        self.riders = []
        self.passengerRoutingMode = .direct
        self.passengerRouteBalances = []
        self.accounts = CompanyAccounts()
        self.geoAnchor = nil
        self.nextStationID = 1
        self.nextTrainID = 1
        self.nextLineID = 1
    }

    // MARK: - Queries

    public func station(id: StationID) -> Station? {
        stations.first { $0.id == id }
    }

    /// The station whose ``Station/location`` is nearest `point`, if one
    /// lies within `reach` world units of it (Stage F1): the lowest
    /// numbered of equally near ones. Distances compare squared, exactly.
    public func station(near point: PlanPoint, within reach: Int64) -> Station? {
        guard reach >= 0, point.isWithinLimits, reach <= WorldCoordinate.limit else { return nil }
        var best: (station: Station, squared: Int64)?
        for station in stations {
            let location = station.location
            let dx = location.x - point.x, dy = location.y - point.y
            guard abs(dx) <= reach, abs(dy) <= reach else { continue }
            let squared = dx * dx + dy * dy
            guard squared <= reach * reach, best.map({ squared < $0.squared }) ?? true else { continue }
            best = (station, squared)
        }
        return best?.station
    }

    // MARK: - Track network

    /// Builds a node of the track network at `position` (Phase 4.5 Stage S3):
    /// a point where edges can end and meet. Free: track is paid for by its
    /// edges. Returns the new node's ID, ``TrackNodeID/node(_:)``, numbered
    /// in order from 1 and never reused.
    ///
    /// The node must lie in the world's ``bounds``, at a height in
    /// ``RailwayNetwork/heightRange`` (Stage S4; 0 is the ground), where no
    /// node stands yet.
    ///
    /// - Throws, checked in this order: ``GameError/invalidTrackGeometry``
    ///   or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func buildTrackNode(at position: WorldCoordinate) throws(GameError) -> TrackNodeID {
        guard isInWorld(position), !network.hasNode(at: position) else { throw .invalidTrackGeometry }
        let (_, next) = try Self.allocateID(from: network.nextNodeNumber)

        return network.addNode(at: position, next: next)
    }

    /// Builds an edge of the track network from node `from` to node `to`,
    /// shaped in plan by `curve` (Phase 4.5 Stage S3) and in height by
    /// `profile`, carried by `structure` (Stage S4), and charges
    /// ``ConstructionCosts/track`` times the structure's
    /// ``TrackStructure/costFactor`` for every
    /// ``ConstructionCosts/trackPricingLength`` of its length (1024 units,
    /// 16 m), rounded up. Returns the new edge's ID,
    /// ``TrackEdgeID/edge(_:)``, numbered in order from 1 and never reused.
    ///
    /// The edge's length, centre line and heights are worked out from its
    /// end nodes, curve and profile (see ``TrackGeometry``); its control
    /// points must lie in the world's ``bounds``. Which edges it joins at each end follows
    /// from the way it leaves the node (see ``TrackNodeEnd``): an edge that
    /// meets others at an angle joins none of them there. Edges that cross
    /// in plan without a shared node never join, and must pass one over the
    /// other (see ``TrackClearance``). Since Stage F2 edges at one level keep
    /// ``RailwayNetwork/trackSpacing`` apart but at points within
    /// ``RailwayNetwork/partingReach`` of each other along the track, where
    /// they are one junction's tracks parting (see ``TrackSpacing``). Several
    /// edges may join the same two nodes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)``
    ///   for `from`, then for `to`; ``GameError/invalidTrackGeometry`` (the
    ///   same node twice, a control point outside the bounds, or a curve or profile
    ///   that does not make an edge); ``GameError/trackTooSteep``;
    ///   ``GameError/invalidTrackStructure``;
    ///   ``GameError/trackConflict(_:)`` for the lowest numbered edge it
    ///   would meet without clearance; ``GameError/trackTooClose(_:)`` for
    ///   the lowest numbered edge it would run too close beside;
    ///   ``GameError/idsExhausted``; under
    ///   traffic control (Stage T), ``GameError/trackReserved(_:)`` when a
    ///   train holds either end node, or track within
    ///   ``RailwayNetwork/junctionZone`` of it, since a new edge there may
    ///   change which trains foul that junction; or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildTrackEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve = .straight, profile: TrackProfile = .uniform, structure: TrackStructure = .surface
    ) throws(GameError) -> TrackEdgeID {
        let id = try buildTrackEdge(from: from, to: to, curve: curve, profile: profile, structure: structure, checksSpacing: true)
        abandonUnservedPassengers()
        return id
    }

    /// Builds the edges `plans` describe, in order, as one command (the
    /// owner's play-test, 2026-10-06): each as
    /// ``buildTrackEdge(from:to:curve:profile:structure:)`` would, charged
    /// the same, except that the spacing rule is checked once all of them
    /// are built, along the ways they make together. An X crossover's
    /// diagonal runs within 4 m of the other track near the middle and parts
    /// from it only by way of its other half; built one at a time, the first
    /// half would be refused. All or nothing. Returns the new edges in order.
    ///
    /// - Throws: what ``buildTrackEdge(from:to:curve:profile:structure:)``
    ///   throws for the first plan it refuses, checked as that plan is
    ///   built (``GameError/insufficientFunds(required:available:)`` for
    ///   the first the money left does not cover); then
    ///   ``GameError/trackTooClose(_:)`` for the lowest numbered edge the
    ///   first new edge, in order, runs too close beside.
    @discardableResult
    public mutating func buildTrackEdges(_ plans: [TrackEdgePlan]) throws(GameError) -> [TrackEdgeID] {
        var after = self
        var built: [TrackEdgeID] = []
        for plan in plans {
            built.append(try after.buildTrackEdge(from: plan.from, to: plan.to, curve: plan.curve, profile: plan.profile,
                                                  structure: plan.structure, checksSpacing: false))
        }
        for id in built {
            if let other = after.network.firstTooClose(existing: id, besides: []) {
                throw .trackTooClose(other)
            }
        }
        self = after
        abandonUnservedPassengers()
        return built
    }

    private mutating func buildTrackEdge(
        from: TrackNodeID, to: TrackNodeID, curve: TrackCurve, profile: TrackProfile, structure: TrackStructure, checksSpacing: Bool
    ) throws(GameError) -> TrackEdgeID {
        guard let start = network.node(from) else { throw .unknownTrackNode(from) }
        guard let end = network.node(to) else { throw .unknownTrackNode(to) }
        guard from != to, curve.controlPoints.allSatisfy(bounds.contains),
              let geometry = TrackGeometry(from: start.position, to: end.position, curve: curve, profile: profile)
        else { throw .invalidTrackGeometry }
        guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) else { throw .trackTooSteep }
        guard structure.allows(height: start.position.z), structure.allows(height: end.position.z) else { throw .invalidTrackStructure }
        if let other = network.firstConflict(from: from, to: to, curve: curve, geometry: geometry) {
            throw .trackConflict(other)
        }
        if checksSpacing, let other = network.firstTooClose(from: from, to: to, curve: curve, geometry: geometry) {
            throw .trackTooClose(other)
        }
        let (_, next) = try Self.allocateID(from: network.nextEdgeNumber)
        if isTrafficControlEnabled, let train = trains.first(where: { train in
            held(train).contains { resource in [from, to].contains { isWithinJunctionZone(resource, of: $0) } }
        }) {
            throw .trackReserved(train.id)
        }
        try economy.spend(try edgeCost(length: geometry.length, structure: structure))

        let id = network.addEdge(from: from, to: to, curve: curve, profile: profile, structure: structure, geometry: geometry, next: next)
        network.dropSpacedExemptions()
        return id
    }

    /// The lower numbered of the first two placed trains, in ID order, whose
    /// held track would foul without edge `id` but does not now (Stage F2b):
    /// removing an edge makes ways along the track longer, so track near
    /// each other along it may come to foul. `nil` when there are none.
    private func firstTrainFouled(removing id: TrackEdgeID) -> TrainID? {
        var after = network
        after.removeEdge(id)
        guard !after.foulingSpans.isEmpty else { return nil }
        let placed = trains.filter { $0.position != nil }.map { ($0.id, held($0)) }
        for j in placed.indices {
            for i in placed.indices where i < j {
                if after.fouls(placed[i].1, placed[j].1), !network.fouls(placed[i].1, placed[j].1) { return placed[i].0 }
            }
        }
        return nil
    }

    /// Removes edge `id` of the track network (Stage S3). Removal is free and
    /// not refunded. Its nodes stay; the edges it joined there no longer join
    /// it. A train whose path names it stops at the node before it and waits
    /// there: IDs are never reused, so give that train a new path.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackEdge(_:)``;
    ///   ``GameError/trackEdgeInUse(_:)`` while a placed train's head or
    ///   body is on it (unplace the train first); or
    ///   ``GameError/trackEdgeHasPlatform(_:)`` while a station has a
    ///   platform on it (Stage S4); or, under traffic control (Stage T),
    ///   ``GameError/trackReserved(_:)`` while a train has reserved some of
    ///   it for its route, or (Stage F2b) when without it track two trains
    ///   hold would foul (see ``RailwayNetwork/fouls(_:_:)``): the lower
    ///   numbered of the first two such trains; or
    ///   ``GameError/tracksWouldBeTooClose(_:_:)`` when
    ///   two edges part from each other only by way of it, so that without
    ///   it they would be too close (Stage F2, ARCHITECTURE decision 52).
    public mutating func removeTrackEdge(_ id: TrackEdgeID) throws(GameError) {
        guard network.edge(id) != nil else { throw .unknownTrackEdge(id) }
        guard !trains.contains(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(id)
        }) else { throw .trackEdgeInUse(id) }
        guard network.platforms(on: id).isEmpty else { throw .trackEdgeHasPlatform(id) }
        if isTrafficControlEnabled, let train = trains.first(where: { $0.reservation.contains { $0.isSpan(of: id) } }) {
            throw .trackReserved(train.id)
        }
        if isTrafficControlEnabled, let train = firstTrainFouled(removing: id) {
            throw .trackReserved(train)
        }
        if let pair = network.firstPairLeftTooClose(removing: id) {
            throw .tracksWouldBeTooClose(pair.first, pair.second)
        }

        network.removeEdge(id)
        abandonUnservedPassengers()
    }

    /// The shortest piece either part of a split edge may be: a junction
    /// zone (``RailwayNetwork/junctionZone``, 16 m), so the new node's
    /// junction never reaches past the far end.
    public static let minimumSplitPiece: Int64 = RailwayNetwork.junctionZone

    /// Splits edge `id` of the track network into two edges joined at a new
    /// node `distance` along it from its `from` node, so that new track can
    /// branch from there (a turnout in the middle of a line). Free: the
    /// track is paid for. Returns the new node.
    ///
    /// A straight edge splits into two straight edges at its point
    /// `distance` along. A cubic edge splits at its sampled point nearest
    /// `distance` along (see ``TrackGeometry``), the curve cut there by de
    /// Casteljau's rule with each control point rounded to the nearest unit,
    /// halves up; the parts' geometry and lengths are worked out again from
    /// them. Each part keeps the edge's structure. The parts join each other
    /// at the new node and the edges the old one joined at its ends, and a
    /// platform on the edge moves to the part it lies on, at the same
    /// distances from the edge's `from` node (the second part's less the
    /// first part's length); one that would end past its part's rounded
    /// end moves back to end there, its length kept.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackEdge(_:)``;
    ///   ``GameError/invalidTrackGeometry`` for an edge that is not level
    ///   (a split of a slope is not yet supported), a cut less than
    ///   ``minimumSplitPiece`` from either end, an edge in a spacing
    ///   exemption, or parts that would not be edges or not join as it did;
    ///   ``GameError/trackReserved(_:)`` for the lowest numbered train that
    ///   stands on the edge, has its body on it, will enter it along its
    ///   path or has reserved some of it; ``GameError/trackEdgeHasPlatform(_:)``
    ///   when a platform spans the cut; ``GameError/trackEdgeInLineRoute(_:)``
    ///   for the lowest numbered line whose chosen path runs along it or
    ///   stops at a platform on it; ``GameError/trackConflict(_:)`` or
    ///   ``GameError/trackTooClose(_:)`` when a part would meet other track;
    ///   or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func splitTrackEdge(_ id: TrackEdgeID, at distance: Int64) throws(GameError) -> TrackNodeID {
        guard let edge = network.edge(id), let geometry = network.geometry(of: id),
              let start = network.node(edge.from), let end = network.node(edge.to) else { throw .unknownTrackEdge(id) }
        guard start.position.z == end.position.z, edge.profile == .uniform,
              distance >= Self.minimumSplitPiece, distance <= geometry.length - Self.minimumSplitPiece,
              !network.spacingExemptions.contains(where: { $0.contains(id) }),
              let cut = Self.split(edge.curve, from: start.position.plan, to: end.position.plan, near: distance)
        else { throw .invalidTrackGeometry }
        if let train = trains.first(where: { train in
            if case .onEdge(let traversal, _)? = train.position, traversal.edge == id { return true }
            return train.trailEdges.contains(id) || train.movement.remainingEdges.contains(id)
                || train.reservation.contains { $0.isSpan(of: id) }
        }) {
            throw .trackReserved(train.id)
        }
        guard !network.platforms(on: id).contains(where: { $0.start < cut.chainage && cut.chainage < $0.end }) else {
            throw .trackEdgeHasPlatform(id)
        }
        if let line = lines.first(where: { line in
            (0..<line.serviceCount).contains { service in
                line.routes(ofService: service).contains { route in
                    route.platform.edge == id || route.tracks.contains { $0.edge == id }
                }
            }
        }) {
            throw .trackEdgeInLineRoute(line.id)
        }
        let middle = WorldCoordinate(x: cut.point.x, y: cut.point.y, z: start.position.z)
        guard isInWorld(middle), !network.hasNode(at: middle),
              cut.first.controlPoints.allSatisfy(bounds.contains), cut.second.controlPoints.allSatisfy(bounds.contains),
              let firstGeometry = TrackGeometry(from: start.position, to: middle, curve: cut.first),
              let secondGeometry = TrackGeometry(from: middle, to: end.position, curve: cut.second)
        else { throw .invalidTrackGeometry }

        var after = network
        let platforms = after.platforms(on: id)
        for platform in platforms {
            guard let index = after.platforms.firstIndex(of: platform) else { continue }
            after.removePlatform(at: index)
        }
        after.removeEdge(id)
        let (_, nodeNext) = try Self.allocateID(from: after.nextNodeNumber)
        let node = after.addNode(at: middle, next: nodeNext)
        if let other = after.firstConflict(from: edge.from, to: node, curve: cut.first, geometry: firstGeometry) {
            throw .trackConflict(other)
        }
        let (_, firstNext) = try Self.allocateID(from: after.nextEdgeNumber)
        let first = after.addEdge(from: edge.from, to: node, curve: cut.first, profile: .uniform, structure: edge.structure,
                                  geometry: firstGeometry, next: firstNext)
        if let other = after.firstConflict(from: node, to: edge.to, curve: cut.second, geometry: secondGeometry) {
            throw .trackConflict(other)
        }
        let (_, secondNext) = try Self.allocateID(from: after.nextEdgeNumber)
        let second = after.addEdge(from: node, to: edge.to, curve: cut.second, profile: .uniform, structure: edge.structure,
                                   geometry: secondGeometry, next: secondNext)
        // Spacing along the ways of the network with both parts: alone,
        // neither reaches the junction where the edge parted from track
        // beside it.
        for part in [first, second] {
            if let other = after.firstTooClose(existing: part, besides: [first, second]) {
                throw .trackTooClose(other)
            }
        }
        // The parts join each other, and at the old ends what the edge did.
        func exits(_ edge: TrackEdgeID, at node: TrackNodeID, in network: RailwayNetwork) -> Set<TrackEdgeID> {
            Set(network.node(node)?.end(of: edge)?.exits ?? [])
        }
        guard exits(first, at: node, in: after) == [second], exits(second, at: node, in: after) == [first],
              exits(first, at: edge.from, in: after) == exits(id, at: edge.from, in: network),
              exits(second, at: edge.to, in: after) == exits(id, at: edge.to, in: network)
        else { throw .invalidTrackGeometry }
        // The parts' lengths are rounded, so one can end a few units short
        // of where the edge did: a platform past its end moves back, its
        // length kept, so a train that fitted it still does.
        func moved(_ platform: TrackPlatform, to part: TrackEdgeID, length: Int64, from offset: Int64) -> TrackPlatform {
            let end = min(platform.end - offset, length)
            let start = max(0, min(platform.start - offset, end - (platform.end - platform.start)))
            return TrackPlatform(station: platform.station, edge: part, start: start, end: end)
        }
        for platform in platforms {
            let moved = platform.end <= cut.chainage
                ? moved(platform, to: first, length: firstGeometry.length, from: 0)
                : moved(platform, to: second, length: secondGeometry.length, from: cut.chainage)
            guard moved.start >= 0, moved.start < moved.end, !after.platforms.contains(where: { $0.overlaps(moved) }) else {
                throw .invalidTrackGeometry
            }
            after.addPlatform(moved)
        }
        after.dropSpacedExemptions()
        network = after
        return node
    }

    /// Edge `curve` from `p0` to `p3` cut at its sampled point nearest
    /// `distance` along it (see ``splitTrackEdge(_:at:)``): the two parts'
    /// curves, the point, and its chainage along the uncut edge. `nil` when
    /// the cut would fall on an end.
    static func split(_ curve: TrackCurve, from p0: PlanPoint, to p3: PlanPoint, near distance: Int64)
        -> (first: TrackCurve, second: TrackCurve, point: PlanPoint, chainage: Int64)?
    {
        switch curve {
        case .straight:
            guard let geometry = TrackGeometry(from: WorldCoordinate(x: p0.x, y: p0.y, z: 0), to: WorldCoordinate(x: p3.x, y: p3.y, z: 0),
                                               curve: .straight) else { return nil }
            let position = geometry.location(at: distance).position
            let point = PlanPoint(x: position.x, y: position.y)
            guard point != p0, point != p3 else { return nil }
            return (.straight, .straight, point, distance)
        case .cubic(let c1, let c2):
            // The samples of TrackGeometry, kept with their indices.
            let polygon = c1.vector(from: p0).length + c2.vector(from: c1).length + p3.vector(from: c2).length
            var count = TrackGeometry.minimumSamples
            var shift = 9
            while count < TrackGeometry.maximumSamples, count * TrackGeometry.sampleSpacing < polygon {
                count *= 2
                shift += 3
            }
            let unit = shift / 3
            func point(_ step: Int64) -> PlanPoint {
                let rest = count - step
                let w0 = rest * rest * rest, w1 = 3 * rest * rest * step, w2 = 3 * rest * step * step, w3 = step * step * step
                return PlanPoint(x: FixedPoint.roundedShift(w0 * p0.x + w1 * c1.x + w2 * c2.x + w3 * p3.x, by: shift),
                                 y: FixedPoint.roundedShift(w0 * p0.y + w1 * c1.y + w2 * c2.y + w3 * p3.y, by: shift))
            }
            var best: (step: Int64, chainage: Int64)?
            var previous = p0
            var travelled: Int64 = 0
            for step in 1..<count {
                let here = point(step)
                travelled += here.vector(from: previous).length
                previous = here
                if best == nil || abs(travelled - distance) < abs(best!.chainage - distance) {
                    best = (step, travelled)
                }
            }
            guard let best else { return nil }
            let i = best.step, rest = count - i
            func linear(_ a: PlanPoint, _ b: PlanPoint) -> PlanPoint {
                PlanPoint(x: FixedPoint.roundedShift(rest * a.x + i * b.x, by: unit),
                          y: FixedPoint.roundedShift(rest * a.y + i * b.y, by: unit))
            }
            func quadratic(_ a: PlanPoint, _ b: PlanPoint, _ c: PlanPoint) -> PlanPoint {
                let w0 = rest * rest, w1 = 2 * rest * i, w2 = i * i
                return PlanPoint(x: FixedPoint.roundedShift(w0 * a.x + w1 * b.x + w2 * c.x, by: 2 * unit),
                                 y: FixedPoint.roundedShift(w0 * a.y + w1 * b.y + w2 * c.y, by: 2 * unit))
            }
            let middle = point(i)
            let first = TrackCurve.cubic(linear(p0, c1), quadratic(p0, c1, c2))
            let second = TrackCurve.cubic(quadratic(c1, c2, p3), linear(c2, p3))
            guard middle != p0, middle != p3 else { return nil }
            return (first, second, middle, best.chainage)
        }
    }

    /// Removes node `id` of the track network (Stage S3). Free. No edge may
    /// end at it, so no train can be there.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrackNode(_:)`` or
    ///   ``GameError/trackNodeInUse(_:)`` while edges end at it.
    public mutating func removeTrackNode(_ id: TrackNodeID) throws(GameError) {
        guard let node = network.node(id) else { throw .unknownTrackNode(id) }
        guard node.ends.isEmpty else { throw .trackNodeInUse(id) }

        network.removeNode(id)
    }

    /// Adds a platform to the railway network for station `id`, along edge
    /// `edge` from `start` to `end` measured from the edge's `from` node
    /// (Phase 4.5 Stage S4). Free: the station has been paid for. A station
    /// may have any number of platforms, straight or curved, at different
    /// levels (surface, elevated, underground); each platform's level is its
    /// edge's height and structure there. Its ends cut the edge's resource
    /// spans (see ``trackSpans(of:)``).
    ///
    /// The stretch must lie within the edge (`0 <= start < end <= length`),
    /// be level (the edge's height at `start` and at `end` is the same, and
    /// heights never turn back along an edge), and not overlap another
    /// platform on the edge, of this station or another.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/unknownTrackEdge(_:)``; ``GameError/invalidPlatform``;
    ///   ``GameError/trainServiceActive(_:)`` naming the lowest numbered
    ///   train whose service stands at a passing place (Stage V2) with its
    ///   head where the platform would be, of the station of its call; or,
    ///   under traffic control (Stage T), ``GameError/trackReserved(_:)``
    ///   while a train holds a span of the edge, whose spans the platform's
    ///   ends would cut.
    public mutating func addTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64, to end: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard network.edge(edge) != nil else { throw .unknownTrackEdge(edge) }
        let platform = TrackPlatform(station: id, edge: edge, start: start, end: end)
        guard isValidPlatform(platform), !network.platforms.contains(where: { $0.overlaps(platform) }) else {
            throw .invalidPlatform
        }
        // Stage V2: a service at a passing place stands there with its path
        // spent; a platform of its call under its head would stop it at its
        // call without arriving.
        if let train = trains.first(where: { train in
            guard isAtPassingPlace(train), case .travellingToStop(let stop, _)? = train.execution,
                  train.timetable[stop].station == id, let (standing, chainage) = standingPoint(of: train) else { return false }
            return standing == edge && start <= chainage && chainage <= end
        }) {
            throw .trainServiceActive(train.id)
        }
        try requireSpansUnheld(on: edge)

        network.addPlatform(platform)
        abandonUnservedPassengers()
    }

    /// Removes station `id`'s platform on edge `edge` that starts at `start`
    /// (Stage S4). Free.
    ///
    /// A platform a timetable service needs cannot be removed (Stage S5):
    /// one where a service waits at this station with the train's head on
    /// the platform, or one on the edge where a service travelling to this
    /// station ends its path, or one of a passing place it travels to or
    /// stands at, or of the call it goes on to from there (Stage V2). Stop
    /// the service first (for a line's train, take it off the line). So a
    /// waiting service is always stopped at its station, and a travelling
    /// one always has a platform to arrive at.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)``;
    ///   ``GameError/invalidPlatform`` when the station has no such
    ///   platform; ``GameError/trainServiceActive(_:)`` naming the
    ///   lowest numbered train whose service needs it; or, under traffic
    ///   control (Stage T), ``GameError/trackReserved(_:)`` while a train
    ///   holds a span of the edge, which removing the platform's ends would
    ///   join to its neighbours.
    public mutating func removeTrackPlatform(_ id: StationID, on edge: TrackEdgeID, from start: Int64) throws(GameError) {
        guard station(id: id) != nil else { throw .unknownStation(id) }
        guard let index = network.platforms.firstIndex(where: { $0.station == id && $0.edge == edge && $0.start == start }) else {
            throw .invalidPlatform
        }
        let platform = network.platforms[index]
        if let train = trains.first(where: { serviceNeeds($0, platform) }) {
            throw .trainServiceActive(train.id)
        }
        try requireSpansUnheld(on: edge)

        network.removePlatform(at: index)
        abandonUnservedPassengers()
    }

    /// Whether `train`'s service needs `platform` (Stage S5): it waits at
    /// the platform's station with its head on the platform, or travels to
    /// that station along a path whose last edge is the platform's. Since
    /// Stage V2 also a passing place's (see ``isAtPassingPlace(_:)``): the
    /// platform of another station a service travels to, or stands at with
    /// its head on it, and while it stands there, every platform of its
    /// call, which it goes on to from there.
    private func serviceNeeds(_ train: Train, _ platform: TrackPlatform) -> Bool {
        guard let execution = train.execution,
              case .onEdge(let traversal, let offset)? = train.position, let edge = network.edge(traversal.edge)
        else { return false }
        let call = train.timetable[execution.stop].station
        let chainage = traversal.direction == .forward ? offset : edge.length - offset
        let headOn = traversal.edge == platform.edge && platform.start <= chainage && chainage <= platform.end
        switch execution {
        case .waitingAtStop:
            return platform.station == call && headOn
        case .travellingToStop:
            if isAtPassingPlace(train) { return headOn || platform.station == call }
            guard (train.movement.remainingEdges.last ?? traversal.edge) == platform.edge else { return false }
            return platform.station == call
                || (!pathEndsAtBerth(of: train, for: call) && pathEndsAtBerth(of: train, for: platform.station))
        }
    }

    /// Under traffic control (Stage T), refuses a change to the spans of
    /// `edge` while a train holds any of them (it stands on them or has
    /// reserved them): a reserved span must keep its meaning, and two trains
    /// in neighbouring spans must not end up sharing one.
    private func requireSpansUnheld(on edge: TrackEdgeID) throws(GameError) {
        guard isTrafficControlEnabled, let train = trains.first(where: { held($0).contains { $0.isSpan(of: edge) } }) else { return }
        throw .trackReserved(train.id)
    }

    /// The platforms of station `id` on the track network, in order along
    /// the track (Stage S4); empty for none or an unknown station.
    public func trackPlatforms(of id: StationID) -> [TrackPlatform] {
        network.platforms(of: id)
    }

    /// Whether `platform` fits its edge: the edge exists, the stretch lies
    /// within it and is level.
    private func isValidPlatform(_ platform: TrackPlatform) -> Bool {
        guard let geometry = network.geometry(of: platform.edge) else { return false }
        return 0 <= platform.start && platform.start < platform.end && platform.end <= geometry.length
            && geometry.height(at: platform.start) == geometry.height(at: platform.end)
    }

    /// Whether a node at `position` would lie in the world's ``bounds``, at
    /// a height in ``RailwayNetwork/heightRange``.
    private func isInWorld(_ position: WorldCoordinate) -> Bool {
        RailwayNetwork.heightRange.contains(position.z) && bounds.contains(position.plan)
    }

    /// What an edge `length` long on `structure` costs:
    /// ``ConstructionCosts/track`` times the structure's
    /// ``TrackStructure/costFactor`` for every
    /// ``ConstructionCosts/trackPricingLength`` of its length, rounded up,
    /// and at least one.
    ///
    /// - Throws: ``GameError/insufficientFunds(required:available:)`` when
    ///   the price does not even fit in a ``Money``, so no balance could pay
    ///   it; `required` is then the largest amount there is.
    private func edgeCost(length: Int64, structure: TrackStructure) throws(GameError) -> Money {
        let priced = ConstructionCosts.trackPricingLength
        let lengths = max(1, (length + priced - 1) / priced)
        let (units, overflowFactor) = lengths.multipliedReportingOverflow(by: structure.costFactor)
        let (price, overflow) = economy.costs.track.amount.multipliedReportingOverflow(by: units)
        guard !overflowFactor, !overflow else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
        return Money(price)
    }

    /// Builds a station standing at `point` (Stage F1) and charges
    /// ``ConstructionCosts/station``. Other stations may stand anywhere
    /// near it. It has no platforms until the track network gives it some
    /// (``addTrackPlatform(_:on:from:to:)``).
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/outOfBounds(_:)`` naming `point` when it lies outside
    ///   the world's ``bounds``, ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func buildStation(named name: String, at point: PlanPoint) throws(GameError) -> Station {
        guard Self.isValidName(name) else { throw .invalidName }
        guard bounds.contains(point) else { throw .outOfBounds(point) }
        let (id, nextID) = try Self.allocateID(from: nextStationID)
        try economy.spend(economy.costs.station)

        let station = Station(id: StationID(rawValue: id), name: name, point: point)
        nextStationID = nextID
        stations.append(station)
        return station
    }

    /// Sets station `id`'s operation mode (Phase 5F, see
    /// ``StationOperationMode``; the reference's
    /// `applyStationOperationToStation`). Free.
    ///
    /// Closing a station sends everyone waiting there away, counted as
    /// abandoned at their original station (the reference's
    /// `clearStationWaitingPassengers`), and so does any journey waiting
    /// elsewhere that still has to board, change or arrive at a closed
    /// station. The reference's automatic modes after the last train
    /// (`metroComputeStationAutoOperationMode`) are not ported: only the
    /// player sets the mode. Passengers on
    /// board stay on their train; nobody gets off at a closed station. The
    /// new mode changes the passengers released from now on.
    ///
    /// - Throws: ``GameError/unknownStation(_:)``.
    public mutating func setStationOperationMode(_ id: StationID, to mode: StationOperationMode) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard stations[index].operationMode != mode else { return }
        stations[index].operationMode = mode
        if mode == .closed {
            abandonPassengers(waitingAt: id)
        }
        // Forgets the release plan (the next release follows the new mode),
        // and sends away every waiting journey elsewhere that still needs
        // to board, change or arrive here.
        abandonUnservedPassengers()
    }

    /// Buys a new train and charges ``ConstructionCosts/train``.
    ///
    /// The new train is unplaced (its ``Train/position`` is `nil`); put it on
    /// the track with ``placeTrain(_:at:)``.
    ///
    /// - Throws: ``GameError/invalidName``, ``GameError/idsExhausted``, or
    ///   ``GameError/insufficientFunds(required:available:)``.
    @discardableResult
    public mutating func purchaseTrain(named name: String) throws(GameError) -> Train {
        guard Self.isValidName(name) else { throw .invalidName }
        let (id, nextID) = try Self.allocateID(from: nextTrainID)
        try economy.spend(economy.costs.train)

        let train = Train(id: TrainID(rawValue: id), name: name)
        nextTrainID = nextID
        trains.append(train)
        return train
    }

    // MARK: - Trains

    /// The train with `id`, or `nil` if there is none.
    public func train(id: TrainID) -> Train? {
        trains.first { $0.id == id }
    }

    /// Puts an unplaced train on the track at `position`. Placement is free.
    ///
    /// `position` must be on this world's track (Stage S3):
    /// ``TrainPosition/onEdge(_:offset:)`` on an edge, `0 <= offset <=` its
    /// length; a train with a body stands at an offset above 0 (at a node,
    /// at the end of the edge it arrived along; see ``TrainPosition``). Its
    /// body is laid back from the start of its edge the way a train could
    /// have come, the lowest numbered edge first where the track branches.
    /// Other trains at the same place do not matter. The train starts idle:
    /// rate 0 and no path.
    ///
    /// Under traffic control (Stage T) the train must also be able to take
    /// the track it would stand on, the junctions it would foul, and the
    /// way it would run by itself, to the end of its edge (see
    /// ``reservedResources(of:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (placement never moves a
    ///   train), ``GameError/invalidTrainPosition``, or, under traffic
    ///   control, ``GameError/trackReserved(_:)``.
    public mutating func placeTrain(_ id: TrainID, at position: TrainPosition) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        guard isOnTrack(position) else { throw .invalidTrainPosition }
        var train = trains[index]
        let length = train.length
        switch position {
        case .onEdge(let traversal, let offset):
            guard length == 0 || offset > 0, let trail = networkTrailBehind(traversal, offset: offset, length: length) else {
                throw .invalidTrainPosition
            }
            train.position = position
            train.trailEdges = trail
        }

        try admit(train, at: index)
    }

    /// Sets how many cars an unplaced train has (Phase 4.5 Stage S2),
    /// ``Train/carLength`` apart: ``Train/minimumCars`` to ``Train/maximumCars``. Each car
    /// added costs ``ConstructionCosts/car``; taking cars off refunds
    /// nothing. Cars that cost nothing are added whatever the balance, even
    /// a negative one. A train of more than one car is placed with its body behind
    /// its head along the track it could have come by (see
    /// ``placeTrain(_:at:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/invalidTrainLength``,
    ///   ``GameError/trainAlreadyPlaced(_:)`` (take it off the track first),
    ///   or ``GameError/insufficientFunds(required:available:)``.
    public mutating func setTrainCars(_ id: TrainID, to cars: Int) throws(GameError) {
        let index = try trainIndex(of: id)
        guard (Train.minimumCars...Train.maximumCars).contains(cars) else { throw .invalidTrainLength }
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }

        let added = Int64(cars - trains[index].cars)
        if added > 0 {
            let (price, overflow) = economy.costs.car.amount.multipliedReportingOverflow(by: added)
            guard !overflow else { throw .insufficientFunds(required: Money(.max), available: economy.balance) }
            // Free cars are added even in the red: `spend` would refuse a
            // price of 0 against a negative balance.
            if price > 0 { try economy.spend(Money(price)) }
        }
        trains[index].cars = cars
    }

    /// Renames station `id` (the reference's station rename). Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownStation(_:)`` or
    ///   ``GameError/invalidName``.
    public mutating func renameStation(_ id: StationID, to name: String) throws(GameError) {
        guard let index = stations.firstIndex(where: { $0.id == id }) else { throw .unknownStation(id) }
        guard Self.isValidName(name) else { throw .invalidName }
        stations[index].name = name
    }

    /// Renames line `id`. Free.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidName``.
    public mutating func renameLine(_ id: LineID, to name: String) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        guard Self.isValidName(name) else { throw .invalidName }
        lines[index].name = name
    }

    /// Sets line `id`'s colour, or `nil` for the app's own pick (the
    /// reference's line colour, from its `PRESET_COLORS` or any other).
    /// Free; no rule reads it.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func setLineColor(_ id: LineID, to color: LineColor?) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        lines[index].color = color
    }

    /// Sets the type of train `id`'s cars (the reference's `TRAIN_TYPES`),
    /// or `nil` for the standard car: what each car carries and how many
    /// doors it has (see ``TrainType``). Free, and only while the train is
    /// off the track, as its cars are (see ``setTrainCars(_:to:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainAlreadyPlaced(_:)``.
    public mutating func setTrainType(_ id: TrainID, to type: TrainType?) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].position == nil else { throw .trainAlreadyPlaced(id) }
        trains[index].type = type
    }

    /// Takes a placed train off the track. The train keeps its ID, name and
    /// timetable (and its period); its movement becomes ``TrainMovement/idle`` (rate 0, no
    /// path), so placing it again never resumes an old journey.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first).
    public mutating func unplaceTrain(_ id: TrainID) throws(GameError) {
        let (index, _) = try manuallyControlledTrain(id)

        trains[index].position = nil
        trains[index].trafficVisits = []
        trains[index].movement = .idle
        trains[index].trailEdges = []
        trains[index].reservation = []
    }

    /// Turns a placed train around where it stands, without moving it: its
    /// head goes to where its tail was, travelling its edge the other way,
    /// and its body lies back over the same track (see
    /// ``TrainPosition``). Reversing twice restores the original position
    /// exactly.
    ///
    /// The path is cleared, including where it stops, because it was a path
    /// for the other direction; the rate is kept. A reversed train therefore
    /// runs to the end of its edge and stops there until it is given a new
    /// path.
    ///
    /// Under traffic control (Stage T) the train's reservation goes with its
    /// path. A reversed train stands on the same track as before, but then
    /// runs to the end of its edge by itself, and must be able to take that
    /// way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (stop the service first), or, under traffic control,
    ///   ``GameError/trackReserved(_:)``.
    public mutating func reverseTrain(_ id: TrainID) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        var train = trains[index]

        switch position {
        case .onEdge(let traversal, let offset):
            (train.position, train.trailEdges) = reversedOnNetwork(traversal, offset: offset, trail: train.trailEdges, length: train.length)
        }
        train.movement.edges = []
        train.movement.cursor = 0
        train.movement.end = nil
        try admit(train, at: index)
    }

    // MARK: - Train movement

    /// Sets how many logical units a placed train may travel in each basic
    /// step (one game minute). 0 holds the train where it is and keeps its
    /// path, so setting a rate again resumes the same journey. Any
    /// non-negative `Int64` is accepted: travel adds distance to an offset
    /// only after checking that it is shorter than the rest of the edge, so
    /// no rate can overflow.
    ///
    /// Allowed while the train runs its timetable: a service never sets the
    /// rate. Between calls a service's train follows its running curve
    /// (Stage W2c, see ``ServiceRun``) whatever its rate, unless the rate is
    /// 0, which holds it (a service still gives it a path when a departure
    /// comes); the rate is how fast it goes only when its
    /// performance builds no curve for the way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/invalidMovementRate`` for a negative rate.
    public mutating func setTrainMovementRate(_ id: TrainID, to rate: Int64) throws(GameError) {
        let (index, _) = try placedTrain(id)
        guard rate >= 0 else { throw .invalidMovementRate }

        trains[index].movement.rate = rate
    }

    /// Enables movement using the train's configured km/h performance.
    /// Services still follow their acceleration/braking curve; manual
    /// movement uses the same top speed, converted to integer world units
    /// per minute. The old rate command remains for save/replay compatibility
    /// and explicit holds, rather than a second player speed setting.
    public mutating func useTrainPerformanceForMovement(_ id: TrainID) throws(GameError) {
        let (index, _) = try placedTrain(id)
        let speed = trains[index].performance.topSpeed
        let minutesPerHour = GameTime.secondsPerHour / GameTime.secondsPerMinute
        // Valid performances cap speed at 2^20, so this product fits Int64.
        trains[index].movement.rate = speed * WorldCoordinate.unitsPerMetre * 1000 / minutesPerHour
    }

    /// Sets how train `id` accelerates, brakes and coasts, and how fast it may
    /// run (Stage W2c; see ``Train/performance``): the running curves its
    /// services follow between calls. Placed or not, at no cost.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while it runs a service (its
    ///   run follows the curve of the performance it set off with), or
    ///   ``GameError/invalidTrainPerformance`` (see
    ///   ``TrainPerformance/isValid``).
    public mutating func setTrainPerformance(_ id: TrainID, to performance: TrainPerformance) throws(GameError) {
        let index = try trainIndex(of: id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard performance.isValid else { throw .invalidTrainPerformance }
        trains[index].performance = performance
    }

    /// Replaces a placed train's path with `traversals` (Stage S3): the form
    /// ``route(from:to:)`` returns. Each traversal must be one a train may
    /// take after the one before it (see ``transitions(after:)``), the first
    /// after the edge the train is on. The whole list is checked against the
    /// current track, then replaces the old path (``TrainMovement/edges``),
    /// and the cursor goes back to 0; an empty list clears it. The train
    /// never picks a way itself, and clearing its path does not move it: it
    /// still runs to the end of its edge at its rate (set the rate to 0 to
    /// hold it where it is).
    ///
    /// The path may stop part of the way along its last edge (Stage S5):
    /// `end` is how far along it the head stops, measured the way the train
    /// travels it (see ``TrainMovement/end``); `nil`, the default, runs to
    /// the end of that edge. The last edge is the last
    /// traversal, or the train's own edge when there are none. `end` must be
    /// below that edge's length, above 0 after a traversal, and not behind
    /// the train on its own edge; with no traversals and `end` where the
    /// head is, the train stands where it is. A path from
    /// ``path(from:toStation:length:)`` goes in unchanged, as
    /// `along: path.traversals, stoppingAt: path.end`.
    ///
    /// Under traffic control (Stage T) the train takes its whole new route
    /// at once, with everything its whole length covers on the way (see
    /// ``reservedResources(of:)``), in place of its old reservation; if
    /// another train holds any of it, nothing changes.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainNotPlaced(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` while the train runs its
    ///   timetable (the service owns the path; stop it first),
    ///   ``GameError/invalidContinuation`` (a step a train may not take, or
    ///   an `end` that does not fit), or, under traffic control,
    ///   ``GameError/trackReserved(_:)``.
    public mutating func setTrainContinuation(_ id: TrainID, along traversals: [TrackTraversal], stoppingAt end: Int64? = nil) throws(GameError) {
        let (index, position) = try manuallyControlledTrain(id)
        let (traversal, offset): (TrackTraversal, Int64) = switch position {
        case .onEdge(let traversal, let offset): (traversal, offset)
        }
        var arrival = traversal
        for next in traversals {
            guard transitions(after: arrival).contains(next) else { throw .invalidContinuation }
            arrival = next
        }
        if let end {
            guard end < network.edge(arrival.edge)!.length, end >= (traversals.isEmpty ? offset : 1) else { throw .invalidContinuation }
        }

        var train = trains[index]
        train.movement.edges = traversals.map(\.edge)
        train.movement.cursor = 0
        train.movement.end = end
        try admit(train, at: index)
    }

    /// Puts `candidate`, train `index` with a new place or path, into the
    /// world: under traffic control (Stage T) with the reservation of its
    /// route, in place of its old one, only if no other train holds track
    /// it needs (see ``reserving(_:)``); otherwise nothing changes.
    ///
    /// - Throws: ``GameError/trackReserved(_:)`` naming the lowest numbered
    ///   train holding such track.
    private mutating func admit(_ candidate: Train, at index: Int) throws(GameError) {
        switch reserving(candidate) {
        case .granted(let train): trains[index] = train
        case .held(let holder, _): throw .trackReserved(holder)
        }
    }

    // MARK: - Traffic control

    /// Turns traffic control on or off (Phase 4.6 Stage T, ARCHITECTURE
    /// decision 32; see ``isTrafficControlEnabled``).
    ///
    /// Turning it on works out, for every placed train in ID order, the
    /// track it needs now: what it stands on and the junctions it fouls
    /// (see ``heldResources(of:)``), and for a train with a way left to go
    /// the whole of it (see ``reservedResources(of:)``). If two trains need
    /// the same track nothing changes; otherwise every train takes its
    /// reservation and traffic control is on, all at once. Turning it on
    /// again changes nothing.
    ///
    /// Turning it off always succeeds: every reservation is dropped, and
    /// trains keep their positions, paths, timetables, services and lines,
    /// passing through each other again as before.
    ///
    /// - Throws: ``GameError/trainsShareTrack(_:_:)`` when turning it on:
    ///   the first train, in ID order, that needs track an earlier train
    ///   needs, and the earliest such train.
    public mutating func setTrafficControl(_ enabled: Bool) throws(GameError) {
        guard enabled else {
            isTrafficControlEnabled = false
            for index in trains.indices {
                trains[index].reservation = []
            }
            abandonUnservedPassengers()
            return
        }
        guard !isTrafficControlEnabled else { return }
        var needs: [(index: Int, resources: Set<TrackResource>, moves: Bool)] = []
        for index in trains.indices where trains[index].position != nil {
            let envelope = routeEnvelope(of: trains[index])
            if let earlier = needs.first(where: { network.fouls($0.resources, envelope.resources) }) {
                throw .trainsShareTrack(trains[earlier.index].id, trains[index].id)
            }
            needs.append((index, envelope.resources, envelope.moves))
        }
        isTrafficControlEnabled = true
        for need in needs where need.moves {
            trains[need.index].reservation = need.resources.sorted()
        }
        abandonUnservedPassengers()
    }

    // MARK: - Timetables

    /// Replaces a train's timetable with `stops`, in order (see
    /// ``ScheduledStop``), running once or, with a `period`, repeating every
    /// `period` seconds (see ``Train/timetablePeriod``; minutes before Stage
    /// W2a). An empty list without a period clears it. Free, and the train
    /// may be placed or not.
    ///
    /// The whole list is checked before anything changes: its times never go
    /// back in time, starting from second 0 (`0 <= arrival <= departure` at
    /// every stop, and each departure no later than the next stop's
    /// arrival), and every stop names a station of this world. A repeating
    /// timetable also needs a stop and a period of at least one second, and
    /// its times must not go back when it starts again: the last departure
    /// no later than the first arrival one period later. Equal times,
    /// repeated stations, stations without platforms, turning round at any
    /// stop and times the clock has already passed are all allowed; whether
    /// the train could keep to the timetable (a route between the stations,
    /// the travel time, where the train is now, the last stop leading back
    /// to the first) is not checked.
    ///
    /// Only the timetable and its period change. Setting one never places,
    /// moves, routes or stops the train, and never starts a service: only a
    /// service started with ``startTrainService(_:)`` reads the timetable.
    /// While a service runs, its timetable cannot be replaced: an index into
    /// the old timetable has no meaning in a new one. Stop the service, set
    /// the timetable, and start the service again. A train assigned to a
    /// line gets its timetables from the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
    ///   ``GameError/trainServiceActive(_:)``,
    ///   ``GameError/invalidTimetable`` (for the times or the period), or
    ///   ``GameError/unknownStation(_:)`` naming the first stop, in
    ///   timetable order, whose station does not exist.
    public mutating func setTrainTimetable(
        _ id: TrainID,
        to stops: [ScheduledStop],
        repeatingEvery period: Int64? = nil
    ) throws(GameError) {
        let index = try trainIndex(of: id)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        guard ScheduledStop.isTimetable(stops, period: period) else { throw .invalidTimetable }
        if let stop = stops.first(where: { station(id: $0.station) == nil }) {
            throw .unknownStation(stop.station)
        }

        trains[index].trafficVisits = []
        trains[index].timetable = stops
        trains[index].timetablePeriod = period
    }

    // MARK: - Timetable services

    /// Starts running the train's timetable as a service, stop by stop in
    /// timetable order, from the first stop to the last: once, or cycle
    /// after cycle for a repeating timetable (see ``Train/timetablePeriod``).
    ///
    /// The train must be stopped at the first stop's station (see
    /// ``stationsStoppedAt(by:)``; a platform shared with other stations is
    /// fine). It then waits there as if it had just arrived
    /// (``TimetableExecution/waitingAtStop(_:cycle:)`` with index 0). A
    /// service always starts from the first stop, however late it is. A
    /// timetable that runs once starts in its only cycle, so if its times
    /// have all passed it leaves every stop as soon as it can. A repeating
    /// timetable starts in the first cycle whose first departure is not
    /// before now, so the train leaves on time; a cycle that has begun
    /// already is not joined halfway. Starting changes nothing else; nothing
    /// moves until time passes (see ``advance(ticks:)`` for how a service
    /// runs, turns trains round and starts a timetable again). A train
    /// assigned to a line is sent out by the line.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``,
    ///   ``GameError/trainServiceActive(_:)`` if a service is already
    ///   running, ``GameError/noTimetable(_:)`` for an empty timetable,
    ///   ``GameError/trainNotPlaced(_:)``, or
    ///   ``GameError/trainNotAtFirstStop(_:)``.
    public mutating func startTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        let train = trains[index]
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard train.execution == nil else { throw .trainServiceActive(id) }
        guard let first = train.timetable.first else { throw .noTimetable(id) }
        guard train.position != nil else { throw .trainNotPlaced(id) }
        guard isStopped(train, at: first.station) else { throw .trainNotAtFirstStop(id) }

        trains[index].trafficVisits = []
        trains[index].execution = .waitingAtStop(0, cycle: train.startingCycle(at: clock.now))
        // Stage W2b: starting counts as arriving at the first stop now, so
        // the train dwells there before it leaves.
        trains[index].times = ServiceTimes(arrival: clock.now)
    }

    /// Stops the train's service, wherever it has got to. Only the
    /// automation ends: the train keeps its timetable, position, rate and
    /// path, so a train on its way to a stop carries on to it and
    /// stops there, now under manual control. Stopping a service is not a
    /// brake; set the rate to 0 to hold the train. A line's train is taken
    /// off the line first (``unassignTrain(_:)``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/trainOnLine(_:)``, or
    ///   ``GameError/trainServiceNotActive(_:)``.
    public mutating func stopTrainService(_ id: TrainID) throws(GameError) {
        let index = try trainIndex(of: id)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution != nil else { throw .trainServiceNotActive(id) }

        trains[index].execution = nil
        trains[index].times = nil
        trains[index].trafficVisits = []
        abandonRiders(of: id)
    }

    // MARK: - Service lines

    /// The line with `id`, or `nil` if there is none.
    public func line(id: LineID) -> ServiceLine? {
        lines.first { $0.id == id }
    }

    /// Creates a service line calling at `stops`, in order, with the
    /// standard window (06:00 to midnight), the default rate (one link a
    /// minute) and no trains in service. Free.
    ///
    /// A line is plan data: it never moves, routes or schedules a train.
    /// Whether its stations are joined by track is not checked; what its
    /// journey would take is derived by ``lineJourney(_:pattern:)``.
    ///
    /// - Throws, checked in this order: ``GameError/invalidName``,
    ///   ``GameError/invalidLineStops`` (fewer than two, or a station twice
    ///   in a row), ``GameError/unknownStation(_:)`` naming the first stop
    ///   whose station does not exist, or ``GameError/idsExhausted``.
    @discardableResult
    public mutating func createLine(named name: String, stops: [StationID]) throws(GameError) -> ServiceLine {
        guard Self.isValidName(name) else { throw .invalidName }
        try requireLineStops(stops)
        let (id, nextID) = try Self.allocateID(from: nextLineID)

        let line = ServiceLine(id: LineID(rawValue: id), name: name, stops: stops)
        nextLineID = nextID
        lines.append(line)
        passengerPlan = PassengerPlanCache()
        return line
    }

    /// Removes a line. Its ID is never handed out again. Its trains are no
    /// longer assigned to a line; a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service.
    ///
    /// - Throws: ``GameError/unknownLine(_:)``.
    public mutating func removeLine(_ id: LineID) throws(GameError) {
        let index = try lineIndex(of: id)
        lines.remove(at: index)
        abandonUnservedPassengers()
    }

    /// Replaces a line's stops with `stops`, in order. Its patterns keep
    /// their calls, as indices into the new stops.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops`` (on a ring also fewer than three, or
    ///   the same station first and last, see ``setLineRing(_:to:)``),
    ///   ``GameError/unknownStation(_:)`` naming the first stop whose
    ///   station does not exist, or ``GameError/invalidLinePattern`` if a
    ///   pattern would call past the new last stop (remove it first).
    public mutating func setLineStops(_ id: LineID, to stops: [StationID]) throws(GameError) {
        let index = try lineIndex(of: id)
        try requireLineStops(stops, ring: lines[index].isRing)
        guard lines[index].patterns.allSatisfy({ LinePattern.isCallList($0.calls, stopCount: stops.count) }) else {
            throw .invalidLinePattern
        }
        var changed = lines[index]
        changed.stops = stops
        guard changed.validRoutePreferences else { throw .invalidLineRoutePreference }
        lines[index].stops = stops
        abandonUnservedPassengers()
    }

    /// Makes a line a ring, or no longer one (decision 49, the `Ci/` metro
    /// game's `completeRingLine` and opening a ring with `metroSplitOpenRing`).
    /// Free.
    ///
    /// A ring's trains run on from its last stop back to the first, round
    /// and round, never turning round: the first of its trains in ID order,
    /// the third and so on the ``RingDirection/inner`` way, the others the
    /// ``RingDirection/outer`` way (see ``ServiceLine/ringDirection(of:)``).
    /// Making a line a ring makes its counts of trains in service even,
    /// down (the reference's `normalizeRingPairedTrainCaps`); making it a
    /// line again forgets when it last sent a train out the outer way.
    /// Trains already sent out keep their timetables either way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/invalidLineStops`` to make a ring of fewer than three
    ///   stops or of one calling at the same station first and last, or
    ///   ``GameError/invalidLinePattern`` to make a ring of a line with
    ///   patterns (the reference keeps a ring's route legs to one over the
    ///   whole ring, `consolidateRingRouteLegs`; its ring express is not
    ///   ported).
    public mutating func setLineRing(_ id: LineID, to isRing: Bool) throws(GameError) {
        let index = try lineIndex(of: id)
        if isRing {
            guard ServiceLine.isRingStopList(lines[index].stops) else { throw .invalidLineStops }
            guard lines[index].patterns.isEmpty else { throw .invalidLinePattern }
            let counts = lines[index].trainsInService
            lines[index].trainsInService = TrainsInService(
                peak: ServiceLine.paired(counts.peak), offPeak: ServiceLine.paired(counts.offPeak), low: ServiceLine.paired(counts.low)
            )
        } else {
            lines[index].outerLastDispatch = nil
        }
        if lines[index].isRing != isRing { lines[index].routePreferences = [] }
        lines[index].isRing = isRing
        abandonUnservedPassengers()
    }

    /// Replaces one service's preferences atomically. Missing physical
    /// track/platform is permitted: rebuilding the map falls back to the
    /// automatic route until that preference becomes usable again.
    public mutating func setLineRoutePreferences(_ id: LineID, to routes: [LineRoutePreference], pattern: Int? = nil) throws(GameError) {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        if let pattern, !lines[index].patterns.indices.contains(pattern) { throw .unknownLinePattern(pattern) }
        var changed = lines[index]
        if let pattern { changed.patterns[pattern].routePreferences = routes }
        else { changed.routePreferences = routes }
        guard changed.validRoutePreferences else { throw .invalidLineRoutePreference }
        lines[index] = changed
        abandonUnservedPassengers()
    }

    /// Sets the performance a line's journey times are worked out with
    /// (Stage W2c; see ``ServiceLine/performance`` and
    /// ``lineJourney(_:pattern:)``). Trains already sent out keep their
    /// timetables.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidTrainPerformance`` (see
    ///   ``TrainPerformance/isValid``).
    public mutating func setLinePerformance(_ id: LineID, to performance: TrainPerformance) throws(GameError) {
        let index = try lineIndex(of: id)
        guard performance.isValid else { throw .invalidTrainPerformance }
        lines[index].performance = performance
        abandonUnservedPassengers()
    }

    /// Sets when a line runs during the day (see ``ServiceWindow``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidServiceWindow``.
    public mutating func setLineServiceWindow(_ id: LineID, to window: ServiceWindow) throws(GameError) {
        let index = try lineIndex(of: id)
        guard window.isValid else { throw .invalidServiceWindow }
        lines[index].window = window
        abandonUnservedPassengers()
    }

    /// Sets how many trains a line's own service, or its pattern at index
    /// `pattern`, is to run at each service level. Any count of 0 or more
    /// is kept as it is; how many it can run is derived (see
    /// ``lineTrainsInService(_:at:pattern:)``).
    ///
    /// On a ring (decision 49) each count is made even, down: a ring runs
    /// its trains in pairs, one each way.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidTrainsInService`` for a negative count.
    public mutating func setLineTrainsInService(_ id: LineID, to trains: TrainsInService, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard trains.isValid else { throw .invalidTrainsInService }
        if lines[index].isRing {
            lines[index].trainsInService = TrainsInService(
                peak: ServiceLine.paired(trains.peak), offPeak: ServiceLine.paired(trains.offPeak), low: ServiceLine.paired(trains.low)
            )
        } else if service == 0 {
            lines[index].trainsInService = trains
        } else {
            lines[index].patterns[service - 1].trainsInService = trains
        }
        abandonUnservedPassengers()
    }

    /// Sets which service level each minute of the day has, for every line.
    ///
    /// - Throws: ``GameError/invalidServiceDay`` unless the bands start at
    ///   minute 0 and strictly increase within the day.
    public mutating func setServiceDay(_ day: ServiceDay) throws(GameError) {
        guard day.isValid else { throw .invalidServiceDay }
        serviceDay = day
        abandonUnservedPassengers()
    }

    /// Sets the minutes a line's own service, or its pattern at index
    /// `pattern`, aims to keep between its trains, at the levels with a
    /// target; the other levels run the count set by
    /// ``setLineTrainsInService(_:to:pattern:)`` (see ``TargetHeadways``).
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)``,
    ///   ``GameError/unknownLinePattern(_:)``, or
    ///   ``GameError/invalidHeadway`` for a target outside `2...1440`.
    public mutating func setLineTargetHeadways(_ id: LineID, to headways: TargetHeadways, pattern: Int? = nil) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        guard headways.isValid else { throw .invalidHeadway }
        if service == 0 {
            lines[index].targetHeadways = headways
        } else {
            lines[index].patterns[service - 1].targetHeadways = headways
        }
        abandonUnservedPassengers()
    }

    /// Adds a pattern to a line, calling at `calls` (indices into the
    /// line's stops), after its other patterns, with no trains in service,
    /// no target headways and no trains; returns its index. Free.
    ///
    /// Calls that are a run of neighbouring stops make a short working;
    /// calls that leave stops out make an express, which passes them.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/invalidLinePattern`` on a ring (decision 49), or
    ///   unless there are two calls or more, strictly increasing, each an
    ///   index of one of the line's stops.
    @discardableResult
    public mutating func addLinePattern(_ id: LineID, calling calls: [Int]) throws(GameError) -> Int {
        let index = try lineIndex(of: id)
        guard !lines[index].isRing, LinePattern.isCallList(calls, stopCount: lines[index].stops.count) else { throw .invalidLinePattern }
        lines[index].patterns.append(LinePattern(calls: calls))
        return lines[index].patterns.count - 1
    }

    /// Removes a line's pattern at index `pattern`; the patterns after it
    /// move down one index. Its trains are no longer assigned to a line: a
    /// train on a round trip keeps its timetable and finishes the trip as
    /// an ordinary service, as when a line is removed.
    ///
    /// - Throws, checked in this order: ``GameError/unknownLine(_:)`` or
    ///   ``GameError/unknownLinePattern(_:)``.
    public mutating func removeLinePattern(_ id: LineID, at pattern: Int) throws(GameError) {
        let (index, service) = try lineService(id, pattern: pattern)
        lines[index].patterns.remove(at: service - 1)
        reindexPassengerJourneys(on: id, removing: pattern)
        abandonUnservedPassengers()
    }

    /// The line train `id` is assigned to, or `nil` if it is on none (or
    /// does not exist).
    public func assignedLine(of id: TrainID) -> LineID? {
        lines.first { line in (0..<line.serviceCount).contains { line.trains(ofService: $0).contains(id) } }?.id
    }

    /// The index of the pattern train `id` is assigned to, or `nil` if it
    /// is assigned to a line's own service, or to no line.
    public func assignedPattern(of id: TrainID) -> Int? {
        for line in lines {
            if let pattern = line.patterns.firstIndex(where: { $0.trains.contains(id) }) { return pattern }
        }
        return nil
    }

    /// Assigns a train to a line's own service, or to its pattern at index
    /// `pattern`, which from then on runs the train's timetable and
    /// service: it sends the train out on round trips from its first call
    /// (see ``advance(ticks:)``). Free, and the train may be placed or not,
    /// anywhere; only a train stopped at the first call can be sent out.
    /// Nothing else changes until the service sends the train out.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)``,
    ///   ``GameError/unknownLine(_:)``, ``GameError/unknownLinePattern(_:)``,
    ///   ``GameError/trainOnLine(_:)`` if it is on a line already (this one
    ///   included), or ``GameError/trainServiceActive(_:)`` while it runs a
    ///   service of its own (stop it first).
    public mutating func assignTrain(_ id: TrainID, to line: LineID, pattern: Int? = nil) throws(GameError) {
        let index = try trainIndex(of: id)
        let (target, service) = try lineService(line, pattern: pattern)
        guard assignedLine(of: id) == nil else { throw .trainOnLine(id) }
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }

        if service == 0 {
            lines[target].trains.insert(id, at: lines[target].trains.firstIndex { $0 > id } ?? lines[target].trains.count)
        } else {
            let roster = lines[target].patterns[service - 1].trains
            lines[target].patterns[service - 1].trains.insert(id, at: roster.firstIndex { $0 > id } ?? roster.count)
        }
        abandonUnservedPassengers()
    }

    /// Takes a train off its line, whichever of the line's services it is
    /// on. Only the assignment ends: a train on a round trip keeps its
    /// timetable and finishes the trip as an ordinary service, which can
    /// then be stopped like any other.
    ///
    /// - Throws, checked in this order: ``GameError/unknownTrain(_:)`` or
    ///   ``GameError/trainNotOnLine(_:)``.
    public mutating func unassignTrain(_ id: TrainID) throws(GameError) {
        _ = try trainIndex(of: id)
        guard let index = lines.firstIndex(where: { $0.id == assignedLine(of: id) }) else { throw .trainNotOnLine(id) }

        lines[index].trains.removeAll { $0 == id }
        for pattern in lines[index].patterns.indices {
            lines[index].patterns[pattern].trains.removeAll { $0 == id }
        }
        abandonUnservedPassengers()
    }

    // MARK: - Time

    public mutating func pause() {
        clock.pause()
    }

    public mutating func resume() {
        clock.resume()
    }

    public mutating func setSpeed(_ speed: GameSpeed) {
        clock.setSpeed(speed)
    }

    /// How many destinations each origin sends passengers to in the plan
    /// of the day that ends at midnight `now`: `release`'s, worked out at
    /// `time`, unless that is `now` itself (a call that starts at
    /// midnight, or a service level that changes there, works out the new
    /// day's plan first). Then the plan is worked out afresh as at the
    /// day's last second, as a call across midnight has it, so a day's
    /// growth does not depend on where calls of ``advance(ticks:)`` end.
    func reachedStations(endingDayAt now: GameTime, release: PassengerRelease?, workedOutAt time: GameTime) -> [StationID: Int] {
        guard townGrowth != nil, accounts.mode == .management else { return [:] }
        guard time >= now, now.seconds > Int64.min else { return release.map(Self.reachedStations) ?? [:] }
        var day = self
        day.clock = GameClock(now: GameTime(seconds: now.seconds - 1))
        day.passengerPlan = PassengerPlanCache()
        return day.passengerRelease().map(Self.reachedStations) ?? [:]
    }

    /// Advances the simulation by `ticks` ticks at the current speed.
    ///
    /// A basic step is one game second (Stage W2a). A tick runs the speed's
    /// tenths of a second (see ``GameSpeed/tenthsPerTick``): none while
    /// paused, a second every 10 ticks at ``GameSpeed/x1`` (the tenths that
    /// make no whole second yet wait in ``GameClock/pendingTenths``), a
    /// minute at ``GameSpeed/normal``.
    ///
    /// Trains move every second (phase 2 below), each second its share of
    /// its rate per minute: second `s` of a minute (from 0) takes a train
    /// `⌊rate·(s + 1)/60⌋ − ⌊rate·s/60⌋` units, so a whole minute takes it
    /// its rate. Services run on the second too (Stage W2b): a train dwells
    /// at each call (see ``ServiceTimes``) and leaves at whichever second
    /// its doors have closed; between calls it follows its run's running
    /// curve instead of its rate (Stage W2c, see ``ServiceRun``). The
    /// accounts, passengers and dispatch stay on whole minutes. So each
    /// step from second `t` to `t + 1` has these phases, each taking the
    /// lines in ascending ``LineID`` order and the trains in ascending
    /// ``TrainID`` order:
    ///
    /// - **At a whole minute `T`** only: the accounts settle (G1c), then
    ///   **passengers** (G1a): every pair of stations with trips (see
    ///   ``hourlyDemand(from:to:)``), by ascending origin and then
    ///   destination, releases its share of minute `T` at the origin, where
    ///   the passengers wait for their trip (see
    ///   ``passengerTrip(from:to:)``) or, when the station is full, leave at
    ///   once (see ``StationPassengers/capacity``). A pair's share of a
    ///   minute is its trips of the hour, and of the next hour, weighted by
    ///   how far into the hour the minute is: `((60 − m)·R_h + m·R_{h+1}) /
    ///   3600` at minute `m` of hour `h`, with the fraction kept for the next
    ///   minute. So a pair releases exactly its daily trips over any 1440
    ///   minutes in a row. This reads no train and changes none.
    /// 0. **Dispatch at `T`**, only at a whole minute: each line sends out
    ///    at most one of its trains on a round trip (see below). Its service
    ///    starts as if it had just arrived at the first call, where it
    ///    dwells before it leaves.
    /// 1. **Services at `t`.** Every train whose service waits at a stop
    ///    moves its dwell on, and then leaves if it is due:
    ///
    ///    - **Doors open.** ``ServiceDwell/doorOpening`` after the train
    ///      arrived, those riding it to the stop's station get off (at a
    ///      stop where it turns round or its service ends, everyone does),
    ///      and, before its last stop, a train on a line takes on the
    ///      passengers waiting there for its line and direction whose
    ///      destination it calls at before it next turns round, the
    ///      farthest first, up to its ``Train/capacity`` (G1b; see
    ///      ``riders(of:)`` and ``PassengerLedger``). Both use the doors at
    ///      once, so the exchange lasts the larger number's
    ///      ``Train/exchangeSeconds(_:)``.
    ///    - **Doors held open.** At each whole minute while they are open,
    ///      newly released passengers board too, and the exchange runs on.
    ///    - **Doors closing.** They start closing at the first second when
    ///      the exchange is over and, once they have closed, the train will
    ///      have dwelt its least (``ServiceDwell/minimumDwell(isTerminal:)``)
    ///      and reached its scheduled departure: an early train holds for
    ///      its timetable, a late one leaves as soon as it can.
    ///    - **Departure**, ``ServiceDwell/doorClosing`` later (see below).
    ///      Departures are those of the service's cycle: the timetable's
    ///      times shifted by whole periods. A full train counts those it
    ///      could not take as refused, and a line's train counts the
    ///      departure (G1c). The train sets off on a run (Stage W2c, see
    ///      ``run(of:length:scheduled:)``): in the seconds from the
    ///      scheduled departure to the scheduled arrival when its
    ///      performance builds a curve for them, otherwise as fast as it
    ///      can.
    ///
    ///    A travelling train held up on its run (see phase 2) sets off on a
    ///    new one from a stand over the way left, as fast as it can, once
    ///    it has a rate and can move (see ``resumeRun(_:at:)``). A service
    ///    stopped at a passing place (Stage V2) goes on to its call once it
    ///    can take the route there, as fast as it can (see ``goOn(_:held:memo:)``).
    /// 1b. **The dispatcher at `T`** (Stage V2), only at a whole minute,
    ///    under traffic control: of the trains in a deadlock (see
    ///    ``deadlockedTrains()``), the first whose service is due to leave
    ///    or stands at a passing place, and has a passing place that lets
    ///    another of them go, sets off for it (see ``resolveDeadlock(memo:)``).
    /// 2. **Movement.** Every train with a rate above 0 travels its share
    ///    for second `t`: along its service's run, the curve's distance at
    ///    `t + 1` less at `t`; otherwise its share of its rate (see
    ///    ``TrainMovement``). A travelling train that could not keep to its
    ///    run (a rate of 0, or track ahead removed) drops it (see
    ///    ``dropRunsHeldUp(endingAt:)``).
    /// 3. The clock moves on to `t + 1`.
    /// 4. **Arrivals.** Every train whose service is travelling to a stop
    ///    and that is now stopped at that stop's station (see
    ///    ``stationsStoppedAt(by:)``) waits at that stop, arriving at
    ///    `t + 1`; its dwell starts in phase 1 of the next step.
    ///
    /// Without traffic control trains do not interact, so the order only
    /// fixes when each is updated. Between the seconds at which something
    /// happens (a whole minute, a dwell moving on, a run's end, a train
    /// coming to the end of its route, and under traffic control the track
    /// a waiting departure needs coming free) only movement does, and it depends
    /// on the map and the clock alone, so those seconds are taken together:
    /// they move every train exactly as far as one second at a time would. Whenever the clock can
    /// hold the whole batch, `advance(ticks: n)` is the same as `n` calls
    /// of `advance(ticks: 1)`, and one tick at a speed the same as ticks at
    /// slower speeds that run the same seconds, apart from the speed
    /// itself. (Near the clock's limit a batch is rejected whole, while
    /// single ticks may still fit one at a time.)
    ///
    /// A train that cannot enter the next edge of its path (the edge was
    /// removed after the path was set) waits at the end of its edge; edge
    /// IDs are never reused, so it waits until it is given a new path.
    /// Distance a train cannot use is dropped, so a train never catches up.
    ///
    /// **Services** (see ``startTrainService(_:)``). A service never leaves a
    /// stop before its scheduled departure, and never before its dwell
    /// there is over (phase 1). Starting a service counts as arriving at
    /// its first stop. Leaving stop `i`:
    ///
    /// - A stop marked ``ScheduledStop/reverses`` first turns the train
    ///   round where it stands, as ``reverseTrain(_:)`` would, and the rest
    ///   of the departure starts from there.
    /// - At the last stop of a timetable that runs once, or of the last
    ///   cycle whose times fit, the service is complete: it ends, and the
    ///   train stays where it is, keeping its timetable and rate.
    /// - Otherwise the service gives the train the path
    ///   ``path(from:toStation:length:)`` finds to where it stops for the
    ///   station of the next call (a berth of one of the station's platforms
    ///   that the train fits; Stage S5), and the train travels there. The next call is stop `i + 1`; after the last
    ///   stop of a repeating timetable it is stop 0 of the next cycle. The
    ///   service never turns the train except at a stop marked to, and never
    ///   sets the rate: a train with rate 0 gets its path and stays where it
    ///   is.
    /// - A path of no distance means the train is already stopped at the
    ///   next call's station (a repeated station, a platform both share, or
    ///   a repeating timetable that ends where it starts). It arrives there
    ///   at once, and dwells there as at any call.
    /// - A train the service turns round, or leaves at its last stop, stands
    ///   where it is: its path now ends there (see ``TrainMovement/end``), so
    ///   it does not run on along its edge.
    /// - Without a route the train waits at its stop, not turned round, and
    ///   later steps try again, turning it first again: after a command
    ///   changes the map, a route may appear. Within one call the map cannot
    ///   change, so the route is looked up at most once per call.
    ///
    /// A travelling train follows its path like any other; if track ahead is
    /// removed it waits at the end of its edge, and no new route is looked
    /// up. Since Stage W2c the timetable's arrival times set how long each
    /// run takes, so a train that leaves on time arrives on time and one
    /// that leaves late arrives as late; they are not a limit (a train that
    /// cannot keep to its run arrives later).
    ///
    /// **Traffic control** (Stage T, see ``setTrafficControl(_:)``). A
    /// departure takes its whole route to the next call at once, turned
    /// round first where the stop says so (see ``reservedResources(of:)``);
    /// where another train holds some of it, nothing changes (the train is
    /// not turned round either) and the service tries again at the next
    /// step. A line's train is ready only if its first departure could take
    /// its route when it is sent out; one that cannot is not sent out, and
    /// the line's last dispatch stays as it was. Earlier departures in a
    /// step take their routes first, in train ID order. Trains move as they
    /// always have: the whole route was theirs before they set off. As a
    /// train moves on in phase 2, its reservation keeps only what it still
    /// needs (Stage U, see ``reservedResources(of:)``): track its tail has
    /// left is free for other trains from the next step on, and all of it
    /// is once it comes to the end of its route.
    ///
    /// **Dispatch** (see ``assignTrain(_:to:pattern:)``). Each service of a
    /// line (its own, then its patterns in order) sends a train out at `T`
    /// when all of these hold:
    ///
    /// - `T` is minute 0 or later, the line's window is open, the
    ///   service's journey can be driven (see ``lineJourney(_:pattern:)``),
    ///   and at the level of `T` it runs trains beside the services before
    ///   it (see ``lineTrainsInService(_:at:pattern:)``);
    /// - that headway (see ``lineHeadway(_:at:pattern:)``) has passed since
    ///   the service last sent a train out;
    /// - fewer of its trains run a service than it runs then; and
    /// - one of its trains is ready: without a service, placed, with a rate
    ///   above 0, stopped at the first call's station (see
    ///   ``stationsStoppedAt(by:)``), and able to drive the whole round trip
    ///   from there as it faces or turned round, whichever is shorter (as it
    ///   faces when they are equal).
    ///
    /// The first ready train in ID order gets a timetable for one round trip
    /// sent out at `T`, and its service starts at the first call, where it
    /// dwells (phase 1): the timetable has it leave
    /// ``ServiceDwell/terminalMinimum`` after `T`. The times come from that
    /// trip at the line's rate, with the dwells of ``ServiceLine``: out to
    /// the last call, where it turns round, and back to the first, where it
    /// turns round and the service ends; stops a pattern does not call at
    /// are not in the timetable. The train then waits there until its service
    /// sends it out again. So a service never runs more trains than it runs
    /// at its level: when it runs fewer, the trains coming back wait at the
    /// first call; when it runs more, only trains waiting there can go. A
    /// train late back makes the next one leave late, never early.
    ///
    /// When a whole minute changes no train (no train moves, no service's
    /// dwell moves on, no service leaves, arrives or ends, and no line
    /// sends a train out), no later minute of this call can change anything
    /// before the minute of the next second at which a service's dwell
    /// moves on by itself (see ``nextServiceEvent(after:)``), or a slow run
    /// takes its train on (see ``nextRunMove(from:)``), or the next
    /// minute at which a line's service with a ready train might send it
    /// out (the map and every train's inputs stay the same until the next
    /// command, a departure that found no route finds none later in the
    /// call, one whose route is held finds it held until some train moves,
    /// and a line's window, level and headways change only at known
    /// minutes), so the clock moves on at once to that minute, or to the
    /// end of the batch, releasing each skipped minute's passengers on the
    /// way. While passengers are released and a train waits with its doors
    /// open, minutes are not skipped: those released may board. This is an
    /// exact shortcut, not an approximation.
    ///
    /// - Throws: ``GameError/clockOverflow`` if game time would pass the
    ///   largest second the clock can hold. This is checked before any train
    ///   or the clock changes, so a rejected call changes nothing.
    /// - Precondition: `ticks >= 0`.
    public mutating func advance(ticks: Int) throws(GameError) {
        let steps = try clock.basicSteps(forTicks: ticks)
        clock.keep(pendingTenths: steps.pendingTenths)
        var remaining = steps.seconds
        // Services whose departure found no route in this call. Nothing can
        // change the map or move a waiting train before the call ends, so
        // looking again would give the same answer.
        var unroutable: Set<TrainID> = []
        var memo = DispatchMemo()
        // Departures due now whose routes other trains hold (Stage T), each
        // with the track it waits for: tried again at the next step.
        var held: [HeldRoute] = []
        // Worked out only when the call steps at all: a paused game's calls
        // cost nothing.
        // A network plan kept from an earlier call is used only while all
        // it was worked out from is unchanged, the service level included.
        if remaining > 0 && passengerRoutingMode == .network, passengerPlan.plan != nil,
           passengerPlan.key != passengerPlanKey() {
            passengerPlan = PassengerPlanCache()
        }
        var release = remaining > 0 ? passengerRelease() : nil
        // When `release` was worked out: midnight's growth reads the plan
        // of the day that ended.
        var releasedFrom = clock.now
        var passengerLevels = lines.map { serviceLevel(of: $0.id, at: clock.now) }
        let minute = GameTime.secondsPerMinute
        while remaining > 0 {
            let start = clock.now
            var changed = false
            // Stage U2: trains following others take what has freed ahead of
            // them first, before any train sets off.
            if extendAuthorities() {
                changed = true
            }
            if start.isWholeMinute {
                if passengerRoutingMode == .network {
                    let levels = lines.map { serviceLevel(of: $0.id, at: start) }
                    if levels != passengerLevels {
                        if let release { keepRemainders(of: release) }
                        passengerPlan = PassengerPlanCache()
                        release = passengerRelease()
                        releasedFrom = start
                        passengerLevels = levels
                    }
                }
                // Items 4 and 5: towns grow from the day that ended, and
                // events start and end, at midnight.
                let midnight = (demandEvents != nil || townGrowth != nil) && start.seconds % GameTime.secondsPerDay == 0
                if midnight {
                    growTowns(reached: reachedStations(endingDayAt: start, release: release, workedOutAt: releasedFrom))
                    startDemandEventDay(dayIndex(of: start))
                }
                // Weekly demand and events: each day releases its own day's
                // trips.
                if midnight || demandDay != nil && passengerPlan.day != demandDay {
                    if let release { keepRemainders(of: release) }
                    passengerPlan = PassengerPlanCache()
                    release = passengerRelease()
                    releasedFrom = start
                }
                settleAccounts(at: start, memo: &memo)
                if release != nil {
                    releasePassengers(at: start, &release!)
                }
                if dispatchTrains(memo: &memo) {
                    changed = true
                }
            }
            // Stage W2b: every service's dwell, and the departures due now.
            held = []
            // V3 (decision 59): the plan from the world as the step finds
            // it, kept for every decision the step makes.
            memo.directions.stepTraffic = nil
            let traffic = trafficPlan(memo: &memo.directions)
            let trafficKey = memo.directions.traffic?.key
            memo.directions.stepTraffic = traffic
            recordTrafficVisits(traffic, before: nil)
            if runServices(at: start, unroutable: &unroutable, held: &held, memo: &memo) {
                changed = true
            }
            // Stage V2: once a minute, the dispatcher sends a service of a
            // deadlock to a passing place.
            if start.isWholeMinute, let resolved = resolveDeadlock(memo: &memo) {
                held.removeAll { $0.candidate.id == resolved }
                changed = true
            }
            // The seconds to the end of this minute, or of the batch, or to
            // the next second at which a service's dwell moves on or a
            // train comes to the end of its route: they move the trains
            // exactly as far as one second at a time would, and nothing
            // else happens in them.
            let second = start.secondOfMinute
            var span = min(remaining, minute - second)
            if let event = nextServiceEvent(after: start) {
                let (gap, overflow) = event.seconds.subtractingReportingOverflow(start.seconds)
                span = overflow ? span : min(span, gap)
            }
            if let end = secondsUntilARouteEnds(from: start, within: span) {
                span = end
            }
            // Stage U: or to the second at which trains moving on have
            // released enough track behind them for a departure that waits
            // for its route, which then tries again, or (Stage U2) for a
            // train following them to take more of its route.
            if span > 1, !held.isEmpty || trains.contains(where: isFollowing),
               let freed = secondsUntilARouteFrees(held, from: start, within: span, memo: &memo) {
                span = freed
            }
            if !traffic.waits.isEmpty {
                span = 1
            } else if span > 1, trafficPlanKey() != trafficKey {
                // A departure or a visit in this step changed what the plan
                // is derived from: when the plan it gives schedules a wait,
                // the next second works it out again, as a step every second
                // would (decision 59, point 13).
                memo.directions.stepTraffic = nil
                if !trafficPlan(memo: &memo.directions).waits.isEmpty { span = 1 }
                memo.directions.stepTraffic = traffic
            }
            let beforeTraffic = traffic.waits.isEmpty ? nil : trains
            if moveTrains(from: start, for: span) {
                changed = true
            }
            if dropRunsHeldUp(endingAt: Self.saturating(start, plus: span)) {
                changed = true
            }
            clock.advance(basicSteps: span)
            remaining -= span
            recordTrafficVisits(traffic, before: beforeTraffic)
            memo.directions.stepTraffic = nil
            if recordArrivals() {
                changed = true
            }
            if !changed, span == minute, traffic.waits.isEmpty {
                // A closed network may have no release plan and no ready
                // train. It must still wake when passenger service opens.
                let passengerWake: Int64?
                if passengerRoutingMode == .network {
                    let levels = lines.map { serviceLevel(of: $0.id, at: clock.now) }
                    passengerWake = levels != passengerLevels ? 0 : lines.compactMap {
                        $0.nextChange(after: clock.now, in: serviceDay)
                    }.min().map { Self.minutes(from: clock.now, until: $0) }
                } else {
                    passengerWake = nil
                }
                // Weekly demand, events and town growth: the next day
                // releases its own trips. The second of the day, without
                // multiplying back (a save's clock may be near the end of
                // time). At midnight itself that is 0: the next step handles
                // it, and skipping it would lose the day's growth and events.
                let day = GameTime.secondsPerDay
                let dayWake: Int64? = demandDay != nil || townGrowth != nil ? {
                    let intoDay = (clock.now.seconds % day + day) % day
                    let left = (day - intoDay) % day
                    return (left + GameTime.secondsPerMinute - 1) / GameTime.secondsPerMinute
                }() : nil
                let wake = [
                    wholeMinutesUntilNextServiceEvent(passengersWaiting: release != nil), minutesUntilNextDispatch(memo: &memo),
                    minutesUntilLineWaitsChange(memo: &memo), passengerWake, dayWake,
                ].compactMap { $0 }.min()
                let idle = min(remaining / minute, wake ?? remaining / minute)
                if release != nil || accounts.mode == .management {
                    // Releasing passengers (G1a) and settling the accounts
                    // (G1c) change no train, so the minutes skipped still do
                    // theirs, minute by minute.
                    for step in 0..<idle {
                        let time = GameTime(seconds: clock.now.seconds + step * minute)
                        settleAccounts(at: time, memo: &memo)
                        if release != nil {
                            releasePassengers(at: time, &release!)
                        }
                    }
                }
                clock.advance(basicSteps: idle * minute)
                remaining -= idle * minute
            }
        }
        if let release {
            keepRemainders(of: release)
        }
    }

    /// `time` plus `minutes` whole minutes, or `nil` if that does not fit in
    /// a ``GameTime``.
    static func time(_ time: GameTime, plusMinutes minutes: Int64) -> GameTime? {
        let (seconds, long) = minutes.multipliedReportingOverflow(by: GameTime.secondsPerMinute)
        let (sum, overflow) = time.seconds.addingReportingOverflow(seconds)
        return long || overflow ? nil : GameTime(seconds: sum)
    }

    /// The whole minutes from `now`, the start of a minute, until the start
    /// of the first minute at or after `time`, which is not before `now`;
    /// `Int64.max` if that is more than an `Int64` holds.
    static func minutes(from now: GameTime, until time: GameTime) -> Int64 {
        let (gap, overflow) = time.seconds.subtractingReportingOverflow(now.seconds)
        guard !overflow else { return .max }
        let minute = GameTime.secondsPerMinute
        return gap / minute + (gap % minute == 0 ? 0 : 1)
    }

    /// What dispatching works out once per call of ``advance(ticks:)``:
    /// no command can come within a call, so the map, the lines' stops,
    /// patterns and rates and an idle train's position stay the same, and
    /// so do these.
    struct DispatchMemo {
        /// Each service's journey (see ``lineJourney(_:pattern:)``), by line
        /// and service (see ``ServiceLine/serviceCount``), once looked up.
        var journeys: [LineID: [Int: LineJourney?]] = [:]
        var capacityLayouts: [LineID: LineCapacityLayout] = [:]
        var capacities: [LineID: [Int: ServiceCapacityProfile?]] = [:]
        var outerCapacityJourneys: [LineID: LineJourney?] = [:]
        /// V1 complete direction plans, local to this advance.
        var directions = DirectionMemo()
        /// Each train's round trip from where it stood idle (its position
        /// and body) when it was looked up, or
        /// `nil` if it had none.
        var trips: [TrainID: (from: TrainPlacement, trip: LineTrip?)] = [:]
    }

    /// Phase 0 of a basic step: each line, in ascending ID order, and on it
    /// each service, its own first and then its patterns in order, sends
    /// out at most one of its trains (see ``advance(ticks:)``). Its service
    /// starts at the first call as if it had just arrived there (Stage
    /// W2b): it dwells there, and leaves when its doors have closed.
    /// Returns whether any was sent out.
    ///
    /// Under traffic control (Stage T) the train is sent out only when it
    /// could take its route now (see ``readyTrain(of:_:memo:)``); it takes
    /// it when it leaves, and waits for it like any service if another
    /// train has taken some of it meanwhile.
    ///
    /// A ring (decision 49) sends its trains out each way on its own: each
    /// way is a stream (see ``ServiceLine/dispatchStreams``), the streams
    /// taken inner way first.
    private mutating func dispatchTrains(memo: inout DispatchMemo) -> Bool {
        let now = clock.now
        var dispatched = false
        for index in lines.indices {
            for stream in lines[index].dispatchStreams where !lines[index].trains(of: stream).isEmpty {
                let line = lines[index]
                guard isDispatchDue(line, stream, at: now, memo: &memo),
                      let (ready, trip) = readyTrain(of: line, stream, memo: &memo),
                      let timetable = trip.timetable(calling: line.stops, sentOutAt: now)
                else { continue }
                trains[ready].trafficVisits = []
                trains[ready].timetable = timetable
                trains[ready].timetablePeriod = nil
                trains[ready].execution = .waitingAtStop(0)
                // Stage W2b: the train is sent out as if it had just
                // arrived at the first call; it dwells there first.
                trains[ready].times = ServiceTimes(arrival: now)
                lines[index].recordDispatch(of: stream, at: now)
                dispatched = true
            }
        }
        return dispatched
    }

    /// Whether `line`'s `stream` sends a train out at `now` if one is
    /// ready: not before second 0; the line's window is open and the
    /// stream's service runs trains then (see
    /// ``plannedService(of:_:at:memo:)``); a headway of that level has
    /// passed since the stream's last dispatch; and fewer of its trains
    /// run a service than it runs then: on a ring each way runs half the
    /// trains (decision 49), at the ring's headway, which is each way's.
    func isDispatchDue(_ line: ServiceLine, _ stream: DispatchStream, at now: GameTime, memo: inout DispatchMemo) -> Bool {
        guard now.seconds >= 0, let planned = plannedService(of: line, stream.service, at: now, memo: &memo) else { return false }
        if let last = line.lastDispatch(of: stream) {
            guard let due = Self.time(last, plusMinutes: planned.headway), due <= now else { return false }
        }
        let running = line.trains(of: stream).count { id in train(id: id)?.execution != nil }
        return running < (stream.direction == nil ? planned.trains : planned.trains / 2)
    }

    /// The trains `line`'s service `service` runs at `now` and the headway
    /// between them, beside the services before it (see
    /// ``ServiceLine/services(at:roundTrips:)``), or `nil` when the line's
    /// window is closed, or the service runs none then or its journey
    /// cannot be driven.
    private func plannedService(of line: ServiceLine, _ service: Int, at now: GameTime, memo: inout DispatchMemo) -> (trains: Int, headway: Int64)? {
        guard line.window.contains(minuteOfDay: now.minuteOfDay) else { return nil }
        var roundTrips: [Int64?] = []
        var capacities: [ServiceCapacityProfile?] = []
        let layout: LineCapacityLayout
        if let known = memo.capacityLayouts[line.id] { layout = known }
        else {
            layout = capacityLayout(of: line)
            memo.capacityLayouts[line.id] = layout
        }
        for earlier in 0...service {
            let journey: LineJourney?
            if let known = memo.journeys[line.id]?[earlier] {
                journey = known
            } else {
                journey = self.journey(of: line, service: earlier)
                memo.journeys[line.id, default: [:]][earlier] = journey
            }
            roundTrips.append(journey?.roundTripMinutes)
            if let known = memo.capacities[line.id]?[earlier] { capacities.append(known) }
            else {
                var outer: LineJourney?
                if line.isRing, !layout.blocks.isEmpty {
                    if let known = memo.outerCapacityJourneys[line.id] { outer = known }
                    else {
                        outer = self.journey(of: line, service: earlier, direction: .outer)
                        memo.outerCapacityJourneys[line.id] = .some(outer)
                    }
                }
                let profile = layout.blocks.isEmpty ? nil : journey.map {
                    capacityProfile(of: line, service: earlier, journey: $0, layout: layout, outer: outer)
                }
                memo.capacities[line.id, default: [:]][earlier] = .some(profile)
                capacities.append(profile)
            }
        }
        guard roundTrips[service] != nil else { return nil }
        return line.services(at: serviceDay.level(atMinuteOfDay: now.minuteOfDay), roundTrips: roundTrips, capacities: capacities).plans[service]
    }

    /// The first of the trains of `line`'s service `service`, in ID order,
    /// that it can send out: one without a service, placed, with a rate
    /// above 0, stopped at the first call's station, and able to drive the
    /// whole round trip from there (see ``trip(of:service:for:)``); with
    /// its index and that trip. Under traffic control (Stage T) it must
    /// also be able to take the route of its first departure now; one whose
    /// default and alternative routes cannot be taken is not ready, and
    /// tries again at the next step.
    private func readyTrain(of line: ServiceLine, _ stream: DispatchStream, memo: inout DispatchMemo) -> (index: Int, trip: LineTrip)? {
        for id in line.trains(of: stream) {
            guard let index = trains.firstIndex(where: { $0.id == id }),
                  let trip = readyTrip(of: trains[index], on: line, stream.service, memo: &memo)
            else { continue }
            if isTrafficControlEnabled, let leaving = firstDeparture(of: trains[index], on: trip, calling: line.stops),
               case .held = reservingDeparture(leaving, memo: &memo.directions) {
                continue
            }
            return (index, trip)
        }
        return nil
    }

    /// The round trip `line`'s service `service` would send `train` on now,
    /// without traffic control: `nil` unless the train has no service, is
    /// placed, has a rate above 0, is stopped at the service's first call
    /// and can drive the whole round trip from there (see
    /// ``trip(of:service:for:)``). Each trip is looked up once per call of
    /// ``advance(ticks:)`` for where the train stands.
    func readyTrip(of train: Train, on line: ServiceLine, _ service: Int, memo: inout DispatchMemo) -> LineTrip? {
        let first = line.stops[line.calls(ofService: service)[0]]
        guard train.execution == nil, let placement = train.placement, train.movement.rate > 0,
              isStopped(train, at: first)
        else { return nil }
        if let known = memo.trips[train.id], known.from == placement { return known.trip }
        let trip = self.trip(of: line, service: service, for: train)
        memo.trips[train.id] = (placement, trip)
        return trip
    }

    /// `train` sent out now on `trip` (calling at the line's `stops`), as
    /// it would be once it has left the first call: turned round first if
    /// the trip says so, on its way along the first leg. `nil` if the
    /// trip's times would not fit.
    func firstDeparture(of train: Train, on trip: LineTrip, calling stops: [StationID]) -> Train? {
        guard let timetable = trip.timetable(calling: stops, sentOutAt: clock.now) else { return nil }
        var sent = train
        sent.timetable = timetable
        sent.timetablePeriod = nil
        sent.execution = .waitingAtStop(0)
        sent.times = ServiceTimes(arrival: clock.now)
        return leaving(sent, stop: 0, cycle: 0).train
    }

    /// The whole minutes from now, the start of a minute, until the first
    /// minute, at or after now, at which some service might send a train
    /// out, or `nil` if none can in this call.
    ///
    /// Only a service with a train ready counts: a train becomes ready only
    /// by arriving or finishing a service, which is a change, so after a
    /// step that changed nothing no other service can send one out before
    /// the next command. For such a service the answer is now if it is due
    /// now; otherwise the first of minute 0, the minute a headway since its
    /// last dispatch has passed, and the next minute its line's window
    /// opens or closes or the day's level changes. Until then nothing that
    /// decides whether it is due can change (what the services before it
    /// run changes only at those same minutes), so this is exact. A gap too
    /// large for an `Int64` is given as `Int64.max`.
    private func minutesUntilNextDispatch(memo: inout DispatchMemo) -> Int64? {
        let now = clock.now
        var soonest: Int64?
        for line in lines {
            for stream in line.dispatchStreams where !line.trains(of: stream).isEmpty {
                guard readyTrain(of: line, stream, memo: &memo) != nil else { continue }
                var wake: GameTime?
                if now.seconds < 0 {
                    wake = .zero
                } else if isDispatchDue(line, stream, at: now, memo: &memo) {
                    wake = now
                } else {
                    wake = line.nextChange(after: now, in: serviceDay)
                    if let last = line.lastDispatch(of: stream), let planned = plannedService(of: line, stream.service, at: now, memo: &memo),
                       let due = Self.time(last, plusMinutes: planned.headway), due > now {
                        wake = min(wake ?? due, due)
                    }
                }
                guard let wake else { continue }
                soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake))
            }
        }
        return soonest
    }

    /// Stage V2: the whole minutes from now, the start of a minute, until
    /// the first minute at or after now at which a line's service with a
    /// train that only its route keeps from being ready (see
    /// ``readyTrain(of:_:memo:)``) starts or stops being due to send it out,
    /// or `nil` if there is none. Such a train waits for its route while
    /// the line is due (see ``trainHoldingRoute(of:)``), so it may complete
    /// a deadlock, and the dispatcher looks only at whole minutes: an idle
    /// stretch must not skip the minute it starts or stops waiting. The
    /// minutes are those of ``minutesUntilNextDispatch(memo:)``.
    private func minutesUntilLineWaitsChange(memo: inout DispatchMemo) -> Int64? {
        guard isTrafficControlEnabled else { return nil }
        let now = clock.now
        var soonest: Int64?
        for line in lines {
            for stream in line.dispatchStreams where !line.trains(of: stream).isEmpty {
                let waits = line.trains(of: stream).contains { id in
                    guard let train = train(id: id) else { return false }
                    return readyTrip(of: train, on: line, stream.service, memo: &memo) != nil
                }
                guard waits, readyTrain(of: line, stream, memo: &memo) == nil else { continue }
                var wake: GameTime?
                if now.seconds < 0 {
                    wake = .zero
                } else {
                    wake = line.nextChange(after: now, in: serviceDay)
                    if !isDispatchDue(line, stream, at: now, memo: &memo), let last = line.lastDispatch(of: stream),
                       let planned = plannedService(of: line, stream.service, at: now, memo: &memo),
                       let due = Self.time(last, plusMinutes: planned.headway), due > now {
                        wake = min(wake ?? due, due)
                    }
                }
                guard let wake else { continue }
                soonest = min(soonest ?? .max, Self.minutes(from: now, until: wake))
            }
        }
        return soonest
    }

    /// The services' phase of a basic step (Stage W2b): every train whose
    /// service waits at a stop, in ascending ID order, moves its dwell on
    /// (see ``stepDwell(_:at:)``) and then leaves if its departure is due
    /// (see ``departService(_:at:unroutable:held:)``); every train whose service
    /// travels and was held up on its run sets off again if it can (Stage
    /// W2c, see ``resumeRun(_:at:)``). Returns whether any service changed.
    private mutating func runServices(at now: GameTime, unroutable: inout Set<TrainID>, held: inout [HeldRoute], memo: inout DispatchMemo) -> Bool {
        var changed = false
        for index in trains.indices where trains[index].execution != nil {
            if stepDwell(index, at: now) {
                changed = true
            }
            if departService(index, at: now, unroutable: &unroutable, held: &held, memo: &memo) {
                changed = true
            }
            if resumeRun(index, at: now) {
                changed = true
            }
            if goOn(index, held: &held, memo: &memo) {
                changed = true
            }
        }
        return changed
    }

    /// Stage V2 (ARCHITECTURE decision 58): train `index`'s service,
    /// stopped at a passing place on its way (see ``isAtPassingPlace(_:)``),
    /// sets off again for its call once it can take the route there as a
    /// departure does (see ``reservingDeparture(_:)``): whole, following
    /// the trains ahead, or to another berth of the call's station. It is
    /// off its timetable, so it runs as fast as it can. Otherwise it waits
    /// there, and the route it waits for joins `held`. Without traffic
    /// control it always can. Returns whether the service changed.
    ///
    /// Stage V3 (decision 59): a train held by a scheduled wait stays; one
    /// whose scheduled way on (see ``scheduledPath(for:from:to:plan:)``)
    /// it can take whole now takes it, on the scheduled run. Otherwise it
    /// goes on exactly as above.
    private mutating func goOn(_ index: Int, held: inout [HeldRoute], memo: inout DispatchMemo) -> Bool {
        let plan = trafficPlan(memo: &memo.directions)
        guard currentTrafficWait(trains[index], plan: plan, memo: &memo.directions) == nil,
              let going = goingOn(trains[index]) else { return false }
        if let chosen = scheduledPath(for: trains[index], from: trains[index].position!, to: trains[index].timetable[trains[index].execution!.stop].station, plan: plan) {
            var scheduled = going
            follow(chosen.path, &scheduled)
            let plannedRun = run(of: scheduled, length: chosen.path.distance, scheduled: chosen.seconds)
            scheduled.times?.run = plannedRun
            if case .granted(let granted) = reserving(scheduled) {
                setOff(index, as: granted)
                return true
            }
        }
        if let preferred = preferredGoingOn(trains[index]), case .granted(let granted) = reserving(preferred) {
            setOff(index, as: granted)
            return true
        }
        switch reservingDeparture(going, memo: &memo.directions) {
        case .granted(var granted):
            let fastest = run(of: granted, length: routeLength(of: granted))
            granted.times?.run = fastest
            setOff(index, as: granted)
            return true
        case .held:
            held.append(HeldRoute(candidate: going))
            return false
        }
    }

    /// Train `index` set off as `train`, its traffic visits (decision 59)
    /// kept, with its departure from where it stands.
    private mutating func setOff(_ index: Int, as train: Train) {
        recordTrafficDeparture(index)
        var departed = train
        departed.trafficVisits = trains[index].trafficVisits
        trains[index] = departed
    }

    /// Stage V2 (ARCHITECTURE decision 58): the dispatcher's phase, at a
    /// whole minute after the services' phase. Of the trains in a deadlock
    /// (see ``deadlock(memo:)``), the first in ID order whose service is due to
    /// leave a stop, or is stopped at a passing place, and that has a
    /// passing place letting another of them go (see
    /// ``passingPlace(for:in:memo:)``) sets off for it, taking the way there
    /// whole, as fast as it can: one train at most each minute. Leaving a
    /// stop so is a departure like any other (G1b, G1c), counted over the
    /// whole way to its call. Returns the train's ID, or `nil`.
    private mutating func resolveDeadlock(memo: inout DispatchMemo) -> TrainID? {
        // Only such a service is ever sent: without one, nothing to find.
        guard isTrafficControlEnabled, trains.contains(where: { train in
            if case .waitingAtStop? = train.execution, let due = departureDue(of: train), due <= clock.now { return true }
            return isAtPassingPlace(train)
        }) else { return nil }
        let stuck = deadlock(memo: &memo.directions)
        for id in stuck.keys.sorted() {
            guard let request = stuck[id], request.departs, let index = trains.firstIndex(where: { $0.id == id }),
                  trains[index].execution != nil,
                  let passing = passingPlace(for: request.candidate, in: stuck, memo: &memo.directions)
            else { continue }
            var aside = request.candidate
            if passing.reverses, let place = aside.placement {
                let reverse = turnedRound(place)
                aside.position = reverse.position
                aside.trailEdges = reverse.trailEdges
            }
            follow(passing.path, &aside)
            let fastest = run(of: aside, length: passing.path.distance)
            aside.times?.run = fastest
            guard case .granted(let granted) = reserving(aside) else { continue }
            let left: Int? = if case .waitingAtStop(let stop, _)? = trains[index].execution { stop } else { nil }
            setOff(index, as: granted)
            if let left {
                serve(departureOf: id, from: left, distance: passing.distance)
            }
            return id
        }
        return nil
    }

    /// This world with `train` in place of the train of its ID: for asking
    /// what would follow from it (Stage V2), never committed.
    func replacing(_ train: Train) -> GameWorld {
        var world = self
        if let index = world.trains.firstIndex(where: { $0.id == train.id }) {
            world.trains[index] = train
        }
        return world
    }

    /// Moves on the dwell of train `index`, if its service waits at a stop
    /// (see ``ServiceTimes``), and returns whether it changed:
    ///
    /// - once its doors have opened, the passengers for that stop get off
    ///   and those waiting for the train get on (see
    ///   ``exchangePassengers(_:at:)``), taking as long as the larger
    ///   number does (see ``Train/exchangeSeconds(_:)``);
    /// - while its doors stay open, at each whole minute, when new
    ///   passengers have come, they get on too, after those still getting
    ///   on;
    /// - its doors start closing once the exchange is over, its least dwell
    ///   will be over when they have closed, and (when it is early) they
    ///   close for its scheduled departure: at the latest of
    ///   ``closingStart(of:stop:cycle:)``.
    private mutating func stepDwell(_ index: Int, at now: GameTime) -> Bool {
        guard case .waitingAtStop(let stop, let cycle)? = trains[index].execution, var times = trains[index].times else { return false }
        var changed = false
        if let end = times.exchangeEnd {
            if times.closing == nil, now.isWholeMinute {
                let boarded = boardPassengers(trains[index], at: stop)
                if boarded > 0 {
                    times.exchangeEnd = Self.saturating(max(end, now), plus: trains[index].exchangeSeconds(boarded))
                    changed = true
                }
            }
        } else {
            guard now >= Self.saturating(times.arrival, plus: ServiceDwell.doorOpening) else { return false }
            let busy = exchangePassengers(index, at: stop)
            times.exchangeEnd = Self.saturating(now, plus: trains[index].exchangeSeconds(busy))
            changed = true
        }
        if times.closing == nil, let start = closingStart(of: trains[index], stop: stop, cycle: cycle, times: times), now >= start {
            times.closing = now
            changed = true
        }
        trains[index].times = times
        return changed
    }

    /// Train `index`'s service, travelling to a stop, after it was held up
    /// on its run (Stage W2c; see ``dropRunsHeldUp(endingAt:)``): a train
    /// without a run sets off on a new one (see
    /// ``run(of:length:scheduled:)``), in the least whole second its
    /// performance builds a curve for, over the way left to the end of its
    /// route, when all of these hold:
    ///
    /// - its rate is above 0 (a rate of 0 holds it);
    /// - it has way left (see ``routeStretches(of:)``); and
    /// - it can move now: the track lets it go on at least one unit.
    ///
    /// It was stopped, so it starts again from a stand, as fast as it can
    /// (the references only sample timetables and have no rule for this).
    /// A run that is over before the train arrived (which only a train held
    /// up has, and it drops it at once) is dropped first. Returns whether
    /// the service changed.
    private mutating func resumeRun(_ index: Int, at now: GameTime) -> Bool {
        guard case .travellingToStop? = trains[index].execution, var times = trains[index].times else { return false }
        var changed = false
        if let run = times.run {
            guard run.end <= now else { return false }
            times.run = nil
            changed = true
        }
        let train = trains[index]
        let route = routeStretches(of: train)
        if train.movement.rate > 0, route.moves {
            let step = travelling(train, distance: 1)
            if step.position != train.position || step.cursor != train.movement.cursor {
                var left: Int64 = 0
                for stretch in route.stretches {
                    let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                    left = overflow ? .max : sum
                }
                if let run = run(of: train, length: left) {
                    times.run = run
                    changed = true
                }
            }
        }
        trains[index].times = times
        return changed
    }

    /// When the doors of `train`, waiting at timetable entry `stop` of
    /// `cycle` with `times`, start closing (Stage W2b): the latest of the
    /// end of its exchange, its least dwell (see
    /// ``ServiceDwell/minimumDwell(isTerminal:)``) less the time the doors
    /// take to close, and its scheduled departure less that time. `nil`
    /// while the doors are still opening. A ring's train (decision 49) has
    /// no terminal: it dwells at the first stop of its lap as at any other,
    /// unless it turns round there (the reference's ring dwell).
    func closingStart(of train: Train, stop: Int, cycle: Int64, times: ServiceTimes) -> GameTime? {
        guard let exchangeEnd = times.exchangeEnd else { return nil }
        let entry = train.timetable[stop]
        let onRing = lines.contains { $0.isRing && $0.trains.contains(train.id) }
        let isTerminal = entry.reverses || (!onRing && (stop == 0 || stop == train.timetable.count - 1))
        let leastDwell = Self.saturating(times.arrival, plus: ServiceDwell.minimumDwell(isTerminal: isTerminal) - ServiceDwell.doorClosing)
        // Scheduled times are never negative, so this cannot overflow.
        let scheduled = GameTime(seconds: train.scheduledDeparture(of: stop, cycle: cycle).seconds - ServiceDwell.doorClosing)
        return max(exchangeEnd, leastDwell, scheduled)
    }

    /// When the service of `train`, waiting at a stop with its doors
    /// closing, may leave: once they have closed. `nil` while it is not
    /// waiting, or its doors are open.
    func departureDue(of train: Train) -> GameTime? {
        guard case .waitingAtStop? = train.execution, let closing = train.times?.closing else { return nil }
        return Self.saturating(closing, plus: ServiceDwell.doorClosing)
    }

    /// `time` plus `seconds`, or the largest time when that does not fit.
    static func saturating(_ time: GameTime, plus seconds: Int64) -> GameTime {
        let (sum, overflow) = time.seconds.addingReportingOverflow(seconds)
        return GameTime(seconds: overflow ? (seconds < 0 ? .min : .max) : sum)
    }

    /// Train `index`'s service leaves the stop it waits at if its departure
    /// is due (see ``departureDue(of:)``); see ``leaving(_:stop:cycle:)``.
    /// Returns whether the service changed.
    ///
    /// Under traffic control the departure tries the default route whole,
    /// an unblocked route to the same station whole (V1), then following
    /// on the default route (U2). If none can be taken, nothing changes:
    /// the train is not turned round
    /// either, and it tries again at the next step; the route it waits for
    /// joins `held`. Unlike a departure without a route, this is not
    /// remembered for the rest of the call: trains move and free track
    /// within one.
    @discardableResult
    private mutating func departService(_ index: Int, at now: GameTime, unroutable: inout Set<TrainID>, held: inout [HeldRoute], memo: inout DispatchMemo) -> Bool {
        guard case .waitingAtStop(let stop, let cycle)? = trains[index].execution,
              let due = departureDue(of: trains[index]), due <= now,
              !unroutable.contains(trains[index].id),
              trains[index].placement != nil
        else { return false }
        // Stage V3 (decision 59): a scheduled wait keeps it here.
        let plan = trafficPlan(memo: &memo.directions)
        guard currentTrafficWait(trains[index], plan: plan, memo: &memo.directions) == nil else { return false }
        let departure = leaving(trains[index], stop: stop, cycle: cycle)
        guard let moved = departure.train else {
            // Nothing changes: the train is not turned round either.
            unroutable.insert(trains[index].id)
            return false
        }
        let train: Train
        // Stage V3: the scheduled path, on the scheduled run, when the train
        // can take it whole now; otherwise the departure as without a plan.
        if case .setsOff = departure,
           case .setsOff(let scheduled, _)? = scheduledLeaving(trains[index], stop: stop, cycle: cycle, plan: plan),
           case .granted(let granted) = reserving(scheduled) {
            train = granted
        } else if case .setsOff(let preferred, _)? = preferredLeaving(trains[index], stop: stop, cycle: cycle),
                  case .granted(let granted) = reserving(preferred) {
            train = granted
        } else {
            switch reservingDeparture(moved, memo: &memo.directions) {
            case .granted(let granted):
                train = granted
            case .held:
                held.append(HeldRoute(candidate: moved))
                return false
            }
        }
        setOff(index, as: train)
        serve(departureOf: train.id, from: stop, distance: departure.distance.map { $0 == 0 ? 0 : routeLength(of: train) })
        return true
    }

    /// What leaving stop `stop` (of cycle `cycle`) does to `train`, whose
    /// service waits there: one pass of phase 1, worked out without
    /// changing the world.
    enum Leaving {
        /// The service is complete: the train stands where it is.
        case completes(Train)
        /// It is already stopped at the next call's station, and waits
        /// there at once.
        case arrives(Train)
        /// It sets off along the path to the next call, `distance` world
        /// units long.
        case setsOff(Train, distance: Int64)
        /// There is no path to the next call: nothing changes.
        case noRoute

        /// The train as the departure leaves it; `nil` without a route.
        var train: Train? {
            switch self {
            case .completes(let train), .arrives(let train), .setsOff(let train, _): train
            case .noRoute: nil
            }
        }

        /// How far the departure takes the train to its next call (G1c):
        /// `nil` when the service ends instead.
        var distance: Int64? {
            switch self {
            case .arrives: 0
            case .setsOff(_, let distance): distance
            case .completes, .noRoute: nil
            }
        }
    }

    /// See ``Leaving``. A waiting train is stopped with its path spent, so
    /// turning it round (at a stop marked to) needs nothing else; a train
    /// of several cars turns round with its head where its tail was (see
    /// ``turnedRound(_:)``). A train turned round stands there: its path
    /// ends where its head is.
    /// Without a path, the train is not turned round either.
    func leaving(_ train: Train, stop: Int, cycle: Int64) -> Leaving {
        leaving(train, stop: stop, cycle: cycle) { start, call in
            path(from: start, toStation: call, length: train.length).map { ($0, nil) }
        } ?? .noRoute
    }

    /// Decision 61: a physical preference is taken only as a whole.
    func preferredLeaving(_ train: Train, stop: Int, cycle: Int64) -> Leaving? {
        guard let next = train.call(after: stop, cycle: cycle),
              let preference = routePreference(for: train, from: stop, to: next.stop) else { return nil }
        return leaving(train, stop: stop, cycle: cycle) { start, _ in
            preferredPath(from: start, preference: preference, length: train.length).map { ($0, nil) }
        }
    }

    /// Stage V3 (decision 59): `train` leaving stop `stop` along its
    /// scheduled path, on the scheduled run (see
    /// ``scheduledPath(for:from:to:plan:)``); `nil` when the plan gives it
    /// none.
    func scheduledLeaving(_ train: Train, stop: Int, cycle: Int64, plan: TrafficPlan) -> Leaving? {
        leaving(train, stop: stop, cycle: cycle) { start, call in
            scheduledPath(for: train, from: start, to: call, plan: plan)
        }
    }

    /// See ``leaving(_:stop:cycle:)``, along the path (and in the seconds,
    /// if any) `route` gives from where the train would stand to the next
    /// call's station; `nil` when it gives none.
    private func leaving(_ train: Train, stop: Int, cycle: Int64, route: (TrainPosition, StationID) -> (path: TrainPath, seconds: Int64?)?) -> Leaving? {
        guard let placement = train.placement else { return .noRoute }
        let start = train.timetable[stop].reverses ? turnedRound(placement) : placement
        var moved = train
        guard let next = train.call(after: stop, cycle: cycle) else {
            // The last stop's departure: the service is complete.
            stand(&moved, at: start)
            moved.execution = nil
            moved.times = nil
            return .completes(moved)
        }
        guard let chosen = route(start.position, train.timetable[next.stop].station) else { return nil }
        let path = chosen.path
        stand(&moved, at: start)
        let now = clock.now
        if path.distance == 0 {
            // Already stopped at the next call's station: it arrives there
            // now, and dwells there as at any call (Stage W2b).
            moved.execution = .waitingAtStop(next.stop, cycle: next.cycle)
            moved.times = ServiceTimes(arrival: now, departure: now)
            return .arrives(moved)
        }
        follow(path, &moved)
        moved.execution = .travellingToStop(next.stop, cycle: next.cycle)
        // Stage W2c: the run takes the time the timetable gives it, from the
        // scheduled departure to the scheduled arrival (never negative).
        let scheduled = train.scheduledArrival(of: next.stop, cycle: next.cycle).seconds
            - train.scheduledDeparture(of: stop, cycle: cycle).seconds
        moved.times = ServiceTimes(
            arrival: train.times?.arrival ?? now, departure: now,
            run: run(of: moved, length: path.distance, scheduled: chosen.seconds ?? scheduled)
        )
        return .setsOff(moved, distance: path.distance)
    }

    /// The run `train`, a service's, sets off on now over `length` world
    /// units to its next call (Stage W2c; see ``ServiceRun``): in the
    /// `scheduled` seconds its timetable gives the run when its performance
    /// builds a curve for them, as the Railway reference fits a run's curve
    /// to the timetable; otherwise (it cannot keep that time, or there is
    /// none) in the least whole second it builds one for, running as fast
    /// as it can. `nil` when it builds none at all (see
    /// ``RunningCurve/leastSeconds(length:performance:)``): the train then
    /// goes at its rate.
    ///
    /// - Precondition: `length >= 1`.
    func run(of train: Train, length: Int64, scheduled: Int64? = nil) -> ServiceRun? {
        if let scheduled, (1...RunningCurve.maximumSeconds).contains(scheduled),
           RunningCurve(length: length, duration: scheduled * 1000, performance: train.performance) != nil {
            return ServiceRun(start: clock.now, length: length, seconds: scheduled)
        }
        return RunningCurve.leastSeconds(length: length, performance: train.performance)
            .map { ServiceRun(start: clock.now, length: length, seconds: $0) }
    }

    // The service adapters that change a train (Stage S5; the others are in
    // ServicePath.swift).

    /// Gives `train` `path` as its path, from the start: its edges and
    /// where it stops. The rest of its movement stays.
    func follow(_ path: TrainPath, _ train: inout Train) {
        train.movement.edges = path.traversals.map(\.edge)
        train.movement.end = path.end
        train.movement.cursor = 0
    }

    /// Puts `train` where `placement` says and leaves it standing there: its
    /// path now ends where its head is (see ``TrainMovement/end``), so it
    /// stays until it is given a path.
    private func stand(_ train: inout Train, at placement: TrainPlacement) {
        train.position = placement.position
        train.trailEdges = placement.trailEdges
        switch placement.position {
        case .onEdge(let traversal, let offset):
            train.movement.edges = []
            train.movement.cursor = 0
            train.movement.end = offset < network.edge(traversal.edge)!.length ? offset : nil
        }
    }

    /// Phase 4 of a basic step: every travelling service whose train is now
    /// stopped at the station of the stop it travels to waits at that stop.
    /// Returns whether any service arrived.
    private mutating func recordArrivals() -> Bool {
        var arrived = false
        for index in trains.indices {
            guard case .travellingToStop(let stop, let cycle)? = trains[index].execution,
                  isStopped(trains[index], at: trains[index].timetable[stop].station)
            else { continue }
            trains[index].execution = .waitingAtStop(stop, cycle: cycle)
            trains[index].times = ServiceTimes(arrival: clock.now, departure: trains[index].times?.departure)
            arrived = true
        }
        return arrived
    }

    /// The first second after `now` at which some service's dwell moves on
    /// by itself (Stage W2b), or `nil` if none does: a train's doors finish
    /// opening, its doors start closing, or its departure comes; or (Stage
    /// W2c) a travelling train's run comes to its end, after which a train
    /// held up on the way sets off again (see ``resumeRun(_:at:)``). A
    /// departure that has come and could not be made (no route, or its
    /// route held) is not an event: it is tried again at every step, and
    /// can only succeed once something else has changed; nor is a held-up
    /// train that cannot move yet. Boarding at whole minutes needs no
    /// event: every whole minute ends a step anyway.
    func nextServiceEvent(after now: GameTime) -> GameTime? {
        var soonest: GameTime?
        for train in trains {
            guard let execution = train.execution, let times = train.times else { continue }
            let event: GameTime?
            if case .waitingAtStop(let stop, let cycle) = execution {
                if times.exchangeEnd == nil {
                    event = Self.saturating(times.arrival, plus: ServiceDwell.doorOpening)
                } else if times.closing == nil {
                    event = closingStart(of: train, stop: stop, cycle: cycle, times: times)
                } else {
                    event = departureDue(of: train)
                }
            } else {
                event = times.run?.end
            }
            if let event, event > now, event < soonest ?? .init(seconds: .max) {
                soonest = event
            }
        }
        return soonest
    }

    /// The whole minutes from now, the start of a minute, that an idle step
    /// may skip before the next service event at or after now (see
    /// ``nextServiceEvent(after:)``) or the next second in which a run takes
    /// a train on (see ``nextRunMove(from:)``), or `nil` if there is
    /// neither. The step just taken ended at now, so an event at now has not
    /// been seen yet. None at all while `passengersWaiting` and a train
    /// waits with its doors open: passengers who come at a whole minute get
    /// on.
    private func wholeMinutesUntilNextServiceEvent(passengersWaiting: Bool) -> Int64? {
        let now = clock.now
        if passengersWaiting, trains.contains(where: { train in
            if case .waitingAtStop? = train.execution, train.times?.closing == nil { return true }
            return false
        }) {
            return 0
        }
        guard let event = [nextServiceEvent(after: Self.saturating(now, plus: -1)), nextRunMove(from: now)].compactMap({ $0 }).min() else {
            return nil
        }
        let (gap, overflow) = event.seconds.subtractingReportingOverflow(now.seconds)
        return overflow ? .max : gap / GameTime.secondsPerMinute
    }

    /// The first second, at or after `now`, in which the run of some
    /// travelling service's train takes it farther along its curve than it
    /// had come by `now`, or `nil` if none has a run (Stage W2c): the second
    /// that ends when it has. A slow run can leave its train where it is for
    /// whole minutes, and then take it on: that is a change an idle minute
    /// does not foresee (or, when the train cannot go on, its run is dropped
    /// then; see ``dropRunsHeldUp(endingAt:)``). Never after the run's last
    /// second. Only the shortcut over idle minutes needs it: a step that
    /// moves a train is not idle.
    private func nextRunMove(from now: GameTime) -> GameTime? {
        var soonest: GameTime?
        for train in trains {
            guard case .travellingToStop? = train.execution, let run = train.times?.run, run.end > now,
                  let curve = run.curve(for: train.performance)
            else { continue }
            let covered = run.distance(on: curve, from: run.start, to: now)
            // The least second in (now, end] by which the curve has come
            // farther: at the end it has come all the way.
            var (low, high) = (Self.saturating(now, plus: 1).seconds, run.end.seconds)
            while low < high {
                let middle = low + (high - low) / 2
                if run.distance(on: curve, from: run.start, to: GameTime(seconds: middle)) > covered {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            // The second that ends at `low`; `low > now`, so it is not
            // before now.
            if low - 1 < soonest?.seconds ?? .max {
                soonest = GameTime(seconds: low - 1)
            }
        }
        return soonest
    }

    /// The seconds, from `start` and at most `span`, in which the first
    /// placed train with a rate comes to the end of the way it can go (see
    /// ``routeStretches(of:)``), or `nil` if none does within `span` (Stage
    /// W2b): its service arrives then, or its route is released, so the
    /// step ends there.
    ///
    /// - Precondition: `start.secondOfMinute + span <= 60`.
    private func secondsUntilARouteEnds(from start: GameTime, within span: Int64) -> Int64? {
        var soonest: Int64?
        for train in trains where train.movement.rate > 0 && train.position != nil {
            let route = routeStretches(of: train)
            guard route.moves else { continue }
            var left: Int64 = 0
            for stretch in route.stretches {
                let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                left = overflow ? .max : sum
            }
            let limit = soonest.map { $0 - 1 } ?? span
            let share = travelShare(of: train, from: start)
            guard limit >= 1, share(limit) >= left else { continue }
            // Where the travel ends decides: a train held up on the way never
            // comes to its end, however far it may go.
            let end = travelling(train, distance: left)
            var arrived = train
            arrived.position = end.position
            arrived.movement.cursor = end.cursor
            guard !routeStretches(of: arrived).moves else { continue }
            // The least `k` whose distance covers what is left.
            var (low, high) = (Int64(1), limit)
            while low < high {
                let middle = (low + high) / 2
                if share(middle) >= left {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            soonest = low
        }
        return soonest
    }

    /// The travel of `span` basic steps from `start`, for every placed train
    /// with a rate, in ascending ID order: each train's share for those
    /// seconds (see ``travelShare(of:from:)``), in one move. The moves of
    /// the seconds one at a time add up to it, since a move depends on the
    /// map alone. Returns whether any train changed.
    private mutating func moveTrains(from start: GameTime, for span: Int64) -> Bool {
        var moved = false
        for index in trains.indices {
            let movement = trains[index].movement
            guard let position = trains[index].position, movement.rate > 0 else { continue }
            let distance = travelShare(of: trains[index], from: start)(span)
            guard distance > 0 else { continue }
            let travel = travelling(trains[index], distance: distance)
            guard travel.position != position || travel.cursor != movement.cursor else { continue }
            switch (position, travel.position) {
            case (.onEdge(let traversal, _), .onEdge(_, let reached)):
                trains[index].trailEdges = networkTrail(
                    after: traversal.edge, trail: trains[index].trailEdges,
                    entered: movement.edges[movement.cursor..<travel.cursor], offset: reached, length: trains[index].length
                )
            }
            trains[index].position = travel.position
            if travel.cursor == movement.edges.count {
                // Every edge has been entered: the path is spent. Where the
                // path ends (Stage S5) is now on the train's own edge, and
                // stays.
                trains[index].movement.edges = []
                trains[index].movement.cursor = 0
            } else {
                trains[index].movement.cursor = travel.cursor
            }
            releasePassedTrack(index)
            moved = true
        }
        return moved
    }

    /// Stage W2c: every travelling service's train that could not follow its
    /// run (see ``ServiceRun``) up to `end`, the end of a step, drops it:
    /// held by a rate of 0, or by track ahead that was removed, it has
    /// more way left than its curve has left to go. Its curve no longer says
    /// where it is; it sets off again from a stand once it can (see
    /// ``resumeRun(_:at:)``). Within a step the map and the rates cannot
    /// change, so a train held up at one second of it is held up at its
    /// end. Returns whether any run was dropped.
    private mutating func dropRunsHeldUp(endingAt end: GameTime) -> Bool {
        var dropped = false
        for index in trains.indices {
            guard case .travellingToStop? = trains[index].execution, let run = trains[index].times?.run,
                  let curve = run.curve(for: trains[index].performance)
            else { continue }
            var left: Int64 = 0
            for stretch in routeStretches(of: trains[index]).stretches {
                let (sum, overflow) = left.addingReportingOverflow(stretch.to - stretch.from)
                left = overflow ? .max : sum
            }
            guard left > run.length - run.distance(on: curve, from: run.start, to: end) else { continue }
            trains[index].times?.run = nil
            dropped = true
        }
        return dropped
    }

    /// How far placed train `train`, with a rate, may travel in the first
    /// `k` seconds from `start`, for `k` from 0 to the end of `start`'s
    /// minute: along its service's run (Stage W2c, see ``ServiceRun``) how
    /// much farther its curve has come by then, and otherwise its share of
    /// its rate (see ``TrainMovement/distance(at:fromSecond:toSecond:)``).
    /// Never less for a larger `k`. The curve is built once, for all of
    /// them.
    func travelShare(of train: Train, from start: GameTime) -> (Int64) -> Int64 {
        if case .travellingToStop? = train.execution, let run = train.times?.run {
            guard let curve = run.curve(for: train.performance) else { return { _ in 0 } }
            return { k in run.distance(on: curve, from: start, to: Self.saturating(start, plus: k)) }
        }
        let rate = train.movement.rate
        let second = start.secondOfMinute
        return { k in TrainMovement.distance(at: rate, fromSecond: second, toSecond: second + k) }
    }

    /// Where placed train `train` ends up after travelling up to `distance`
    /// units, and its cursor: each edge as long as it is (Stage S3), up to
    /// where its path ends, and under traffic control no farther than its
    /// movement authority (Stage U2, see ``authorityLeft(of:)``). It depends
    /// on the network and the train's reservation alone.
    func travelling(_ train: Train, distance: Int64) -> (position: TrainPosition, cursor: Int) {
        let distance = authorityLeft(of: train).map { min(distance, $0) } ?? distance
        let movement = train.movement
        switch train.position! {
        case .onEdge(let traversal, let offset):
            return TrainMovement.travel(
                along: traversal, offset: offset, length: network.edge(traversal.edge)!.length,
                distance: distance, edges: movement.edges, cursor: movement.cursor, end: movement.end,
                enter: { networkEntry(after: $0, into: $1) }
            )
        }
    }

    /// Stage U (ARCHITECTURE decision 55): once train `index` has moved,
    /// its reservation keeps only the track it still needs (see
    /// ``routeEnvelope(of:)``): what it stands on, what its head has still
    /// to pass over and the junctions all that fouls. Track its tail has
    /// left behind is released at once, and once it has come to the end of
    /// its route (it stands, with no distance left to go) all of it is
    /// (Stage T). What it stands on stays held as long as it stands there.
    /// A train only ever goes on along its route, so what it needs only
    /// ever shrinks: nothing is taken here, and nothing the train will
    /// still use is released.
    private mutating func releasePassedTrack(_ index: Int) {
        guard !trains[index].reservation.isEmpty else { return }
        let envelope = routeEnvelope(of: trains[index])
        trains[index].reservation = envelope.moves ? trains[index].reservation.filter(envelope.resources.contains) : []
    }

    /// Stage U2: every train that follows another, in ascending ID order,
    /// takes more of its route if it can: all of it once no other train
    /// holds any of it (it no longer follows), or else as far as
    /// ``followingGap`` short of the first track another holds, if that is
    /// farther than it holds now. Comes first in each step, before any
    /// train sets off: trains already on the way go on first. Returns
    /// whether any reservation changed.
    mutating func extendAuthorities() -> Bool {
        var extended = false
        for index in trains.indices {
            guard let held = authorityLeft(of: trains[index]) else { continue }
            let envelope = routeEnvelope(of: trains[index])
            if holder(of: envelope.resources, except: trains[index].id) == nil {
                trains[index].reservation = envelope.resources.sorted()
                extended = true
                continue
            }
            let blocked = blockedTrack(except: trains[index].id)
            let envelopes = authorityEnvelopes(of: trains[index])
            var (low, high) = (held, envelopes.length)
            while low < high {
                let middle = low + (high - low + 1) / 2
                if !network.fouls(authorityEnvelope(envelopes, to: middle), blocked) {
                    low = middle
                } else {
                    high = middle - 1
                }
            }
            let authority = low - Self.followingGap
            guard authority > held else { continue }
            trains[index].reservation = Set(trains[index].reservation).union(authorityEnvelope(envelopes, to: authority)).sorted()
            extended = true
        }
        return extended
    }

    /// Whether ``extendAuthorities()`` would give any train more of its
    /// route now: some following train's track as far as just beyond
    /// ``followingGap`` past its authority is free. One train taking more
    /// only ever leaves the others less, so the first that could is the
    /// first that does.
    private func canExtendAnyAuthority() -> Bool {
        trains.contains { train in
            guard let held = authorityLeft(of: train) else { return false }
            let (reach, overflow) = held.addingReportingOverflow(Self.followingGap + 1)
            return !network.fouls(authorityEnvelope(of: train, to: overflow ? .max : reach), blockedTrack(except: train.id))
        }
    }

    /// A departure due at the start of a step whose route another train
    /// holds (Stage T): the train as it would set off.
    struct HeldRoute {
        let candidate: Train
    }

    /// The seconds, from `start` and at most `span`, after which one of
    /// `held` could set off (wholly, or following the trains ahead, Stage
    /// U2), or a train following others could take more of its route, or
    /// `nil` if that does not happen within `span` (Stage U): trains moving
    /// on release the track behind them (see ``releasePassedTrack(_:)``),
    /// so the step ends there and the departure or the following train
    /// tries again at the next, as it would one second at a time. Every
    /// train only moves on in the step, and what it holds only shrinks as it
    /// does, so once free the track stays free.
    ///
    /// - Precondition: `start.secondOfMinute + span <= 60`.
    private func secondsUntilARouteFrees(_ held: [HeldRoute], from start: GameTime, within span: Int64, memo: inout DispatchMemo) -> Int64? {
        func frees(after seconds: Int64) -> Bool {
            var moved = self
            _ = moved.moveTrains(from: start, for: seconds)
            if held.contains(where: { if case .granted = moved.reservingDeparture($0.candidate, memo: &memo.directions) { true } else { false } }) {
                return true
            }
            return moved.canExtendAnyAuthority()
        }
        // The least `k` after which one is free. A train following another
        // moving on takes more of its route almost every second, so then
        // the first second is tried first.
        if trains.contains(where: isFollowing), frees(after: 1) { return 1 }
        guard frees(after: span) else { return nil }
        var (low, high) = (Int64(1), span)
        while low < high {
            let middle = (low + high) / 2
            if frees(after: middle) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }

    // MARK: - Validation


    private static func isValidName(_ name: String) -> Bool {
        name.contains { !$0.isWhitespace }
    }

    /// The index of line `id` and the service `pattern` names on it (see
    /// ``ServiceLine/serviceCount``).
    private func lineService(_ id: LineID, pattern: Int?) throws(GameError) -> (index: Int, service: Int) {
        let index = try lineIndex(of: id)
        guard let service = lines[index].service(pattern) else { throw .unknownLinePattern(pattern ?? 0) }
        return (index, service)
    }

    private func lineIndex(of id: LineID) throws(GameError) -> Int {
        guard let index = lines.firstIndex(where: { $0.id == id }) else { throw .unknownLine(id) }
        return index
    }

    private func requireLineStops(_ stops: [StationID], ring: Bool = false) throws(GameError) {
        guard ring ? ServiceLine.isRingStopList(stops) : ServiceLine.isStopList(stops) else { throw .invalidLineStops }
        if let missing = stops.first(where: { station(id: $0) == nil }) {
            throw .unknownStation(missing)
        }
    }

    private func trainIndex(of id: TrainID) throws(GameError) -> Int {
        guard let index = trains.firstIndex(where: { $0.id == id }) else { throw .unknownTrain(id) }
        return index
    }

    private func placedTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let index = try trainIndex(of: id)
        guard let position = trains[index].position else { throw .trainNotPlaced(id) }
        return (index, position)
    }

    /// A placed train that no service is running: the commands that change
    /// its path or take it off the track need one.
    private func manuallyControlledTrain(_ id: TrainID) throws(GameError) -> (index: Int, position: TrainPosition) {
        let (index, position) = try placedTrain(id)
        guard trains[index].execution == nil else { throw .trainServiceActive(id) }
        return (index, position)
    }

    /// Whether `position` is well formed and lies on this world's track: the
    /// edge exists and the offset lies within it (see
    /// ``isOnNetwork(_:offset:)``).
    func isOnTrack(_ position: TrainPosition) -> Bool {
        guard position.isWellFormed else { return false }
        switch position {
        case .onEdge(let traversal, let offset):
            return isOnNetwork(traversal, offset: offset)
        }
    }
}

// MARK: - ID allocation

extension GameWorld {
    /// The ID a counter hands out, and the counter's value afterwards.
    ///
    /// A counter holds the next ID to hand out, and every ID is below it, so
    /// handing out `next` needs `next + 1` to fit in an `Int`: the last ID is
    /// `Int.max - 1`, leaving the counter at `Int.max`, where it stays. Only
    /// reads the counter, so a command can check before changing anything.
    ///
    /// - Throws: ``GameError/idsExhausted`` once the counter is at `Int.max`.
    static func allocateID(from next: Int) throws(GameError) -> (id: Int, next: Int) {
        let (following, overflow) = next.addingReportingOverflow(1)
        guard !overflow else { throw .idsExhausted }
        return (next, following)
    }
}

// MARK: - Codable

extension GameWorld: Codable {
    private enum CodingKeys: String, CodingKey {
        case bounds, map, stations, trains, lines, serviceDay, clock, economy, nextStationID, nextTrainID, nextLineID, network, trafficControl
        case passengers, riders, passengerRoutingMode, passengerRouteBalances, weeklyDemand, demandEvents, townGrowth, accounts, geoAnchor
    }

    /// Decodes a world, rejecting data that breaks cross-object invariants
    /// (IDs must be unique and below the next ID to allocate; every station
    /// must stand in the world's bounds; every placed train must be on this world's
    /// track, as ``placeTrain(_:at:)`` requires; every timetable stop must
    /// name one of this world's stations, as
    /// ``setTrainTimetable(_:to:repeatingEvery:)`` requires; a waiting
    /// service's train must be stopped at its stop's station, and a
    /// travelling service's journey must end beside the station of the stop
    /// it travels to, as a route from the service would; every line's
    /// and patterns' trains must exist and be on that service only, none of
    /// them may run a repeating timetable, and no service may have sent a
    /// train out after the current minute, as ``assignTrain(_:to:pattern:)`` and dispatching require).
    ///
    /// The edges of a path are not required to exist: track ahead of a train
    /// may have been removed after the path was set, and a world where a
    /// train waits at the end of its edge for a new path is valid.
    ///
    /// The grid went in Stage F3c (ARCHITECTURE decision 51). A save that
    /// holds any of it, which only a save made by hand could (the app has
    /// saved only the track network since saves began, Stage C4), is refused
    /// with that reason: grid track or a station on a tile in the map, a
    /// station on tiles, a train or a reservation on the grid, a body or a
    /// path on the grid.
    ///
    /// The world's extent is `"bounds"` in world units (Stage F3d, save
    /// version 6). A world saved before that has a `"map"` of tiles instead,
    /// read as the bounds its tiles cover (see `LegacyMap`); exactly one of
    /// the two is accepted.
    ///
    /// Under traffic control (Stage T) every reservation must fit its train
    /// and this world, and no two trains may hold the same track (see
    /// `trafficProblem()`); without it, no train may have a reservation.
    public init(from decoder: any Decoder) throws {
        try self.init(from: decoder, madeBeforeSpacing: false)
    }

    /// Decodes a world as ``init(from:)`` does. When `madeBeforeSpacing`,
    /// the world comes from a save made before Stage F2 (save version 4 or
    /// below, see ``SavedGame``): it has no `"spacingExemptions"`, and
    /// whatever pairs of edges it has closer than the track spacing become
    /// its exemptions, so the save loads as it was (ARCHITECTURE decision
    /// 52).
    init(from decoder: any Decoder, madeBeforeSpacing: Bool) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch (container.contains(.bounds), container.contains(.map)) {
        case (true, false):
            bounds = try container.decode(WorldBounds.self, forKey: .bounds)
        case (false, true):
            bounds = try container.decode(LegacyMap.self, forKey: .map).bounds
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "A world has its bounds (\"bounds\"), or, in a save before version 6, its map (\"map\"): exactly one of them."
            ))
        }
        stations = try container.decode([Station].self, forKey: .stations)
        trains = try container.decode([Train].self, forKey: .trains)
        clock = try container.decode(GameClock.self, forKey: .clock)
        economy = try container.decode(GameEconomy.self, forKey: .economy)
        nextStationID = try container.decode(Int.self, forKey: .nextStationID)
        nextTrainID = try container.decode(Int.self, forKey: .nextTrainID)
        lines = container.contains(.lines) ? try container.decode([ServiceLine].self, forKey: .lines) : []
        nextLineID = container.contains(.nextLineID) ? try container.decode(Int.self, forKey: .nextLineID) : 1
        serviceDay = container.contains(.serviceDay) ? try container.decode(ServiceDay.self, forKey: .serviceDay) : .standard
        network = container.contains(.network) ? try container.decode(RailwayNetwork.self, forKey: .network) : RailwayNetwork()
        isTrafficControlEnabled = container.contains(.trafficControl) ? try container.decode(Bool.self, forKey: .trafficControl) : false
        passengers = container.contains(.passengers) ? try container.decode([StationPassengers].self, forKey: .passengers) : []
        riders = container.contains(.riders) ? try container.decode([TrainRiders].self, forKey: .riders) : []
        passengerRoutingMode = container.contains(.passengerRoutingMode)
            ? try container.decode(PassengerRoutingMode.self, forKey: .passengerRoutingMode) : .direct
        weeklyDemand = container.contains(.weeklyDemand) ? try container.decode(Bool.self, forKey: .weeklyDemand) : false
        demandEvents = container.contains(.demandEvents) ? try container.decode(DemandEventSchedule.self, forKey: .demandEvents) : nil
        townGrowth = container.contains(.townGrowth) ? try container.decode(TownGrowth.self, forKey: .townGrowth) : nil
        passengerRouteBalances = container.contains(.passengerRouteBalances)
            ? try container.decode([PassengerRouteBalance].self, forKey: .passengerRouteBalances) : []
        accounts = container.contains(.accounts) ? try container.decode(CompanyAccounts.self, forKey: .accounts) : CompanyAccounts()
        geoAnchor = container.contains(.geoAnchor) ? try container.decode(GeoAnchor.self, forKey: .geoAnchor) : nil
        if madeBeforeSpacing {
            guard network.spacingExemptions.isEmpty else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "A save made before Stage F2 has no spacing exemptions."
                ))
            }
            let geometries = network.edges.compactMap { network.geometry(of: $0.id) }
            network.exemptFromSpacing(network.tooClosePairs(geometries: geometries))
        }

        if let problem = invariantViolation() {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: problem)
            )
        }
    }

    /// Encodes the world. A world without lines has no `"lines"` key, one
    /// that never had a line no `"nextLineID"`, and one with the standard
    /// service day no `"serviceDay"`: such worlds save exactly as before
    /// lines existed, and those saves read as having none, handing out line
    /// IDs from 1, with the standard day. Likewise a world whose track
    /// network never had a node or an edge has no `"network"` key (Stage
    /// S3), and a save without one reads as an empty network; a world
    /// with traffic control off has no `"trafficControl"` key (Stage T),
    /// which is also how saves made before it read; and a blank map has no
    /// `"geoAnchor"` (Stage E2). An explicit `null` for any of them is
    /// rejected. The world's extent is written as `"bounds"`, in world units
    /// (Stage F3d).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(stations, forKey: .stations)
        try container.encode(trains, forKey: .trains)
        if !lines.isEmpty {
            try container.encode(lines, forKey: .lines)
        }
        if serviceDay != .standard {
            try container.encode(serviceDay, forKey: .serviceDay)
        }
        try container.encode(clock, forKey: .clock)
        try container.encode(economy, forKey: .economy)
        try container.encode(nextStationID, forKey: .nextStationID)
        try container.encode(nextTrainID, forKey: .nextTrainID)
        if nextLineID != 1 {
            try container.encode(nextLineID, forKey: .nextLineID)
        }
        if !network.isPristine {
            try container.encode(network, forKey: .network)
        }
        if isTrafficControlEnabled {
            try container.encode(true, forKey: .trafficControl)
        }
        if !passengers.isEmpty {
            try container.encode(passengers, forKey: .passengers)
        }
        if !riders.isEmpty {
            try container.encode(riders, forKey: .riders)
        }
        if weeklyDemand {
            try container.encode(weeklyDemand, forKey: .weeklyDemand)
        }
        try container.encodeIfPresent(demandEvents, forKey: .demandEvents)
        try container.encodeIfPresent(townGrowth, forKey: .townGrowth)
        if passengerRoutingMode != .direct {
            try container.encode(passengerRoutingMode, forKey: .passengerRoutingMode)
        }
        if !passengerRouteBalances.isEmpty {
            try container.encode(passengerRouteBalances, forKey: .passengerRouteBalances)
        }
        if !accounts.isPristine {
            try container.encode(accounts, forKey: .accounts)
        }
        if let geoAnchor {
            try container.encode(geoAnchor, forKey: .geoAnchor)
        }
    }

    /// The world's size as a save before version 6 holds it: a map of
    /// tiles (``LegacyGrid/tileLength`` units a tile) with its land, read as
    /// the bounds it covers and never written (Stage F3d, ARCHITECTURE
    /// decision 54).
    ///
    /// Two forms (Stage E1, ARCHITECTURE decision 48):
    ///
    /// - `{"width", "height", "occupied"}`, written from save version 2 to
    ///   5: only the tiles that are not empty ground, each with its
    ///   position, in row-major order.
    /// - `{"width", "height", "tiles"}`: every tile in row-major order, the
    ///   form every save had from Stage I to save version 1.
    ///
    /// Every tile is empty ground, so `"occupied"` is `[]`. Until Stage F3c
    /// a tile could hold grid track (`"track"`, `"turnout"`, `"crossing"`)
    /// or a station (`"station"`); a save with any, which only a save made
    /// by hand could hold, is refused with that reason (ARCHITECTURE
    /// decision 51).
    private struct LegacyMap: Decodable {
        /// A saved tile: `{"empty": {}}`, or one of the grid's kinds,
        /// refused.
        private struct Tile: Decodable {
            private struct Key: CodingKey {
                let stringValue: String
                var intValue: Int? { nil }
                init(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: Key.self)
                guard container.allKeys.count == 1, let kind = container.allKeys.first else {
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: container.codingPath, debugDescription: "A tile is exactly one kind."))
                }
                switch kind.stringValue {
                case "empty":
                    _ = try container.nestedContainer(keyedBy: Key.self, forKey: kind)
                case "track", "turnout", "crossing", "station":
                    throw DecodingError.dataCorruptedError(
                        forKey: kind, in: container,
                        debugDescription: "A map with grid track or a station on a tile (\"\(kind.stringValue)\") is no longer supported: the grid was removed in Stage F3c. Only a save made by hand could hold one."
                    )
                default:
                    throw DecodingError.dataCorruptedError(forKey: kind, in: container, debugDescription: "\(kind.stringValue) is not a kind of tile.")
                }
            }
        }

        /// A tile that is not empty ground, and where it is: never one now.
        private struct Occupied: Decodable {
            let x: Int
            let y: Int
            let tile: Tile
        }

        private enum CodingKeys: String, CodingKey {
            case width, height, occupied, tiles
        }

        /// The bounds the map covers.
        let bounds: WorldBounds

        /// Decodes either form, rejecting a size the map could not have
        /// (1 to ``LegacyGrid/maximumTiles`` tiles a side), both forms or
        /// neither, a tile count that does not match the size, an occupied
        /// tile off the map, and any tile that is not empty ground.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let width = try container.decode(Int.self, forKey: .width)
            let height = try container.decode(Int.self, forKey: .height)
            func corrupt(_ key: CodingKeys, _ description: String) -> DecodingError {
                DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: description)
            }
            let sides = 1...LegacyGrid.maximumTiles
            guard sides.contains(width), sides.contains(height) else {
                throw corrupt(.width, "\(width)x\(height) is not a size a map can have.")
            }
            switch (container.contains(.occupied), container.contains(.tiles)) {
            case (true, false):
                // A tile that is not empty is refused while it is read; one
                // that is empty is not occupied.
                if let entry = try container.decode([Occupied].self, forKey: .occupied).first {
                    guard (0..<width).contains(entry.x), (0..<height).contains(entry.y) else {
                        throw corrupt(.occupied, "Tile (\(entry.x), \(entry.y)) lies off the \(width)x\(height) map.")
                    }
                    throw corrupt(.occupied, "Tile (\(entry.x), \(entry.y)) is listed as occupied but empty.")
                }
            case (false, true):
                let tiles = try container.decode([Tile].self, forKey: .tiles)
                guard tiles.count == width * height else {
                    throw corrupt(.tiles, "Tile count \(tiles.count) does not match a valid \(width)x\(height) map.")
                }
            case (true, true):
                throw corrupt(.occupied, "A map has its occupied tiles or every tile, not both.")
            case (false, false):
                throw corrupt(.occupied, "A map needs its occupied tiles.")
            }
            // At most 1024 × 1024 units a side: within the bounds' limit.
            bounds = try WorldBounds(width: Int64(width) * LegacyGrid.tileLength, height: Int64(height) * LegacyGrid.tileLength)
        }
    }

    private func invariantViolation() -> String? {
        let stationIDs = stations.map(\.id.rawValue)
        guard Self.isStrictlyIncreasing(stationIDs, below: nextStationID) else {
            return "Station IDs must be unique, ascending and below nextStationID."
        }
        guard Self.isStrictlyIncreasing(trains.map(\.id.rawValue), below: nextTrainID) else {
            return "Train IDs must be unique, ascending and below nextTrainID."
        }
        guard Self.isStrictlyIncreasing(lines.map(\.id.rawValue), below: nextLineID) else {
            return "Line IDs must be unique, ascending and below nextLineID."
        }
        var assigned: Set<TrainID> = []
        for line in lines {
            guard Self.isValidName(line.name) else { return "Line \(line.id.rawValue) has an invalid name." }
            if let missing = line.stops.first(where: { station(id: $0) == nil }) {
                return "Line \(line.id.rawValue) calls at station \(missing.rawValue), which does not exist."
            }
            for service in 0..<line.serviceCount {
                for id in line.trains(ofService: service) {
                    guard let train = train(id: id) else { return "Line \(line.id.rawValue) has train \(id.rawValue), which does not exist." }
                    guard assigned.insert(id).inserted else { return "Train \(id.rawValue) is assigned to two lines or services." }
                    // A line sends its trains out on trips that run once, and
                    // no other service can start while a train is on a line.
                    guard train.execution == nil || train.timetablePeriod == nil else {
                        return "Line \(line.id.rawValue)'s train \(id.rawValue) runs a repeating timetable."
                    }
                }
                if let last = line.lastDispatch(ofService: service), last > clock.now {
                    return "Line \(line.id.rawValue) sent a train out after the current minute."
                }
            }
            if let last = line.outerLastDispatch, last > clock.now {
                return "Line \(line.id.rawValue) sent a train out the outer way after the current minute."
            }
        }
        for station in stations {
            guard Self.isValidName(station.name) else { return "Station \(station.id.rawValue) has an invalid name." }
            guard bounds.contains(station.point) else {
                return "Station \(station.id.rawValue) stands outside the world's bounds."
            }
        }
        guard trains.allSatisfy({ Self.isValidName($0.name) }) else {
            return "A train has an invalid name."
        }
        // Stage S3: the network lies in the world's bounds; Stage S4: at the
        // heights a world allows.
        guard network.nodes.allSatisfy({ isInWorld($0.position) }) else {
            return "A track node lies outside the world's bounds or beyond the heights track may have."
        }
        guard network.edges.allSatisfy({ $0.curve.controlPoints.allSatisfy(bounds.contains) }) else {
            return "A track edge's curve leaves the world's bounds."
        }
        if let problem = networkRuleProblem() {
            return problem
        }
        for train in trains {
            if train.trafficVisits.contains(where: { visit in station(id: visit.station) == nil || visit.arrival > clock.now || visit.departure.map { $0 > clock.now || $0 < visit.arrival } == true }) {
                return "Traffic visit is invalid or after the clock."
            }
            if let position = train.position, !isOnTrack(position) {
                return "Train \(train.id.rawValue) is not on this map's track."
            }
            if case .onEdge(let traversal, let offset)? = train.position,
               !isNetworkTrail(train.trailEdges, behind: traversal, offset: offset, length: train.length) {
                return "Train \(train.id.rawValue)'s body is not on track it could have come along."
            }
            // IDs are never reused, so an edge that was built once is below
            // the next number even after it was removed.
            guard train.movement.edges.allSatisfy({ ($0.networkNumber ?? .max) < network.nextEdgeNumber }) else {
                return "Train \(train.id.rawValue)'s path names an edge that was never built."
            }
            // Stage S5: a path that stops part of the way along its last edge
            // stops inside it (checked while that edge is still there).
            if let end = train.movement.end, case .onEdge(let traversal, _)? = train.position,
               let last = network.edge(train.movement.edges.last ?? traversal.edge), end >= last.length {
                return "Train \(train.id.rawValue)'s path stops beyond the end of its last edge."
            }
            if let stop = train.timetable.first(where: { station(id: $0.station) == nil }) {
                return "Train \(train.id.rawValue)'s timetable names station \(stop.station.rawValue), which does not exist."
            }
            if let problem = serviceProblem(of: train) {
                return problem
            }
            // Stage W2b: what a service did happened no later than now: it
            // arrived, its doors opened if its exchange has started, they
            // started closing, and it left the call before.
            if let times = train.times,
               times.latest > clock.now || (times.exchangeEnd != nil && Self.saturating(times.arrival, plus: ServiceDwell.doorOpening) > clock.now) {
                return "Train \(train.id.rawValue)'s service times are after the clock."
            }
        }
        return trafficProblem() ?? passengerProblem() ?? riderProblem() ?? accountsProblem() ?? demandEventProblem() ?? townGrowthProblem()
    }

    /// Why the trains' reservations break a Stage T rule (ARCHITECTURE
    /// decision 32, point 14), or `nil`. ``Train``'s decoder has checked
    /// each reservation is in order without repeats, and only on a placed
    /// train.
    ///
    /// Without traffic control no train has a reservation. With it, a train
    /// with a way left to go has one holding at least everything the rest of
    /// its route needs, and a train that stands has none; every reserved
    /// resource exists (a node, or a span of an edge as its platforms cut it
    /// now), except on the train's own way ahead; and no two trains hold the
    /// same track. A reservation may hold more than the
    /// route still needs (track the train has passed, which Stage T does not
    /// release): that is a lock, not an error.
    private func trafficProblem() -> String? {
        guard isTrafficControlEnabled else {
            guard trains.allSatisfy({ $0.reservation.isEmpty }) else { return "A train has a reservation while traffic control is off." }
            return nil
        }
        var held: [(id: TrainID, resources: Set<TrackResource>)] = []
        for train in trains where train.position != nil {
            let id = train.id.rawValue
            let envelope = routeEnvelope(of: train)
            guard envelope.moves != train.reservation.isEmpty else {
                return envelope.moves
                    ? "Train \(id) has a way left to go under traffic control but no reservation."
                    : "Train \(id) stands but keeps a reservation."
            }
            if envelope.moves, !envelope.resources.isSubset(of: Set(train.reservation)) {
                // Stage U2: a train following another holds its route part
                // of the way, from where it stands.
                guard authorityEnvelope(of: train, to: 0).isSubset(of: Set(train.reservation)) else {
                    return "Train \(id)'s reservation does not hold the rest of its route."
                }
            }
            for resource in train.reservation where !resourceExists(resource) && !envelope.resources.contains(resource) {
                return "Train \(id) has reserved \(resource), which is not track of this world."
            }
            let resources = self.held(train)
            if let other = held.first(where: { !$0.resources.isDisjoint(with: resources) }) {
                return "Trains \(other.id.rawValue) and \(id) hold the same track under traffic control."
            }
            held.append((train.id, resources))
        }
        return nil
    }

    /// Whether `resource` is track of this world now: a node of the track
    /// network, or a span of an edge as its platforms cut it now (see
    /// ``trackSpans(of:)``).
    private func resourceExists(_ resource: TrackResource) -> Bool {
        switch resource {
        case .node(let node):
            return trackNode(node) != nil
        case .span(let span):
            return trackSpans(of: span.edge).contains(span)
        }
    }

    /// Why the track network breaks a Stage S4 rule, or `nil`: an edge
    /// steeper than the maximum grade or on a structure that cannot carry it
    /// at its heights, two edges meeting without clearance, two edges closer
    /// than the track spacing that are not exempt or exempt edges that are
    /// not (Stage F2), or a platform that does not fit its edge or overlaps
    /// another.
    private func networkRuleProblem() -> String? {
        var geometries: [TrackGeometry] = []
        for edge in network.edges {
            guard let geometry = network.geometry(of: edge.id) else { return "Track edge \(edge.id) has no geometry." }
            geometries.append(geometry)
            guard geometry.steepestGrade.isNoSteeper(than: TrackProfile.maximumGrade) else {
                return "Track edge \(edge.id) is steeper than the maximum grade."
            }
            guard edge.structure.allows(height: geometry.startHeight), edge.structure.allows(height: geometry.endHeight) else {
                return "Track edge \(edge.id)'s structure cannot carry it at its heights."
            }
        }
        if let (a, b) = network.firstConflictingPair(geometries: geometries) {
            return "Track edges \(a) and \(b) meet without clearance."
        }
        let tooClose = network.tooClosePairs(geometries: geometries)
        if tooClose != network.spacingExemptions {
            if let pair = tooClose.first(where: { !network.spacingExemptions.contains($0) }) {
                return "Track edges \(pair.first) and \(pair.second) are closer than the track spacing."
            }
            return "A spacing exemption lists two edges that keep the track spacing."
        }
        // The network's decoder has checked the platforms are in order and
        // do not overlap.
        for platform in network.platforms {
            guard station(id: platform.station) != nil else {
                return "A platform belongs to station \(platform.station.rawValue), which does not exist."
            }
            guard isValidPlatform(platform) else {
                return "Station \(platform.station.rawValue) has a platform that does not fit its edge."
            }
        }
        return nil
    }

    /// Why a train's service does not fit this world's stations, or `nil`.
    /// ``Train``'s decoder has already checked that the service fits the
    /// timetable, position and movement as far as it can without the map.
    ///
    /// A waiting train is stopped at its stop's station. A travelling train's
    /// path is not spent, and it ends at a berth of a platform of the
    /// station of the stop it travels to that the train fits (Stage S5), as every path from the service does; such a platform
    /// cannot be removed while the service needs it (see
    /// ``removeTrackPlatform(_:on:from:)``). Since Stage V2 a travelling
    /// train may also be on its way to, or stand at, a passing place: a
    /// berth of another station (see ``isAtPassingPlace(_:)``). Where an edge on the way was
    /// removed, so the path can no longer be followed to its last edge, that
    /// edge still has such a berth, one way or the other, where it ends.
    private func serviceProblem(of train: Train) -> String? {
        guard let execution = train.execution, train.position != nil,
              let station = station(id: train.timetable[execution.stop].station)
        else { return nil }
        switch execution {
        case .waitingAtStop:
            guard isStopped(train, at: station.id) else {
                return "Train \(train.id.rawValue)'s service waits at a station the train is not stopped at."
            }
        case .travellingToStop:
            if standingPoint(of: train) != nil {
                // Stage V2: only at a passing place, a berth of another
                // station than its call's.
                guard !isStopped(train, at: station.id), stations.contains(where: { standsAtBerth(train, of: $0.id) }) else {
                    return "Train \(train.id.rawValue)'s service travels, but its path is spent."
                }
            } else {
                // Stage V2: or to a passing place.
                guard pathEndsAtBerth(of: train, for: station.id) || stations.contains(where: { pathEndsAtBerth(of: train, for: $0.id) }) else {
                    return "Train \(train.id.rawValue)'s service travels on a path that does not end at its next stop."
                }
            }
        }
        return nil
    }

    /// Whether `train` stands at a berth of station `id` for its length
    /// (see ``berths(of:length:)``): its head exactly there, the way it
    /// faces.
    private func standsAtBerth(_ train: Train, of id: StationID) -> Bool {
        guard case .onEdge(let traversal, let offset)? = train.position else { return false }
        return berths(of: id, length: train.length).contains(Berth(traversal: traversal, offset: offset))
    }

    /// Whether the path of `train` ends at a berth
    /// of station `id` for its length (Stage S5; see ``berths(of:length:)``):
    /// followed along its edges to the last, exactly; when an edge on the
    /// way no longer exists, at a berth on the last edge either way.
    private func pathEndsAtBerth(of train: Train, for id: StationID) -> Bool {
        guard case .onEdge(let traversal, _)? = train.position else { return false }
        let lastEdge = train.movement.remainingEdges.last ?? traversal.edge
        guard let length = network.edge(lastEdge)?.length else { return false }
        let end = train.movement.end ?? length
        let berths = berths(of: id, length: train.length)
        var last: TrackTraversal? = traversal
        for edge in train.movement.remainingEdges {
            last = last.flatMap { arrival in transitions(after: arrival).first { $0.edge == edge } }
        }
        guard let last else { return berths.contains { $0.traversal.edge == lastEdge && $0.offset == end } }
        return berths.contains(Berth(traversal: last, offset: end))
    }

    private static func isStrictlyIncreasing(_ ids: [Int], below limit: Int) -> Bool {
        zip(ids, ids.dropFirst()).allSatisfy { $0 < $1 } && (ids.last ?? 0) < limit && (ids.first ?? 1) >= 1
    }
}

// V3 actual traffic events, written only by GameWorld.
extension GameWorld {
    /// Record only actual visits needed by this plan. Crossing tests use
    /// the physical path, so a zero rate or truncated authority never
    /// creates a fictitious event. Called at one-second boundaries in V3.
    mutating func recordTrafficVisits(_ plan: TrafficPlan, before: [Train]?) {
        guard !plan.waits.isEmpty else { return }
        for index in trains.indices {
            let train = trains[index]
            guard let service = plan.services.first(where: { $0.train.id == train.id }) else { continue }
            let needed = service.points.filter { p in
                plan.waits.contains { w in
                    w.station == p.station && ((w.train == train.id && w.stop == p.stop && w.cycle == p.cycle)
                                              || (w.other == train.id && w.otherStop == p.stop && w.otherCycle == p.cycle))
                }
            }
            for point in needed {
                var arrival: GameTime?, departure: GameTime?
                if let execution = train.execution, execution.cycle == point.cycle, execution.stop == point.stop,
                   isStopped(train, at: point.station) {
                    arrival = point.calls ? train.times?.arrival : clock.now
                }
                if let old = before?.first(where: { $0.id == train.id }), let execution = old.execution {
                    let fromStop = execution.stop
                    let belongs = execution.cycle == point.cycle && (fromStop == point.stop || (point.calls && fromStop + 1 == point.stop))
                    if belongs {
                        let stretches = routeStretches(of: old).stretches
                        let moved = max(0, routeLength(of: old) - routeLength(of: train))
                        var distance: Int64 = 0
                        for stretch in stretches {
                            for berth in berths(of: point.station, length: train.length) where berth.traversal == stretch.traversal {
                                let reach = distance + berth.offset - stretch.from
                                if berth.offset >= stretch.from, berth.offset <= stretch.to, reach > 0, reach <= moved {
                                    arrival = clock.now
                                    if !(standingPoint(of: train) != nil && isStopped(train, at: point.station)) { departure = clock.now }
                                }
                            }
                            distance += stretch.to - stretch.from
                        }
                    }
                }
                if let found = trains[index].trafficVisits.firstIndex(where: { $0.station == point.station && $0.stop == point.stop && $0.cycle == point.cycle }) {
                    if let departure { trains[index].trafficVisits[found].departure = departure }
                } else if let arrival {
                    trains[index].trafficVisits.append(TrafficVisit(station: point.station, stop: point.stop, cycle: point.cycle, arrival: arrival, departure: departure))
                }
            }
            trains[index].trafficVisits.sort {
                if $0.cycle != $1.cycle { return $0.cycle < $1.cycle }
                if $0.stop != $1.stop { return $0.stop < $1.stop }
                return $0.station < $1.station
            }
        }
    }

    mutating func recordTrafficDeparture(_ index: Int) {
        let train = trains[index]
        for i in trains[index].trafficVisits.indices where trains[index].trafficVisits[i].departure == nil {
            let visit = trains[index].trafficVisits[i]
            if let execution = train.execution, visit.cycle == execution.cycle, visit.stop == execution.stop,
               isStopped(train, at: visit.station) {
                trains[index].trafficVisits[i].departure = clock.now
            }
        }
    }
}
