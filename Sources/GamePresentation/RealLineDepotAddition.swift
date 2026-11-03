import GameCore

// Decision 557: a real depot added to a line bought before it came with
// one. The Ankeng LRT has been bought with its real depot past Shuangcheng
// since decision 535 (continued), the Green Mountain Line with the Danhai
// depot since decision 489 and the Wenhu Line with its two since decision
// 535; a game saved with the line bought before then has none, and its
// trains stand overnight at stations, where they can stand in the way. A
// save is never changed when it is read (the author, 2026-11-03: 「那就照
// 你的」, the button rather than adding it unasked): the line's panel offers
// the depot, priced and laid as the purchase lays it
// (``RealLineDepotLayout/lay(_:beyond:first:length:ground:water:in:)``),
// and the player decides.
//
// Only a depot past the line's end is offered: its lead goes on from the
// end of the line's track there, which the line bought without it left
// running straight on past the station, so a curve takes it from there
// round into the real yard's way, where the purchase's own run-on turns
// (``RealLineLaying/offer(for:raising:depot:)``'s `runOn`). The Sanxia
// depot, off the line between its ends, would split the line's track for
// its wye and crossovers; it is not offered (the decision's next step).

/// A depot past a line's end added to the line (decision 557): the track
/// from the end of the line's track there, the yard, the depot and its
/// platforms, all built with ``GameWorld``'s commands
/// (``GameSession/build(_:in:)``).
public struct RealLineDepotAddition: Hashable, Sendable, Codable {
    /// The line it is added to.
    public let line: LineID
    /// The real line's name in the app's data (`ntalrt:K`).
    public let realLine: String
    /// The node at the end of the line's track the lead goes on from.
    let anchor: Int
    /// The map tiles under it not owned yet, bought first; `nil` for none.
    let tiles: [MapTile]?
    /// The track: piece `k` here is piece `k + 1` of the nodes the pieces
    /// name (``RealLineAcquisition/NodeAt``), piece 0 being `anchor`.
    let pieces: [RealLineAcquisition.Piece]
    public let depot: RealLineAcquisition.Depot
}

/// What the line panel's "add the depot" card shows (decision 557).
public struct RealLineDepotOffer: Sendable {
    public let line: LineID
    /// The depot's name.
    public let name: String
    /// The end station it stands past.
    public let beyond: String
    public let sidings: Int
    /// What adding it takes, or `nil` with ``problem`` saying why it
    /// cannot be added.
    public let addition: RealLineDepotAddition?
    /// The land bought with it and the building.
    public let land: Money?
    public let building: Money?
    /// The company's buildings in its way, which come down with it.
    public let demolished: [String]
    public let problem: String?

    /// The whole price.
    public var price: Money? {
        guard let land, let building else { return nil }
        return land + building
    }

    /// The button on the line's panel.
    public func buttonTitle(in language: DisplayLanguage) -> String {
        language.text("Add \(name)", "加建\(name)")
    }

    /// The card's text: where it stands, what it holds, what it costs and
    /// what comes down; or why it cannot be added.
    public func summaryText(in language: DisplayLanguage) -> String {
        if let problem { return problem }
        let cost = price?.moneyText ?? ""
        var text = language.text(
            "\(name), past \(beyond) where the real one stands: \(sidings) sidings, for \(cost). The line's trains then go back to it at night.",
            "\(name)建在\(beyond)過去、真實機廠的位置：\(sidings) 股停車線，\(cost)。加建後這條線的列車晚上回機廠過夜。"
        )
        if !demolished.isEmpty {
            let names = demolished.joined(separator: language.text(", ", "、"))
            text += language.text(" Comes down: \(names).", "要拆：\(names)。")
        }
        return text
    }

    /// Why the company cannot pay for it now, or `nil`.
    public func shortfallText(balance: Money, in language: DisplayLanguage) -> String? {
        guard let price, balance < price else { return nil }
        return language.text(
            "Not enough money: it costs \(price.moneyText).",
            "資金不足：需要 \(price.moneyText)。"
        )
    }
}

extension GameSession {
    /// The real depots line `id` could have and has not (decision 557):
    /// a line bought before its real depot came with it. Each is offered
    /// with ``realDepotOffer(for:site:)``; an empty list off a real-world
    /// map or before the real railways are read in (where it could only
    /// be refused), for a line not bought or with its depots.
    public func missingRealDepots(of id: LineID) -> [String] {
        missingRealDepotSites(of: id).map { $0.name(in: language) }
    }

    func missingRealDepotSites(of id: LineID) -> [RealLineDepotSite] {
        guard railways != nil, let frame = RealWorldFrame(world: world), let line = world.line(id: id),
              let bought = world.acquisitions.first(where: { $0.line == id }) else { return [] }
        return RealLineDepotSite.sites(of: bought.realLine).filter { site in
            guard site.beyond != nil else { return false }
            // Its depot by name, in either language, or a depot of the
            // line's standing in the real yard.
            let yard = WorldVector(frame.worldPosition(latitude: site.yard.start.latitude, longitude: site.yard.start.longitude))
            return !line.depots.contains { depot in
                guard let station = world.station(id: depot) else { return false }
                if station.name == site.english || station.name == site.chinese { return true }
                return (WorldVector(station.location) - yard).length < RealLineDepotAddition.sameYard
            }
        }
    }

    /// The selected line's first missing real depot, laid out and priced
    /// (decision 557); `nil` for none.
    public var selectedLineRealDepotOffer: RealLineDepotOffer? {
        guard let line = selectedLine, let name = missingRealDepots(of: line.id).first else { return nil }
        return realDepotOffer(for: line.id, site: name)
    }

    /// Real depot `name` (``missingRealDepots(of:)``) laid out for line
    /// `id` on a copy of the world and priced: what it takes or why it
    /// cannot be added here.
    public func realDepotOffer(for id: LineID, site name: String) -> RealLineDepotOffer {
        let sites = missingRealDepotSites(of: id)
        let site = sites.first { $0.name(in: language) == name } ?? sites[0]
        return RealLineDepotAddition.offer(site: site, line: id, laying: realLineLaying)
    }

    /// Adds the depot of `offer` (decision 557), paying for it: its track,
    /// the depot and its sidings, made one of the line's depots. `false`,
    /// with the message saying why, where it cannot be.
    @discardableResult
    public func addRealDepot(_ offer: RealLineDepotOffer) -> Bool {
        guard let addition = offer.addition else {
            message = StatusMessage(kind: .failure, text: offer.problem ?? "")
            return false
        }
        let name = offer.name
        return perform(.addRealLineDepot(addition)) { _, _, _ in
            language.text(
                "Built \(name): the line's trains go back to it at night from now on.",
                "已加建\(name)：這條線的列車從現在起晚上回機廠過夜。"
            )
        } != nil
    }

    func build(_ addition: RealLineDepotAddition, in world: inout GameWorld) throws(GameError) {
        try realLineLaying.build(addition, in: &world)
    }
}

extension RealLineDepotAddition {
    /// How near the real yard a depot of the line's stands to count as it.
    static let sameYard = 400 * RealLineAcquisition.metre
    /// How far past the end station the line's track may end for the lead
    /// to go on from it: the purchase's run-on and some.
    static let endReach = RealLineAcquisition.runOn + RealLineAcquisition.stationReach

    /// Depot `site` laid out for line `id` on the world `laying` reads,
    /// and priced on a funded copy.
    static func offer(site: RealLineDepotSite, line id: LineID, laying: RealLineLaying) -> RealLineDepotOffer {
        let language = laying.language, world = laying.world
        let name = site.name(in: language)
        let urban = RealBranchLine.urbanLines.first { "\(RealBranchLine.dataSystem(of: $0.system)):\($0.network)" == site.line }
        func refused(_ english: String, _ chinese: String, beyond: String = "") -> RealLineDepotOffer {
            RealLineDepotOffer(
                line: id, name: name, beyond: beyond, sidings: site.sidings, addition: nil, land: nil, building: nil, demolished: [],
                problem: language.text(english, chinese)
            )
        }
        guard let line = world.line(id: id), let beyondName = site.beyond, let urban, let railways = laying.railways,
              let frame = RealWorldFrame(world: world),
              let real = RealLineLaying.realPoint(of: beyondName, system: urban.system, railways: railways, frame: frame) else {
            return refused("This line's depot cannot be added on this map.", "這張地圖上不能幫這條線加建機廠。")
        }
        // The line's end station there: its stop nearest the real one.
        let ends = [line.stops.first, line.stops.last].compactMap(\.self).compactMap(world.station(id:))
        guard let end = ends.min(by: { (WorldVector($0.location) - real).length < (WorldVector($1.location) - real).length }),
              (WorldVector(end.location) - real).length < RealLineAcquisition.stationReach else {
            return refused("This line's depot cannot be added on this map.", "這張地圖上不能幫這條線加建機廠。")
        }
        let beyond = end.name
        let points = [site.junction, site.yard.start, site.yard.end].map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) }

        // The end of the line's track past the station: a node only one
        // edge reaches, within the purchase's run-on of the station, the
        // furthest out along the way from the line's previous stop.
        let next = line.stops.count > 1 ? world.station(id: end.id == line.stops.first ? line.stops[1] : line.stops[line.stops.count - 2]) : nil
        let outward = next.map { (WorldVector(end.location) - WorldVector($0.location)).unit } ?? (points[0] - WorldVector(end.location)).unit
        var reached: [TrackNodeID: [TrackEdge]] = [:]
        for edge in world.network.edges {
            reached[edge.from, default: []].append(edge)
            reached[edge.to, default: []].append(edge)
        }
        let deadEnds = world.network.nodes.filter { node in
            reached[node.id]?.count == 1 && (WorldVector(node.position.plan) - WorldVector(end.location)).length <= endReach
        }
        guard let anchorNode = deadEnds.max(by: { a, b in
            (WorldVector(a.position.plan) - WorldVector(end.location)).dot(outward) < (WorldVector(b.position.plan) - WorldVector(end.location)).dot(outward)
        }), case .node(let anchor) = anchorNode.id, let anchorEdge = reached[anchorNode.id]?.first,
              let geometry = world.trackGeometry(of: anchorEdge.id), geometry.points.count >= 2 else {
            return refused(
                "The line's track past \(beyond) no longer ends there, so the depot's track has nowhere to start.",
                "\(beyond)過去的軌道已經接了別的軌道，機廠的入出庫線沒有地方接。",
                beyond: beyond
            )
        }
        let start = WorldVector(anchorNode.position.plan)
        let way: WorldVector = {
            let p = geometry.points
            let (a, b) = anchorEdge.to == anchorNode.id ? (p[p.count - 2], p[p.count - 1]) : (p[1], p[0])
            return (WorldVector(b.plan) - WorldVector(a.plan)).unit
        }()

        // As the purchase's run-on: into the yard's way 50 m short of its
        // sidings' near ends, so the ladder stays within the real depot.
        let yardWay = (points[2] - points[1]).unit
        let into = points[1] - yardWay * (50 * RealLineAcquisition.metre)
        guard (into - start).dot(way) > RealWorldDemo.shortestEdge else {
            return refused(
                "The line's track runs on past where the depot's track would leave it, so the depot does not fit.",
                "這條線的軌道已經鋪過機廠入出庫線該接的地方，機廠放不下。",
                beyond: beyond
            )
        }

        // The ground under it, read in on a copy, as the purchase reads it.
        let length = Int64(urban.network == "BR" ? 4 + 1 : DemoRealLines.cars(ofSystem: urban.system) + 1) * Train.carLength
        var draft = world.pricingCopy()
        let step = 32 * RealLineAcquisition.metre, side = 16 * RealLineAcquisition.metre
        let lead = WorldPath([start, into] + Array(points.dropFirst()))
        let samples = (0...Int(lead.length / step)).flatMap { index -> [PlanPoint] in
            let point = lead.point(at: Double(index) * step)
            return [(-side, -side), (-side, side), (side, -side), (side, side)].map { dx, dy in WorldVector(x: point.x + dx, y: point.y + dy).plan }
        }
        let yardSamples = RealLineDepotLayout.groundSamples(beyond: points, site: site, length: length, back: 50 * RealLineAcquisition.metre, step: step)
        var tiles: [MapTile] = []
        if let expansion = world.mapExpansion {
            let wanted = Set(samples.map { MapExpansion.tile(at: $0) }).filter { world.isOnMap($0) && !expansion.owns($0) }
            guard let order = RealLineAcquisition.buyingOrder(of: wanted, owned: expansion.owned) else {
                return refused(
                    "The depot's land does not touch yours. Use Expand Map to buy up to it first.",
                    "機廠的地和你的地不相連。先用「擴建地圖」買到機廠旁邊。",
                    beyond: beyond
                )
            }
            tiles = order
            for tile in tiles {
                try? draft.buyMapTile(tile, passingMilestone: true)
            }
        }
        try? draft.readGround(under: samples + yardSamples, from: laying.heights)
        let mapped = draft.ground.isMapped
        let planning = draft
        func ground(_ point: WorldVector) -> Double { Double(planning.groundHeight(at: point.plan) ?? 0) }
        func water(_ point: WorldVector) -> Bool {
            guard mapped else { return false }
            let plan = point.plan
            return planning.terrain.isWater(row: Int(plan.y / Land.cellLength), column: Int(plan.x / Land.cellLength))
        }

        // The curve round into the yard's way, its far end within the
        // lead's grade of the line's end, as near the ground as that lets
        // it; then the yard, as the purchase lays it.
        let chord = (into - start).length
        let climb = RealLineDepotLayout.grade * chord
        let height = Int64(max(Double(anchorNode.position.z) - climb, min(Double(anchorNode.position.z) + climb, ground(into))).rounded())
        let handle = 0.4 * chord
        let curve = TrackCurve.cubic((start + way * handle).plan, (into - yardWay * handle).plan)
        let leadEnds = [anchorNode.position, WorldCoordinate(x: into.plan.x, y: into.plan.y, z: height)]
        let surveyed = TrackGeometry(from: leadEnds[0], to: leadEnds[1], curve: curve).map(NetworkBuilding.surveyedPoints(of:)) ?? []
        let connector = RealLineAcquisition.Piece(
            nodes: leadEnds, start: RealLineAcquisition.NodeAt(piece: 0, node: 0), end: nil, curves: [curve], distances: [0, chord],
            structure: .automatic, together: true, ground: [leadEnds[0].plan, leadEnds[1].plan] + surveyed
        )
        guard let laid = RealLineDepotLayout.lay(
            site, beyond: (RealLineAcquisition.NodeAt(piece: 1, node: 1), into, height, yardWay), first: 2, length: length,
            ground: ground, water: water, in: language
        ) else {
            return refused("The depot's track cannot get down to the yard here.", "機廠的入出庫線在這裡接不到停車場。", beyond: beyond)
        }

        // GameCore's answer and the price, on a funded copy. A tile the
        // track reaches between the samples is bought with the others.
        while true {
            let addition = RealLineDepotAddition(
                line: id, realLine: site.line, anchor: anchor, tiles: tiles.isEmpty ? nil : tiles, pieces: [connector] + laid.pieces, depot: laid.depot
            )
            var probe = world.pricingCopy()
            let opening = probe.economy.balance
            let standing = probe.placedBuildings
            do throws(GameError) {
                if let tiles = addition.tiles {
                    for tile in tiles {
                        try probe.buyMapTile(tile, passingMilestone: true)
                    }
                }
                let landed = probe.economy.balance
                try laying.build(addition, in: &probe, buyingTiles: false)
                let gone = standing.filter { building in !probe.placedBuildings.contains { $0.id == building.id } }
                return RealLineDepotOffer(
                    line: id, name: name, beyond: beyond, sidings: site.sidings, addition: addition, land: opening - landed,
                    building: landed - probe.economy.balance, demolished: gone.map { $0.kind.title(in: language) }, problem: nil
                )
            } catch {
                if case .mapTileNotOwned(let tile) = error, let owned = world.mapExpansion?.owned, !tiles.contains(tile),
                   let order = RealLineAcquisition.buyingOrder(of: Set(tiles + [tile]), owned: owned) {
                    tiles = order
                    continue
                }
                return RealLineDepotOffer(
                    line: id, name: name, beyond: beyond, sidings: site.sidings, addition: nil, land: nil, building: nil, demolished: [],
                    problem: language.text("\(name) cannot be added: ", "\(name)加建不了：") + error.playerMessage(in: language)
                )
            }
        }
    }
}

extension RealLineLaying {
    /// Builds `addition` in `world` (decision 557): the tiles under it
    /// (with `buyingTiles`), its track from the end of the line's, the
    /// depot and a platform along each siding, made one of the line's
    /// depots; all of it or, throwing, none, the caller's copy dropped.
    /// From then on the line sends its trains to it when it no longer
    /// needs them and out of it for their runs (decision 221), as it does
    /// a depot it was bought with.
    func build(_ addition: RealLineDepotAddition, in world: inout GameWorld, buyingTiles: Bool = true) throws(GameError) {
        try world.editTrackAsOne { (world: inout GameWorld) throws(GameError) in
            guard let line = world.line(id: addition.line) else { throw .unknownLine(addition.line) }
            if buyingTiles, let tiles = addition.tiles {
                for tile in tiles {
                    try world.buyMapTile(tile, passingMilestone: true)
                }
                GameSession.readLand(roundStationsOf: &world, population: population, places: places, water: water, coverage: coverage)
            }
            let anchor = TrackNodeID.node(addition.anchor)
            guard world.network.node(anchor) != nil else { throw .unknownTrackNode(anchor) }
            var nodes: [[TrackNodeID]] = [[anchor]]
            var edges: [[TrackEdgeID]] = [[]]
            for piece in addition.pieces {
                try world.readGround(under: piece.ground, from: heights)
                var ids: [TrackNodeID] = []
                for (index, position) in piece.nodes.enumerated() {
                    if index == 0, let start = piece.start {
                        guard nodes.indices.contains(start.piece), nodes[start.piece].indices.contains(start.node) else { throw .invalidTrackGeometry }
                        ids.append(nodes[start.piece][start.node])
                    } else if index == piece.nodes.count - 1, let end = piece.end {
                        guard nodes.indices.contains(end.piece), nodes[end.piece].indices.contains(end.node) else { throw .invalidTrackGeometry }
                        ids.append(nodes[end.piece][end.node])
                    } else {
                        ids.append(try world.buildTrackNode(at: position))
                    }
                }
                edges.append(try world.buildTrackEdges(piece.curves.enumerated().map { index, curve in
                    TrackEdgePlan(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure)
                }))
                nodes.append(ids)
            }
            // A platform along each siding, as ``build(_:in:recording:)``
            // lays the purchase's.
            let depot = addition.depot
            let station = try world.buildStation(named: depot.name, at: depot.at)
            for at in depot.platforms {
                guard addition.pieces.indices.contains(at.piece - 1), edges.indices.contains(at.piece) else { throw .invalidTrackGeometry }
                let distances = addition.pieces[at.piece - 1].distances, built = edges[at.piece]
                guard !built.isEmpty, distances.count == built.count + 1 else { throw .invalidTrackGeometry }
                let index = max(0, min(built.count - 1, distances.lastIndex { $0 <= at.distance } ?? 0))
                let a = distances[index], b = distances[index + 1]
                let edgeLength = world.network.edge(built[index])?.length ?? 0
                var offset = Int64(((at.distance - a) / max(b - a, 1) * Double(edgeLength)).rounded())
                if offset + depot.length > edgeLength { offset = max(0, edgeLength - depot.length - Int64(RealLineAcquisition.metre)) }
                try world.addTrackPlatform(station.id, on: built[index], from: offset, to: offset + depot.length)
            }
            try world.setStationDepot(station.id, to: true)
            try world.setLineDepots(line.id, to: line.depots + [station.id])
        }
    }
}
