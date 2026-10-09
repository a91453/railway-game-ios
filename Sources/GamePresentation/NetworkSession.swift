import GameCore

// The network tool (Stage C1): building the track network at any angle from
// taps on the map, its platforms, and removing it. Every change is one or
// more GameWorld commands applied to a copy of the world that replaces the
// session's world only when all of them succeed, so a refused step leaves the
// world exactly as it was. The session never decides whether track can be
// built: GameCore does, and the preview shows its answer by running the same
// commands on a copy that is thrown away.

extension GameSession {
    // MARK: - Mode and taps

    /// Switches what a tap does with the network tool and forgets what the
    /// previous mode picked. Never changes the world.
    public func setNetworkMode(_ mode: NetworkToolMode) {
        guard mode != networkMode else { return }
        networkMode = mode
        clearNetworkDraft()
    }

    /// Forgets the ends picked for the next stretch of track and the place
    /// picked on an edge. Never changes the world.
    public func clearNetworkDraft() {
        networkStart = nil
        networkEnd = nil
        networkEdgePoint = nil
        message = nil
    }

    /// A tap on the map at `point` with the network tool, reaching
    /// `reach` world units to an existing node or edge (see
    /// ``NetworkBuilding/touchRadius``). Never changes the world.
    ///
    /// Building, the first tap picks where the track starts and later taps
    /// where it ends: the nearest node within reach; else the nearest place
    /// on the track within reach, for a turnout there (a place closer than
    /// ``NetworkBuilding/minimumSpacing`` to an end of its edge is that end's
    /// node); else a new point there, at ``networkHeight``. With
    /// ``networkSnapsToTrack`` off every tap is a new point. Tapping the start again forgets both. Placing a platform or
    /// removing, a tap picks the nearest place on an edge within reach.
    /// Taps outside the world's bounds are ignored.
    public func tapNetwork(at point: PlanPoint, reach: Int64) {
        guard world.bounds.contains(point) else { return }
        message = nil
        switch networkMode {
        case .build:
            // With snapping off a tap is always a new point at the height
            // being built, beside or over the track; on, track within reach
            // is joined whatever its height (a ramp starts there).
            let anchor = networkAnchor(at: point, reach: reach)
            if networkStart == nil {
                networkStart = anchor
            } else if anchor == networkStart {
                networkStart = nil
                networkEnd = nil
            } else {
                networkEnd = anchor
            }
        case .platform:
            networkEdgePoint = world.trackEdgePoint(near: point, within: reach)
            platformStationID = networkEdgePoint.flatMap { nearestStation(to: $0) }
            if platformStationID == nil, let stretch = networkPlatformStretch, let geometry = world.trackGeometry(of: stretch.edge) {
                let middle = geometry.location(at: (stretch.start + stretch.end) / 2).position.plan
                // A name the player typed stays (only a suggestion is
                // replaced).
                suggestStationName(at: middle)
            }
            suggestPlatformCars()
        case .remove:
            networkEdgePoint = world.trackEdgePoint(near: point, within: reach)
        }
    }

    /// Where a tap or a drag at `point` picks an end of the next stretch
    /// of track (see ``tapNetwork(at:reach:)``).
    func networkAnchor(at point: PlanPoint, reach: Int64) -> NetworkAnchor {
        networkSnapsToTrack
            ? world.trackNode(near: point, within: reach).map { NetworkAnchor.node($0.id) }
                ?? world.trackEdgePoint(near: point, within: reach).map(trackAnchor)
                ?? .point(point)
            : .point(point)
    }

    // MARK: - Building

    /// A turnout at `point`, or the node at the end of its edge when it is
    /// closer than ``NetworkBuilding/minimumSpacing`` to it.
    private func trackAnchor(_ point: NetworkEdgePoint) -> NetworkAnchor {
        guard let edge = world.network.edge(point.edge) else { return .track(point) }
        if point.distance < NetworkBuilding.minimumSpacing { return .node(edge.from) }
        if edge.length - point.distance < NetworkBuilding.minimumSpacing { return .node(edge.to) }
        return .track(point)
    }

    /// The stretch of track the picked ends would make, and whether
    /// GameCore would build it and for how much; `nil` until both ends are
    /// picked (or in another mode).
    public var networkPreview: NetworkPreview? {
        networkDraftPreview?.preview
    }

    /// ``networkPreview``, with the middle of an X crossover (empty for one
    /// stretch). Building it on a copy of the world takes milliseconds, and
    /// the map, its build button and the panels read it many times a frame
    /// while a finger draws; so it is worked out once for each draft (the
    /// ends and the tool's options) and world, and kept until one changes.
    var networkDraftPreview: (preview: NetworkPreview, crossing: [WorldCoordinate])? {
        guard networkMode == .build, let start = networkStart, let end = networkEnd else { return nil }
        // Read so that what shows the preview is redrawn when the world
        // changes; the revision below says whether it did.
        _ = world
        let key = NetworkPreviewMemo.Key(
            start: start, end: end, structure: networkStructure, height: networkHeight, followsTrack: networkFollowsTrack,
            buildsScissors: networkBuildsScissors, easesGrade: networkEasesGrade, worldRevision: worldRevision
        )
        if let memo = networkPreviewMemo, memo.key == key { return memo.preview }
        let found: (preview: NetworkPreview, crossing: [WorldCoordinate])? = if let scissors = scissorsPreview() {
            scissors
        } else {
            preview(from: start, to: end).map { ($0, []) }
        }
        networkPreviewMemo = NetworkPreviewMemo(key: key, preview: found)
        return found
    }

    /// Builds the stretch of track between the picked ends through
    /// `GameWorld.buildTrackNode(at:)` for each new end and
    /// `GameWorld.buildTrackEdge(from:to:curve:profile:structure:)`, all or
    /// nothing. The end then becomes the start of the next stretch, so taps
    /// lay a line piece by piece, each continuing the last.
    public func buildNetworkTrack() {
        if scissorsPlan() != nil {
            buildNetworkScissors()
            return
        }
        guard let start = networkStart, let end = networkEnd else {
            message = StatusMessage(kind: .failure, text: language.text(
                "Tap where the track starts, then where it ends.",
                "請先點軌道的起點，再點終點。"
            ))
            return
        }
        let plan: EdgePlan
        switch edgePlan(from: start, to: end) {
        case .success(let found): plan = found
        case .failure(let problem):
            message = StatusMessage(kind: .failure, text: problem.text(in: language))
            return
        }
        var built: (edge: TrackEdgeID, to: TrackNodeID)?
        let balance = world.economy.balance
        perform { world throws(GameError) in
            var draft = world
            let result = try plan.build(in: &draft, structure: networkStructure)
            let cleared = world.placedBuildings(clearedIn: draft).count
            world = draft
            built = result
            let cost = Money(balance.amount - world.economy.balance.amount)
            let length = NetworkBuilding.lengthText(plan.length, in: language)
            let structure = networkStructure.name(in: language)
            // Decision 95: the company's buildings in the way come down.
            let demolished = cleared == 0 ? ("", "") : (
                cleared == 1 ? ", pulling down 1 of your buildings" : ", pulling down \(cleared) of your buildings",
                "，拆除自己的建物 \(cleared) 棟"
            )
            return language.text(
                "Built \(result.edge.displayText(in: language)): \(length), \(structure.lowercased()), for \(cost.moneyText)\(demolished.0).",
                "已建造\(result.edge.displayText(in: language))：\(length)，\(structure)，花費 \(cost.moneyText)\(demolished.1)。"
            )
        }
        if let built {
            networkStart = .node(built.to)
            networkEnd = nil
            playSound?(.track)
        }
    }

    private func preview(from start: NetworkAnchor, to end: NetworkAnchor) -> NetworkPreview? {
        let plan: EdgePlan
        switch edgePlan(from: start, to: end) {
        case .success(let found): plan = found
        case .failure(let problem):
            // No curve: the straight line between the ends, drawn as one
            // that cannot be built, and the reason. Without the ends (a node
            // was removed) there is nothing to show.
            guard let from = world.position(of: start, height: networkHeight), let to = world.position(of: end, height: networkHeight) else {
                return nil
            }
            let dx = Double(to.x - from.x), dy = Double(to.y - from.y)
            return NetworkPreview(
                curve: .straight, profile: .uniform, points: [from, to], length: Int64((dx * dx + dy * dy).squareRoot().rounded()),
                startHeight: from.z, endHeight: to.z, joinsStart: false, joinsEnd: false, cost: nil, problem: problem.text(in: language)
            )
        }
        var draft = world
        let cost: Money?
        let problem: String?
        do throws(GameError) {
            _ = try plan.build(in: &draft, structure: networkStructure)
            cost = Money(world.economy.balance.amount - draft.economy.balance.amount)
            problem = nil
        } catch {
            cost = nil
            problem = error.playerMessage(in: language)
        }
        return NetworkPreview(
            curve: plan.curve, profile: plan.profile, points: plan.geometry?.points ?? [plan.from, plan.to],
            length: plan.length, startHeight: plan.from.z, endHeight: plan.to.z,
            joinsStart: plan.joinsStart, joinsEnd: plan.joinsEnd, cost: cost, problem: problem,
            cleared: problem == nil ? world.placedBuildings(clearedIn: draft) : []
        )
    }

    /// The edge the picked ends make: where they are, the curve that
    /// continues the track at each end that has some (when
    /// ``networkFollowsTrack`` is on), and the vertical profile.
    private func edgePlan(from start: NetworkAnchor, to end: NetworkAnchor) -> Result<EdgePlan, NetworkProblem> {
        guard let from = world.position(of: start, height: networkHeight), let to = world.position(of: end, height: networkHeight) else {
            return .failure(.missingNode)
        }
        let isNewPoint: (NetworkAnchor) -> Bool = { if case .node = $0 { false } else { true } }
        if isNewPoint(start) || isNewPoint(end) {
            let dx = to.x - from.x, dy = to.y - from.y
            guard dx * dx + dy * dy >= NetworkBuilding.minimumSpacing * NetworkBuilding.minimumSpacing else { return .failure(.tooClose) }
        }
        var startTangent: PlanVector?
        var endTangent: PlanVector?
        if networkFollowsTrack {
            if case .node(let id) = start, !world.joiningDirections(at: id).isEmpty {
                guard let direction = world.joiningDirection(at: id, toward: to.plan) else { return .failure(.tooSharp) }
                startTangent = direction
            }
            if case .track(let point) = start {
                guard let direction = world.joiningDirection(at: point, toward: to.plan) else { return .failure(.tooSharp) }
                startTangent = direction
            }
            if case .node(let id) = end, !world.joiningDirections(at: id).isEmpty {
                guard let direction = world.joiningDirection(at: id, toward: from.plan) else { return .failure(.tooSharp) }
                endTangent = direction
            }
            if case .track(let point) = end {
                guard let direction = world.joiningDirection(at: point, toward: from.plan) else { return .failure(.tooSharp) }
                endTangent = direction
            }
        }
        guard let curve = NetworkBuilding.curve(from: from.plan, leaving: startTangent, to: to.plan, leaving: endTangent) else {
            return .failure(.tooSharp)
        }
        var profile = TrackProfile.uniform
        var geometry = TrackGeometry(from: from, to: to, curve: curve)
        if networkEasesGrade, from.z != to.z, let length = geometry?.length {
            // A quarter of the length at each end eases into and out of
            // the grade; the middle half is steady.
            profile = TrackProfile(startTransition: length / 4, endTransition: length / 4)
            geometry = TrackGeometry(from: from, to: to, curve: curve, profile: profile)
        }
        return .success(EdgePlan(
            start: start, end: end, from: from, to: to, curve: curve, profile: profile, geometry: geometry,
            joinsStart: startTangent != nil, joinsEnd: endTangent != nil
        ))
    }

    // MARK: - Platforms

    /// The stretch of its edge the next platform would take: centred on
    /// the picked place, ``platformCars`` cars long (one car is
    /// `Train.carLength`), moved along to stay on the edge, or the whole
    /// edge if it is shorter.
    public var networkPlatformStretch: (edge: TrackEdgeID, start: Int64, end: Int64)? {
        guard networkMode == .platform, let point = networkEdgePoint, let edge = world.network.edge(point.edge) else { return nil }
        let length = min(Int64(max(1, platformCars)) * Train.carLength, edge.length)
        let start = min(max(0, point.distance - length / 2), edge.length - length)
        return (point.edge, start, start + length)
    }

    /// The ridership a managed company gives a new station at `point`: on
    /// a real-world map the population grid covers, from the people living
    /// around it (``StationDemand/realWorld(residents:kind:)``), of the
    /// kind the places around it make it (homes without the places grid);
    /// anywhere else the city's (``StationDemand/cityDefault``).
    public func newStationDemand(at point: PlanPoint) -> StationDemand {
        guard let population, let frame = RealWorldFrame(world: world) else { return .cityDefault }
        let place = frame.coordinate(worldX: Double(point.x), worldY: Double(point.y))
        let radius = StationDemand.catchmentRadius
        guard let residents = population.people(within: radius, ofLatitude: place.latitude, longitude: place.longitude) else {
            return .cityDefault
        }
        guard let places else { return .realWorld(residents: residents) }
        let kind = StationDemandKind.realWorld(
            residents: residents,
            places: places.places(within: radius, ofLatitude: place.latitude, longitude: place.longitude),
            totals: Dictionary(uniqueKeysWithValues: PlaceGrid.Kind.allCases.map { ($0, places.total(of: $0)) }),
            population: population.total
        )
        return .realWorld(residents: residents, kind: kind)
    }

    /// Adds a platform along ``networkPlatformStretch`` through
    /// `GameWorld.addTrackPlatform(_:on:from:to:)` for the station
    /// ``platformStationID``, or for a new station built first through
    /// `GameWorld.buildStation(named:at:)` at the middle of the platform
    /// (Stage F1); a managed company gives the new station its ridership
    /// (``newStationDemand(at:)``), unless the land does (Phase 6b). All or
    /// nothing. A new station then serves the next platform, so a second
    /// track beside it joins the same station.
    /// Decision 128: who a new station reaches, said when it opens, where
    /// the land sets ridership: " Within 800 m: …" (decision 108's count),
    /// or that no one lives or works there yet. Empty elsewhere.
    func openingReach(of station: Station, in world: GameWorld) -> String {
        guard !world.land.isEmpty else { return "" }
        let totals = world.land.totals(within: Land.catchmentRadius, of: station.location)
        guard totals.residents + totals.jobs > 0 else {
            return language.text(
                " No one lives or works within 800 m yet: it will see few passengers.",
                "800 公尺內還沒有人住或工作，搭車的人會很少。"
            )
        }
        return language.text(" ", "") + catchmentText(totals) + language.text(
            ". Serve it well and the town round it grows.",
            "。服務好，附近的城市就會長大。"
        )
    }

    public func addNetworkPlatform() {
        guard let stretch = networkPlatformStretch, let geometry = world.trackGeometry(of: stretch.edge) else {
            message = StatusMessage(kind: .failure, text: language.text("Tap the track where the platform goes.", "請點選要設置月台的軌道。"))
            return
        }
        let middle = geometry.location(at: (stretch.start + stretch.end) / 2).position.plan
        let chosen = platformStationID.flatMap { world.station(id: $0) }
        let name = stationName
        let demand = newStationDemand(at: middle)
        var built: StationID?
        let added = perform { world throws(GameError) in
            var draft = world
            let station: Station
            if let chosen {
                station = chosen
            } else {
                station = try draft.buildStation(named: name, at: middle)
                // With demand from land (Phase 6b) GameCore gives it the
                // ridership of the land round it.
                if draft.accounts.mode == .management, !draft.landDemand {
                    try draft.setStationDemand(station.id, to: demand)
                }
            }
            try draft.addTrackPlatform(station.id, on: stretch.edge, from: stretch.start, to: stretch.end)
            world = draft
            built = chosen == nil ? station.id : nil
            let length = NetworkBuilding.lengthText(stretch.end - stretch.start, in: language)
            return chosen == nil
                ? language.text(
                    "Built station “\(station.name)” with a \(length) platform on \(stretch.edge.displayText(in: language).lowercased()).",
                    "已建造車站「\(station.name)」，月台 \(length)，位於\(stretch.edge.displayText(in: language))。"
                ) + openingReach(of: station, in: draft)
                : language.text(
                    "Added a \(length) platform to \(station.name) on \(stretch.edge.displayText(in: language).lowercased()).",
                    "已在\(stretch.edge.displayText(in: language))為 \(station.name) 加上 \(length) 的月台。"
                )
        }
        if added {
            notePutUp(at: middle)
        }
        if let built {
            // The typed name went to the new station: suggest the next.
            let suggestion = Self.suggestedStationName(for: world, at: middle, in: language, railways: railways)
            stationName = suggestion
            automaticStationName = suggestion
            platformStationID = built
        }
    }

    /// Removes `platform` through
    /// `GameWorld.removeTrackPlatform(_:on:from:)`.
    public func removeNetworkPlatform(_ platform: TrackPlatform) {
        perform { world throws(GameError) in
            try world.removeTrackPlatform(platform.station, on: platform.edge, from: platform.start)
            let name = world.station(id: platform.station)?.name ?? "#\(platform.station.rawValue)"
            return language.text("Removed a platform of \(name).", "已拆除 \(name) 的一座月台。")
        }
    }

    /// How far from a new platform's middle a station may stand to be the
    /// one it belongs to by default: 2048 units, 32 m (Stage C1).
    public static let platformStationReach: Int64 = 2_048

    /// The station nearest the place `point` on the network, by where it
    /// stands (``Station/location``), if one lies within
    /// ``platformStationReach``; the lowest ID of equally near ones.
    private func nearestStation(to point: NetworkEdgePoint) -> StationID? {
        guard let position = world.trackGeometry(of: point.edge)?.location(at: point.distance).position else { return nil }
        let reach = Self.platformStationReach
        var best: (id: StationID, distance: Int64)?
        for station in world.stations {
            let centre = station.location
            let dx = centre.x - position.x, dy = centre.y - position.y
            let squared = dx * dx + dy * dy
            guard squared <= reach * reach, best == nil || squared < best!.distance else { continue }
            best = (station.id, squared)
        }
        return best?.id
    }

    // MARK: - Trains

    /// Puts `train` on a platform of `station` on the track network: the
    /// first, along the track, as long as the train, or else the longest;
    /// if GameCore refuses it there (another train holds that track), the
    /// next one in that order.
    /// It faces the way along the platform nearer ``placementHeading`` and
    /// stands with its head at the platform's far end, through
    /// `GameWorld.placeTrain(_:at:)` and, to stand there rather than run on
    /// to the end of the edge, `GameWorld.setTrainContinuation(_:along:stoppingAt:)`
    /// with no traversals. All or nothing; GameCore decides whether the
    /// track behind the platform takes the rest of the train.
    func place(_ train: Train, atPlatformOf station: Station) {
        let platforms = world.trackPlatforms(of: station.id)
        // Those as long as the train in track order, then the rest, longest
        // first.
        let ordered = platforms.filter { $0.length >= train.length }
            + platforms.filter { $0.length < train.length }.sorted { $0.length > $1.length }
        guard !ordered.isEmpty else { return }
        let heading = placementHeading
        perform { world throws(GameError) in
            var refusal: GameError?
            for platform in ordered {
                guard let edge = world.network.edge(platform.edge),
                      let geometry = world.trackGeometry(of: platform.edge) else { continue }
                let way = geometry.location(at: (platform.start + platform.end) / 2).direction
                let forward: Bool
                switch heading {
                case .north: forward = way.dy <= 0
                case .east: forward = way.dx >= 0
                case .south: forward = way.dy >= 0
                case .west: forward = way.dx <= 0
                }
                let traversal = TrackTraversal(edge: platform.edge, direction: forward ? .forward : .backward)
                // The offset is measured the way the train faces.
                let offset = forward ? platform.end : edge.length - platform.start
                var draft = world
                do throws(GameError) {
                    try draft.placeTrain(train.id, at: .onEdge(traversal, offset: offset))
                    if offset < edge.length {
                        try draft.setTrainContinuation(train.id, along: [], stoppingAt: offset)
                    }
                    try draft.useTrainPerformanceForMovement(train.id)
                } catch {
                    refusal = refusal ?? error
                    continue
                }
                world = draft
                return language.text(
                    "Placed \(train.name) at \(station.name), on \(platform.edge.displayText(in: language).lowercased()) going \(forward ? "forward" : "backward").",
                    "已將 \(train.name) 放在 \(station.name)，位於\(platform.edge.displayText(in: language))\(forward ? "正向" : "反向")。"
                )
            }
            throw refusal ?? .unknownStation(station.id)
        }
    }

    // MARK: - Removing

    /// Removes the edge picked in remove mode through
    /// `GameWorld.removeTrackEdge(_:)`, and then each of its end nodes no
    /// other edge ends at through `GameWorld.removeTrackNode(_:)`, all or
    /// nothing.
    public func removeNetworkEdge() {
        guard let id = networkEdgePoint?.edge, let edge = world.network.edge(id) else {
            message = StatusMessage(kind: .failure, text: language.text("Tap the track to remove.", "請點選要拆除的軌道。"))
            return
        }
        let removed = perform { world throws(GameError) in
            var draft = world
            try draft.removeTrackEdge(id)
            for node in Set([edge.from, edge.to]).sorted() where draft.network.node(node)?.ends.isEmpty == true {
                try draft.removeTrackNode(node)
            }
            world = draft
            return language.text("Removed \(id.displayText(in: language).lowercased()).", "已拆除\(id.displayText(in: language))。")
        }
        if removed {
            networkEdgePoint = nil
        }
    }
}

/// Why the network tool will not ask GameCore to build the picked stretch:
/// the reference's own build checks, before any game rule.
enum NetworkProblem: Error {
    /// A node the stretch starts or ends at is gone.
    case missingNode
    /// A new node within ``NetworkBuilding/minimumSpacing`` of the other end.
    case tooClose
    /// A turn of more than 90° from the track joined to the other end.
    case tooSharp

    func text(in language: DisplayLanguage) -> String {
        switch self {
        case .missingNode:
            language.text("That node is gone. Tap the track again.", "那個節點已經不在了。請重新點選軌道。")
        case .tooClose:
            language.text(
                "That point is too close to the other end: keep at least 22 m between them.",
                "該位置與另一端太近：兩者至少要相距 22 公尺。"
            )
        case .tooSharp:
            language.text(
                "That turns too sharply: from the track it continues, new track may turn at most 90° toward the other end.",
                "小於最小轉彎半徑：從相接的軌道朝另一端，新的軌道最多只能轉 90 度。"
            )
        }
    }
}

/// One stretch of track the network tool would build, worked out from the
/// world and the tool's settings.
struct EdgePlan {
    let start: NetworkAnchor
    let end: NetworkAnchor
    let from: WorldCoordinate
    let to: WorldCoordinate
    let curve: TrackCurve
    let profile: TrackProfile
    /// `nil` when the ends and curve make no edge; GameCore then refuses.
    let geometry: TrackGeometry?
    let joinsStart: Bool
    let joinsEnd: Bool

    var length: Int64 { geometry?.length ?? 0 }

    /// Builds it in `world`: a node for each new end, then the edge.
    func build(in world: inout GameWorld, structure: TrackStructure) throws(GameError) -> (edge: TrackEdgeID, to: TrackNodeID) {
        let first = try node(for: start, at: from, in: &world)
        let last = try node(for: end, at: to, in: &world)
        let edge = try world.buildTrackEdge(from: first, to: last, curve: curve, profile: profile, structure: structure)
        return (edge, last)
    }

    private func node(for anchor: NetworkAnchor, at position: WorldCoordinate, in world: inout GameWorld) throws(GameError) -> TrackNodeID {
        switch anchor {
        case .node(let id): return id
        case .point: return try world.buildTrackNode(at: position)
        case .track(let point):
            // The other end may have split the same edge: find the place
            // again where it lies now.
            let now = world.network.edge(point.edge) != nil ? point : world.trackEdgePoint(near: position.plan, within: 16)
            guard let now else { throw .unknownTrackEdge(point.edge) }
            return try world.splitTrackEdge(now.edge, at: now.distance)
        }
    }
}

extension NetworkBuilding {
    /// A length or height in world units as metres, such as "75 m" (64
    /// units to a metre, rounded to the nearest).
    public static func lengthText(_ units: Int64, in language: DisplayLanguage) -> String {
        let unitsPerMetre = WorldCoordinate.unitsPerMetre
        let metres = (units + (units >= 0 ? 1 : -1) * unitsPerMetre / 2) / unitsPerMetre
        return language.text("\(metres) m", "\(metres) 公尺")
    }
}

extension TrackStructure {
    /// What carries the track, for the network tool and the edge summary.
    public func name(in language: DisplayLanguage) -> String {
        switch self {
        case .surface: language.text("Surface", "地面")
        case .elevated: language.text("Elevated", "高架")
        case .bridge: language.text("Bridge", "橋樑")
        case .tunnel: language.text("Tunnel", "隧道")
        }
    }
}

// MARK: - Text

extension GameSession {
    /// What the network tool has picked so far and what to tap next.
    public func networkDraftText() -> String {
        switch networkMode {
        case .build:
            guard let start = networkStart else {
                return language.text(
                    "Tap where the track starts: a node, the track for a turnout there, or anywhere for a new node.",
                    "請點軌道的起點：既有的節點、軌道上（在那裡設轉轍器），或任何地方建立新節點。"
                )
            }
            guard let end = networkEnd else {
                return language.text(
                    "From \(start.text(in: language)). Tap where it ends, or drag there from the start.",
                    "從\(start.text(in: language))開始。請點終點，或從起點拖曳過去。"
                )
            }
            // Two new nodes say nothing an arrow between them would add.
            let ends: String
            if case .point = start, case .point = end {
                ends = language.text("A new stretch of track", "一段新的軌道")
            } else {
                ends = "\(start.text(in: language)) → \(end.text(in: language))"
            }
            guard let real = realTrackSectionText(from: start, to: end) else { return ends }
            return "\(ends) · \(real)"
        case .platform:
            guard let stretch = networkPlatformStretch else {
                return language.text("Tap the track where the platform goes.", "請點選要設置月台的軌道。")
            }
            let length = NetworkBuilding.lengthText(stretch.end - stretch.start, in: language)
            return language.text(
                "\(length) platform on \(stretch.edge.displayText(in: language).lowercased()), \(stretch.start)–\(stretch.end) units along",
                "\(stretch.edge.displayText(in: language)) 上 \(length) 的月台，距起點 \(stretch.start)–\(stretch.end) 單位"
            )
        case .remove:
            guard let edge = networkEdgePoint?.edge else {
                return language.text("Tap the track to remove.", "請點選要拆除的軌道。")
            }
            return world.trackEdgeSummary(edge, in: language) ?? edge.displayText(in: language)
        }
    }
}

extension NetworkAnchor {
    /// "Node #3", or "a new node".
    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .node(let id): id.displayText(in: language)
        case .point: language.text("a new node", "新節點")
        case .track(let point): language.text("a turnout on \(point.edge.displayText(in: language).lowercased())", "\(point.edge.displayText(in: language)) 上的新轉轍器")
        }
    }
}

extension NetworkPreview {
    /// What the stretch is: "75 m · 0 m → 8 m · continues the track ·
    /// $ 1,500"; the cost is left out when GameCore refuses it.
    public func text(in language: DisplayLanguage) -> String {
        var parts = [NetworkBuilding.lengthText(length, in: language)]
        if startHeight != endHeight {
            parts.append("\(NetworkBuilding.lengthText(startHeight, in: language)) → \(NetworkBuilding.lengthText(endHeight, in: language))")
        }
        switch (joinsStart, joinsEnd) {
        case (true, true): parts.append(language.text("joins the track at both ends", "兩端都與軌道相接"))
        case (true, false): parts.append(language.text("continues the track", "延續既有軌道"))
        case (false, true): parts.append(language.text("joins the track at its end", "終點與軌道相接"))
        case (false, false): break
        }
        if let cost {
            parts.append(cost.moneyText)
        }
        return parts.joined(separator: " · ")
    }
}

extension GameWorld {
    /// What edge `id` of the track network is: "Edge #3 · 75 m · Elevated
    /// · 8 m" when level, "Edge #3 · 300 m · Surface · 0 m → 8 m, 27‰ at
    /// its steepest" when not, then its platforms' stations, if any.
    /// `nil` for an edge the network does not have.
    public func trackEdgeSummary(_ id: TrackEdgeID, in language: DisplayLanguage) -> String? {
        guard let edge = network.edge(id), let geometry = trackGeometry(of: id) else { return nil }
        var parts = [id.displayText(in: language), NetworkBuilding.lengthText(edge.length, in: language), edge.structure.name(in: language)]
        let start = NetworkBuilding.lengthText(geometry.startHeight, in: language)
        if geometry.startHeight == geometry.endHeight {
            parts.append(start)
        } else {
            let grade = geometry.steepestGrade
            let perMille = (abs(grade.rise) * 1_000 + grade.run / 2) / grade.run
            let end = NetworkBuilding.lengthText(geometry.endHeight, in: language)
            parts.append(language.text("\(start) → \(end), \(perMille)‰ at its steepest", "\(start) → \(end)，最陡 \(perMille)‰"))
        }
        let names = network.platforms(on: id).map { station(id: $0.station)?.name ?? "#\($0.station.rawValue)" }
        if !names.isEmpty {
            parts.append(language.text("platforms: \(names.joined(separator: ", "))", "月台：\(names.joined(separator: "、"))"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - The map

/// What the map draws over the track network for the network tool (Stage
/// C1), in world coordinates: the picked ends, the stretch they would make,
/// and the edge or platform stretch picked on the track. Derived from the
/// session each time the map is drawn, never kept.
public struct NetworkOverlay: Hashable, Sendable {
    public enum Highlight: Hashable, Sendable {
        /// The edge the remove mode would remove.
        case removal
        /// The stretch the next platform would take.
        case platform
    }

    /// The start, then the end, of the next stretch.
    public var anchors: [WorldCoordinate] = []
    /// The centre line of the next stretch.
    public var preview: [WorldCoordinate] = []
    /// The mirrored diagonal of an X crossover (see
    /// ``GameSession/networkBuildsScissors``), drawn like ``preview``.
    public var crossing: [WorldCoordinate] = []
    /// Whether GameCore would build it.
    public var previewIsBuildable = false
    /// The centre line of what the platform or remove mode picked.
    public var highlight: [WorldCoordinate] = []
    public var highlightKind: Highlight = .removal
    /// The company's buildings the next stretch would pull down (decision
    /// 95).
    public var cleared: [PlanRect] = []

    public init() {}
}

extension GameSession {
    /// What the map draws for the network tool; `nil` with another tool.
    public var networkOverlay: NetworkOverlay? {
        guard tool == .network else { return nil }
        var overlay = NetworkOverlay()
        switch networkMode {
        case .build:
            overlay.anchors = [networkStart, networkEnd].compactMap { $0.flatMap { world.position(of: $0, height: networkHeight) } }
            if let draft = networkDraftPreview {
                overlay.preview = draft.preview.points
                overlay.crossing = draft.crossing
                overlay.previewIsBuildable = draft.preview.problem == nil
                overlay.cleared = draft.preview.cleared.map(PlanRect.init)
            }
        case .platform:
            if let stretch = networkPlatformStretch, let geometry = world.trackGeometry(of: stretch.edge), stretch.start < stretch.end {
                overlay.highlight = geometry.points(from: stretch.start, to: stretch.end)
                overlay.highlightKind = .platform
            }
        case .remove:
            if let edge = networkEdgePoint?.edge, let geometry = world.trackGeometry(of: edge) {
                overlay.highlight = geometry.points
            }
        }
        return overlay
    }

    /// How high new nodes go: "New nodes on the ground", or "New nodes
    /// 8 m above the ground".
    public func networkHeightText() -> String {
        let height = NetworkBuilding.lengthText(abs(networkHeight), in: language)
        if networkHeight > 0 {
            return language.text("New nodes \(height) above the ground", "新節點：地面以上 \(height)")
        } else if networkHeight < 0 {
            return language.text("New nodes \(height) below the ground", "新節點：地面以下 \(height)")
        }
        return language.text("New nodes on the ground", "新節點：地面")
    }

    /// How long the next platform is: "Platform for 4 cars · 64 m".
    public func platformLengthText() -> String {
        let length = NetworkBuilding.lengthText(Int64(platformCars) * Train.carLength, in: language)
        return language.text(
            "Platform for \(Train.carsText(platformCars, in: language)) · \(length)",
            "月台長 \(Train.carsText(platformCars, in: language)) · \(length)"
        )
    }

    /// The platforms on the edge the platform mode picked, to remove.
    public var platformsOnPickedEdge: [TrackPlatform] {
        guard networkMode == .platform, let edge = networkEdgePoint?.edge else { return [] }
        return world.network.platforms(on: edge)
    }

    /// "Station 1, 952–5048 units along" for one of
    /// ``platformsOnPickedEdge``.
    public func platformText(_ platform: TrackPlatform) -> String {
        let name = world.station(id: platform.station)?.name ?? "#\(platform.station.rawValue)"
        return language.text("\(name), \(platform.start)–\(platform.end) units along", "\(name)，距起點 \(platform.start)–\(platform.end) 單位")
    }
}

extension MapScale {
    /// The world point under a point in map coordinates (see
    /// ``center(of:referenceSize:)-(WorldCoordinate,_)``), rounded to whole
    /// units.
    public static func worldPoint(atX x: Double, y: Double, referenceSize: Double) -> PlanPoint {
        precondition(referenceSize > 0, "worldPoint(atX:y:referenceSize:) requires a positive size")
        let scale = Double(referenceLength) / referenceSize
        return PlanPoint(x: Int64((x * scale).rounded()), y: Int64((y * scale).rounded()))
    }

    /// `points` of the screen in world units at `referenceSize`, rounded.
    public static func worldDistance(_ points: Double, referenceSize: Double) -> Int64 {
        precondition(referenceSize > 0, "worldDistance(_:referenceSize:) requires a positive size")
        return Int64((points * Double(referenceLength) / referenceSize).rounded())
    }
}

/// The track preview of the picked ends, and what it was worked out for:
/// the draft (the ends and the network tool's options) and the world's
/// revision (``GameSession/networkDraftPreview``).
struct NetworkPreviewMemo {
    struct Key: Equatable {
        let start: NetworkAnchor
        let end: NetworkAnchor
        let structure: TrackStructure
        let height: Int64
        let followsTrack: Bool
        let buildsScissors: Bool
        let easesGrade: Bool
        let worldRevision: Int
    }

    let key: Key
    let preview: (preview: NetworkPreview, crossing: [WorldCoordinate])?
}
