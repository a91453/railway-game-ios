import GameCore

/// Decision 947: the guideways of the three guideway trains (decision
/// 930): the straddle monorail's concrete beam on its piers
/// (``Map3DGuidedMonorail``, `MONORAIL`), the maglev's T-shaped guideway
/// (``Map3DGuidedMaglev``, `MAGLEV`) and the suspended monorail's steel
/// box beam on its portal frames, the cars hanging under it
/// (``Map3DGuidedSkyrail``, `SKYRAIL`), drawn on the track their lines
/// run on in place of its rails, sleepers and ballast.
///
/// Worked out by the presentation from the trains the lines run
/// (``edges(in:)``): GameCore's track has no kind of its own for them,
/// and the saves do not change. Track a line of guideway trains runs on
/// becomes their guideway unless any other line runs on it too (a train
/// of another type, or of another guideway): there it stays ordinary
/// track, and a guideway train on it stands on the rails as before.
///
/// The beams' cross-sections are the local studio's beam samples
/// (`a91453/railway-assets-private-2`, `game-art-previews/docs/art/`
/// `guided-monorail-2026-11/revision-1/guided-monorail-beam.glb`,
/// `guided-maglev-2026-11/revision-3/guided-maglev-beam.glb`,
/// `guided-skyrail-2026-11/revision-2/guided-skyrail-beam.glb`), each in
/// metres across and up from its running surface (the trains' z 0), swept
/// along the track as the rail reference's metro kit sweeps its rubber-
/// tyred guideway (`rail-3d/garage-scenes/metro-kit.js`, `guideway`,
/// `strips`).
enum Map3DGuideway {
    enum Kind: Int, Hashable, Sendable, CaseIterable {
        /// The straddle monorail (`MONORAIL`).
        case straddle
        /// The maglev (`MAGLEV`).
        case maglev
        /// The suspended monorail (`SKYRAIL`).
        case suspended

        /// The guideway of trains of `type`, `nil` for a train that runs
        /// on rails.
        init?(_ type: TrainType?) {
            switch type {
            case TrainType.monorail?: self = .straddle
            case TrainType.maglev?: self = .maglev
            case TrainType.skyRail?: self = .suspended
            default: return nil
            }
        }

        /// How far the running surface stands over the rails' top (the
        /// track's drawn line), metres: the trains are drawn that much
        /// higher (``Map3DGuidedTrains/model(_:in:palette:lift:)``), so a
        /// straddling car's skirts end at the rails' height on ordinary
        /// track and beside its beam on its guideway; the suspended car's
        /// floor is 0.17 m over the rails, its beam over it.
        var runningSurface: Float {
            switch self {
            case .straddle: 1.3
            case .maglev: 0.75
            case .suspended: 4.1
            }
        }

        /// The cars' door sills over the running surface, metres, as the
        /// studio made them (the bottoms of their door frames): the
        /// monorail's from 1.15 (its floor 1.14 m over its beam), the
        /// maglev's from 0.95, the suspended car's from −3.93.
        var doorSill: Float {
            switch self {
            case .straddle: 1.15
            case .maglev: 0.95
            case .suspended: -3.93
            }
        }

        /// How high a platform beside the guideway stands over the rails'
        /// top, metres: level with the doors.
        var platformTop: Float { runningSurface + doorSill }

        /// How far a platform's edge stands from the guideway's middle,
        /// metres: clear of the car's widest part beside it (the maglev's
        /// 3.70 m over the skirts that wrap its guideway), as the 1.6 m of
        /// ordinary track clears the monorail's 3.03 m and the suspended
        /// car's 2.60 m.
        var platformEdge: Float {
            switch self {
            case .straddle, .suspended: 1.6
            case .maglev: 1.9
            }
        }

        /// The beam's main body, drawn at every distance (the far view's
        /// cheap beam): the studio samples' beam parts.
        var body: [Part] {
            switch self {
            // 0.85 m wide, 1.5 m deep.
            case .straddle: [Part(-0.425, 0.425, -1.5, 0, colour: Map3DGuideway.concrete)]
            // The 2.80 m slab the cars' skirts wrap, 0.45 m thick, on its
            // 1.60 m web, 2 m deep in all.
            case .maglev: [Part(-1.4, 1.4, -0.45, 0, colour: Map3DGuideway.concrete),
                           Part(-0.8, 0.8, -2.0, -0.45, colour: Map3DGuideway.concrete)]
            // The box 1.80 m wide, from 0.45 m under the running surface
            // to 1.15 m over it.
            case .suspended: [Part(-0.9, 0.9, -0.45, 1.15, colour: Map3DGuideway.steel)]
            }
        }

        /// What only the near view draws: the samples' dark parts (the
        /// monorail's power rails on its beam's sides, the maglev's
        /// stators under its slab and the strips on its edges, the slot
        /// under the suspended beam).
        var details: [Part] {
            switch self {
            case .straddle: [-1, 1].map { (side: Float) in
                    Part(min(side * 0.405, side * 0.445), max(side * 0.405, side * 0.445), -0.30, -0.22, colour: Map3DGuideway.dark)
                }
            case .maglev: [-1, 1].flatMap { (side: Float) in
                    [Part(min(side * 0.95, side * 1.35), max(side * 0.95, side * 1.35), -0.52, -0.45, colour: Map3DGuideway.dark),
                     Part(min(side * 1.38, side * 1.43), max(side * 1.38, side * 1.43), -0.40, -0.05, colour: Map3DGuideway.dark)]
                }
            case .suspended: [Part(-0.25, 0.25, -0.47, -0.45, colour: Map3DGuideway.dark)]
            }
        }

        /// The metres between two supports along the beam.
        var supportSpacing: Float {
            switch self {
            case .straddle: 20
            case .maglev, .suspended: 25
            }
        }
    }

    /// One block of a beam's cross-section: from `left` to `right` across
    /// (metres right of the middle) and from `bottom` to `top` up from the
    /// running surface.
    struct Part: Hashable, Sendable {
        let left: Float, right: Float, bottom: Float, top: Float
        let colour: UInt32

        init(_ left: Float, _ right: Float, _ bottom: Float, _ top: Float, colour: UInt32) {
            (self.left, self.right, self.bottom, self.top, self.colour) = (left, right, bottom, top, colour)
        }
    }

    /// The samples' colours: the concrete and steel the palette has
    /// (``Map3DGuidedTrains/palette(band:accent:beam:)``'s `beam`) and
    /// the trains' `dark`.
    static let concrete = Map3DPalette.concrete
    static let steel = Map3DPalette.steel
    static let dark = Map3DMTRUrbanLine.meshPalette[11]

    /// The straddle and maglev piers' columns, metres across and along
    /// (the maglev's 1.1 m the reference's maglev world's,
    /// `taiwan-maglev-world.js`).
    static func column(of kind: Kind) -> (across: Float, along: Float) {
        kind == .maglev ? (1.1, 1.1) : (1.0, 1.2)
    }

    /// The suspended beam's portal frame: its two legs' middles this far
    /// either side of the beam's middle (clear of the 2.60 m car), each
    /// this thick, and its crossbar this deep on the beam's top.
    static let portalHalfSpan: Float = 2.2
    static let portalLeg: Float = 0.6
    static let portalBar: Float = 0.6

    // MARK: Which track

    /// Each edge of `world`'s track that is a guideway, and whose: every
    /// edge the journey of a line whose trains are all of one guideway
    /// type runs on, but those any other line's runs on too (its trains
    /// of another type, or some of them) or two guideways' lines share.
    /// Only the lines calling at a station a guideway line calls at are
    /// driven for the other lines' track: a line elsewhere does not reach
    /// it. Empty when no line runs guideway trains.
    static func edges(in world: GameWorld) -> [TrackEdgeID: Kind] {
        var kinds: [TrainID: Kind] = [:]
        for train in world.trains { if let kind = Kind(train.type) { kinds[train.id] = kind } }
        guard !kinds.isEmpty else { return [:] }
        func kind(of line: ServiceLine) -> Kind?? {
            let trains = line.assignedTrains
            guard !trains.isEmpty else { return .none }
            let found = Set(trains.map { kinds[$0] })
            return found.count == 1 ? .some(found.first!) : .some(nil)
        }
        let guided = world.lines.filter { kind(of: $0).flatMap { $0 } != nil }
        guard !guided.isEmpty else { return [:] }
        let stations = Set(guided.flatMap(\.stops))
        func edges(of line: ServiceLine) -> Set<TrackEdgeID> {
            var services: [Int?] = line.trains.isEmpty ? [] : [nil]
            for (index, pattern) in line.patterns.enumerated() where !pattern.trains.isEmpty { services.append(index) }
            var found = Set<TrackEdgeID>()
            for service in services {
                guard let journey = world.lineJourney(line.id, pattern: service) else { continue }
                for leg in GameWorld.legEdges(of: journey) { found.formUnion(leg.edges) }
            }
            return found
        }
        var laid: [TrackEdgeID: Kind] = [:]
        var shared = Set<TrackEdgeID>()
        for line in world.lines {
            guard case .some(let own) = kind(of: line) else { continue }
            if own == nil, !line.stops.contains(where: stations.contains) { continue }
            for edge in edges(of: line) {
                guard let own else {
                    shared.insert(edge)
                    continue
                }
                if let other = laid[edge], other != own { shared.insert(edge) }
                laid[edge] = own
            }
        }
        for edge in shared { laid[edge] = nil }
        return laid
    }

    // MARK: Drawing

    /// `parts` swept along `line` (the rails' top, as the track is drawn)
    /// raised `lift` metres to the running surface: each part's top and
    /// two sides, its underside when `under`, and its two ends.
    static func sweep(_ parts: [Part], along line: [Map3DPoint], lift: Float, under: Bool, into mesh: inout Map3DMesh) {
        guard line.count > 1 else { return }
        let across = Map3DMesh.acrossDirections(line)
        for part in parts {
            func at(_ index: Int, _ x: Float, _ y: Float) -> Map3DPoint {
                line[index] + across[index] * x + Map3DPoint(0, lift + y, 0)
            }
            for index in 0..<(line.count - 1) {
                let next = index + 1
                // Each face counter-clockwise seen from outside.
                mesh.addQuad(at(index, part.left, part.top), at(index, part.right, part.top), at(next, part.right, part.top),
                             at(next, part.left, part.top), color: part.colour)
                mesh.addQuad(at(next, part.right, part.top), at(index, part.right, part.top), at(index, part.right, part.bottom),
                             at(next, part.right, part.bottom), color: Map3DColor.shaded(part.colour, 0.82))
                mesh.addQuad(at(index, part.left, part.top), at(next, part.left, part.top), at(next, part.left, part.bottom),
                             at(index, part.left, part.bottom), color: Map3DColor.shaded(part.colour, 0.72))
                if under {
                    mesh.addQuad(at(index, part.right, part.bottom), at(index, part.left, part.bottom), at(next, part.left, part.bottom),
                                 at(next, part.right, part.bottom), color: Map3DColor.shaded(part.colour, 0.6))
                }
            }
            // Its ends, facing out along the line.
            let last = line.count - 1
            mesh.addQuad(at(0, part.right, part.top), at(0, part.left, part.top), at(0, part.left, part.bottom), at(0, part.right, part.bottom),
                         color: Map3DColor.shaded(part.colour, 0.86))
            mesh.addQuad(at(last, part.left, part.top), at(last, part.right, part.top), at(last, part.right, part.bottom),
                         at(last, part.left, part.bottom), color: Map3DColor.shaded(part.colour, 0.86))
        }
    }

    /// The distances along a path `length` metres long where `kind`'s
    /// supports stand: every ``Kind/supportSpacing`` metres, half a
    /// spacing in from its start, at least one.
    static func supports(of kind: Kind, length: Float) -> [Float] {
        let spacing = kind.supportSpacing
        let count = max(1, Int((length / spacing).rounded()))
        return (0..<count).map { length * (Float($0) + 0.5) / Float(count) }
    }

    /// `kind`'s support at `point` on the rails' line, its beam along
    /// `along`, the ground `ground` metres up: a column from the ground
    /// to the beam's underside, none where the beam is less than 0.3 m
    /// over the ground; the suspended beam's portal frame, its legs from
    /// the ground to its crossbar on the beam's top.
    static func addSupport(_ kind: Kind, at point: Map3DPoint, along: Map3DPoint, ground: Float, into mesh: inout Map3DMesh) {
        let surface = point.y + kind.runningSurface
        switch kind {
        case .straddle, .maglev:
            let bottom = surface + (kind.body.map(\.bottom).min() ?? 0)
            guard bottom - ground > 0.3 else { return }
            let size = column(of: kind)
            mesh.addBox(base: Map3DPoint(point.x, ground, point.z), forward: along, length: size.along, width: size.across,
                        height: bottom - ground, top: concrete, side: concrete, capped: false)
        case .suspended:
            guard let forward = Map3DPoint(along.x, 0, along.z).normalized else { return }
            let right = Map3DPoint(-forward.z, 0, forward.x)
            let barBottom = surface + (kind.body.map(\.top).max() ?? 0), barTop = barBottom + portalBar
            for side in [Float(-1), 1] {
                let foot = Map3DPoint(point.x, ground, point.z) + right * (side * portalHalfSpan)
                guard barTop - ground > 0.5 else { continue }
                mesh.addBox(base: foot, forward: forward, length: portalLeg, width: portalLeg, height: barTop - ground,
                            top: steel, side: steel, capped: false)
            }
            mesh.addBox(base: Map3DPoint(point.x, barBottom, point.z), forward: right, length: 2 * portalHalfSpan + portalLeg,
                        width: portalLeg + 0.2, height: portalBar, top: steel, side: steel)
        }
    }
}

/// Decision 947: what tells whether the guideways can have changed without the
/// track changing: each line running guideway trains, its stops and
/// which guideways its trains run on. For the 3D map's scene key.
public struct Map3DGuidewaySignature: Hashable, Sendable {
    let lines: [Int]

    public init(world: GameWorld) {
        var kinds: [TrainID: Map3DGuideway.Kind] = [:]
        for train in world.trains { if let kind = Map3DGuideway.Kind(train.type) { kinds[train.id] = kind } }
        guard !kinds.isEmpty else {
            lines = []
            return
        }
        var lines: [Int] = []
        for line in world.lines {
            let trains = line.assignedTrains
            let mask = trains.reduce(0) { $0 | (kinds[$1].map { 1 << $0.rawValue } ?? 1 << 3) }
            guard mask & 0b111 != 0 else { continue }
            var hasher = Hasher()
            hasher.combine(line.id.rawValue)
            hasher.combine(mask)
            hasher.combine(line.stops)
            hasher.combine(line.patterns.map(\.trains.isEmpty))
            lines.append(hasher.finalize())
        }
        self.lines = lines
    }
}

extension Map3DScene.Builder {
    /// Decision 947: the edges of `snapshot`'s track that are guideways
    /// (``Map3DGuideway/edges(in:)``, kept by the scene's shared build),
    /// and the lines of the platforms beside a suspended beam, where its
    /// portal frames would stand on them.
    mutating func guideways(of snapshot: RailwaySnapshot) -> (edges: [TrackEdgeID: Map3DGuideway.Kind], hung: [[Map3DPoint]]) {
        if let guidewayEdges { return guidewayEdges }
        let edges = shared.guideways(of: snapshot, world: world)
        let hung = edges.values.contains(.suspended)
            ? snapshot.platforms.filter { edges[$0.platform.edge] == .suspended }.map { $0.points.map { point($0) + Self.lifted } }
            : []
        guidewayEdges = (edges, hung)
        return (edges, hung)
    }

    /// Decision 947: `line` (the rails' top, a piece of track of `kind`)
    /// as `guideway`'s beam: its body at every distance, its dark parts
    /// close up, its supports (none in a tunnel, which keeps its bore) and
    /// its shadow on the ground.
    mutating func addGuideway(_ line: [Map3DPoint], kind: TrackSectionKind, guideway: Map3DGuideway.Kind) {
        let middle = line[line.count / 2]
        let open = kind != .tunnel
        if !open {
            var bore = Map3DMesh()
            for piece in undergroundStations.outside(line) { addBore(piece, into: &bore) }
            mesh(at: middle) { $0.append(bore) }
        } else {
            let raised = line.map { $0 + Map3DPoint(0, guideway.runningSurface, 0) }
            let parts = guideway.body
            addDeckShadow(raised, grounds: line.map { ground(at: $0) },
                          width: (parts.map(\.right).max() ?? 0) - (parts.map(\.left).min() ?? 0))
        }
        mesh(at: middle) { Map3DGuideway.sweep(guideway.body, along: line, lift: guideway.runningSurface, under: open, into: &$0) }
        let target = self.target
        self.target = .near
        mesh(at: middle) { Map3DGuideway.sweep(guideway.details, along: line, lift: guideway.runningSurface, under: false, into: &$0) }
        self.target = target
        guard open, let path = Map3DStreetLife.Path(line) else { return }
        let hung = guideway == .suspended ? guidewayEdges?.hung ?? [] : []
        for distance in Map3DGuideway.supports(of: guideway, length: path.length) {
            let at = path.at(distance)
            // Not on a platform beside a suspended beam: its station holds it.
            guard !hung.contains(where: { Self.reaches($0, at.point, within: 1) }) else { continue }
            let ground = ground(at: at.point)
            mesh(at: at.point) { Map3DGuideway.addSupport(guideway, at: at.point, along: at.along, ground: ground, into: &$0) }
        }
    }

    /// Whether `line` passes within `reach` metres of `point`, seen from
    /// above.
    static func reaches(_ line: [Map3DPoint], _ point: Map3DPoint, within reach: Float) -> Bool {
        zip(line, line.dropFirst()).contains { a, b in
            let ab = Map3DPoint(b.x - a.x, 0, b.z - a.z), ap = Map3DPoint(point.x - a.x, 0, point.z - a.z)
            let length = ab.dot(ab)
            let share = length > 0 ? min(max(ap.dot(ab) / length, 0), 1) : 0
            return (ap - ab * share).length <= reach
        }
    }
}
