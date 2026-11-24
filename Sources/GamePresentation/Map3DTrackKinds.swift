import GameCore

/// Decision 964 (TRACK-KINDS): what ordinary track looks like under the
/// trains that run it, the rail reference's four kinds of track and its
/// third rail (`Railway/rail-reference/regions/taiwan/source/rail-3d/`
/// `garage-scenes/metro-kit.js`: `ballastTrack`, `slabTrack`, `guideway`,
/// `embeddedTrack`, `thirdRail`). Until now every track was ballast,
/// sleepers' bed and two rails under an overhead line, a metro's and a
/// light rail's too.
///
/// Worked out in the presentation alone, from the trains each line runs
/// (as decision 947 first worked out its beams): nothing of it is in the
/// world or a save. The three guideways of decision 951
/// (``Map3DGuideway``) are the track's own and come first.
enum Map3DTrackKind: Int, Hashable, Sendable, CaseIterable {
    /// Ballast and two rails under an overhead line: Taiwan Railway's and
    /// every train's without a kind of its own.
    case ballast
    /// A concrete bed, the rails fastened to it, under an overhead line:
    /// the High Speed Rail's (the reference's `thsr.js`).
    case slab
    /// A concrete bed and a third rail under its cover, no overhead line:
    /// the heavy metros' (`ntpc-metro.js`, `kaohsiung-metro.js`,
    /// `taichung-metro.js`).
    case thirdRail
    /// Two running pads for rubber tyres between two guide bars, no rails
    /// and no overhead line: the Wenhu line's (`wenhu.js`).
    case rubber
    /// Rails level with a lawn between kerbs on the ground, with paving
    /// on a viaduct or in a tunnel, under an overhead line: a light
    /// rail's (`ntpc-lrt.js`, `kaohsiung-lrt.js`).
    case embedded

    /// The track a train of `type` runs on: the people mover's
    /// (``TrainType/apm``, drawn as the Wenhu line's trains) its pads, the
    /// light metro's (``TrainType/c``, drawn as a tram) embedded, every
    /// other metro's (drawn as Taipei's high-capacity trains, which have
    /// no pantograph) a slab and a third rail, a high-speed set's a slab;
    /// ballast for the rest and for a train of no type. The same split as
    /// a depot's shed (``Map3DDepotFacilities/system(for:)``).
    init(_ type: TrainType?) {
        guard let type else {
            self = .ballast
            return
        }
        if type == .apm {
            self = .rubber
        } else if type == .c {
            self = .embedded
        } else {
            switch type.spec.family {
            case .metro: self = .thirdRail
            case .highSpeed: self = .slab
            case .railway, .special: self = .ballast
            }
        }
    }

    /// Whether an overhead line hangs over it.
    var hasOverheadLine: Bool { self != .thirdRail && self != .rubber }

    /// Whether it has two steel rails.
    var hasRails: Bool { self != .rubber }

    /// Whether a viaduct carrying it is a metro's (twin narrow girders on
    /// a round column, a bare concrete deck: ``Map3DViaduct/metro``)
    /// rather than the railway's ballasted one.
    var ridesMetroViaduct: Bool { self == .thirdRail || self == .rubber || self == .embedded }

    // MARK: Sizes (metres) and colours

    // The reference's scenes are in units of a car 1.25 wide, so its
    // sizes are kept as shares of its rail (0.10 wide, 0.12 high) and of
    // its half gauge (0.46), against the game's rail (0.14 wide, 0.2
    // high) and gauge.

    /// The slab under the rails (the reference's a little over twice its
    /// gauge across), its top one rail's height under the rails' top.
    static let slabWidth: Float = 2.6
    static let slabTop: Float = -0.2
    /// The fastenings' dark strip under each rail.
    static let fasteningWidth: Float = 0.3

    /// The third rail: its middle out from the track's (inside a
    /// platform's edge, 1.6 m out), its top over the rails', and the
    /// cover over it.
    static let thirdRailOffset: Float = 1.35
    static let conductorWidth: Float = 0.09
    static let conductorTop: Float = 0.06
    static let coverWidth: Float = 0.26
    static let coverTop: Float = 0.2
    /// A bracket holding it every this many metres.
    static let bracketSpacing: Float = 5

    /// The rubber-tyred track: each pad's middle out from the track's
    /// (the VAL 256's tyres 1.88 m apart) and its width (wide enough for
    /// the 370's too, as the reference's "走行面取中間、做寬一點"); the
    /// guide bars out from the middle (clear of the 2.06 m car), their
    /// bottom and top over the pads.
    static let padOffset: Float = 0.94
    static let padWidth: Float = 0.5
    static let guideOffset: Float = 1.2
    static let guideBottom: Float = 0.13
    static let guideTop: Float = 0.33
    static let guidePostSpacing: Float = 4

    /// The embedded track: its lawn or paving across, the kerb each side,
    /// how far under the rails' top its surface lies, and a rail's head.
    static let embeddedWidth: Float = 2.9
    static let kerbWidth: Float = 0.25
    static let embeddedDrop: Float = 0.04
    static let embeddedRail: Float = 0.1
    static let grooveWidth: Float = 0.26

    /// The reference kit's materials (`slab`, `pad`, `fastener`, `cover`,
    /// `insulator`, `paving`); the lawn its `#5f8a48` lightened to sit
    /// with the game's ground.
    static let slabColour = Map3DColor.rgb(0xBDB8AB)
    static let padColour = Map3DColor.rgb(0x8D8F8C)
    static let fastening = Map3DColor.rgb(0x4A4C4E)
    static let cover = Map3DColor.rgb(0xD6CBA2)
    static let insulator = Map3DColor.rgb(0x6F6257)
    static let paving = Map3DColor.rgb(0x9D9A90)
    static let lawn = Map3DColor.rgb(0x86A96B)

    // MARK: Which track

    /// The kind of the trains `line` runs in `world`: `nil` when it has
    /// none (it says nothing of its track), ballast when they are of more
    /// than one kind. A high-speed line's is a slab whatever set runs it.
    static func kind(of line: ServiceLine, kinds: [TrainID: Map3DTrackKind]) -> Map3DTrackKind? {
        let trains = line.assignedTrains
        guard !trains.isEmpty else { return nil }
        if line.isHighSpeed { return .slab }
        let found = Set(trains.map { kinds[$0] ?? .ballast })
        return found.count == 1 ? found.first : .ballast
    }

    /// Each edge of `world`'s track that is not ballast, and its kind:
    /// every edge the journey of a line of one kind runs on (its own and
    /// each stopping pattern's with a train), but those a line of another
    /// kind runs on too, which stay ballast. Of the ballast lines only
    /// those calling at a station one of the others calls at are driven:
    /// a line elsewhere does not reach their track. Empty when every
    /// train runs on ballast.
    static func edges(in world: GameWorld) -> [TrackEdgeID: Map3DTrackKind] {
        var kinds: [TrainID: Map3DTrackKind] = [:]
        for train in world.trains {
            let kind = Map3DTrackKind(train.type)
            if kind != .ballast { kinds[train.id] = kind }
        }
        let own = world.lines.map { kind(of: $0, kinds: kinds) }
        let stations = Set(zip(world.lines, own).filter { $0.1 != nil && $0.1 != .ballast }.flatMap(\.0.stops))
        guard !stations.isEmpty else { return [:] }
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
        var laid: [TrackEdgeID: Map3DTrackKind] = [:]
        for (line, own) in zip(world.lines, own) {
            guard let own else { continue }
            if own == .ballast, !line.stops.contains(where: stations.contains) { continue }
            for edge in edges(of: line) {
                if let other = laid[edge], other != own {
                    laid[edge] = .ballast
                } else {
                    laid[edge] = own
                }
            }
        }
        return laid.filter { $0.value != .ballast }
    }

    // MARK: Drawing

    /// The bed under `kind`'s rails (or pads) along `line` (the rails'
    /// top) where ballast would lie, `depth` metres deep under
    /// ``Map3DScene/Builder/bedDrop``: concrete, and on it the embedded
    /// track's kerbs and its lawn (`green`) or paving, level with the
    /// rails.
    static func addBed(_ kind: Map3DTrackKind, along line: [Map3DPoint], depth: Float, green: Bool, into mesh: inout Map3DMesh) {
        typealias Builder = Map3DScene.Builder
        let concrete = Map3DPalette.concrete
        mesh.addRibbon(along: line, width: Builder.bedTop, lift: -Builder.bedDrop, depth: depth, top: concrete, side: concrete,
                       topPaint: Builder.concrete, sidePaint: Builder.concrete)
        guard kind == .embedded else { return }
        addEmbeddedSurface(along: line, green: green, into: &mesh)
    }

    /// The embedded track's surface on what carries it (a bed, a deck):
    /// kerbs and the lawn or paving between them, up to the rails' top.
    static func addEmbeddedSurface(along line: [Map3DPoint], green: Bool, into mesh: inout Map3DMesh) {
        let concrete = Map3DPalette.concrete
        for side in [Float(-1), 1] {
            mesh.addRibbon(along: line, width: kerbWidth, offset: side * (embeddedWidth + kerbWidth) / 2, lift: 0, depth: Map3DScene.Builder.bedDrop,
                           top: concrete, side: concrete)
        }
        mesh.addRibbon(along: line, width: embeddedWidth, lift: -embeddedDrop, top: green ? lawn : paving)
    }

    /// What `kind` has in place of ballast track's two rails, drawn at
    /// every distance: the rubber-tyred track's two pads. The others keep
    /// their rails (the embedded track's narrow heads are
    /// ``addRails(_:along:gauge:into:)``'s).
    static func addPads(along line: [Map3DPoint], into mesh: inout Map3DMesh) {
        for side in [Float(-1), 1] {
            mesh.addRibbon(along: line, width: padWidth, offset: side * padOffset, lift: 0, depth: Map3DScene.Builder.bedDrop,
                           top: padColour, side: Map3DPalette.concrete)
        }
    }

    /// The embedded track's rails: their heads alone, level with the
    /// surface, `offset` out from the middle.
    static func addEmbeddedRail(along line: [Map3DPoint], offset: Float, into mesh: inout Map3DMesh) {
        mesh.addRibbon(along: line, width: embeddedRail, offset: offset, lift: 0, depth: embeddedDrop, top: Map3DPalette.railTop,
                       side: Map3DPalette.rail)
    }

    /// `kind`'s small parts, seen close up only: the slab under the rails
    /// and their fastenings (`railOffset` out), the third rail under its
    /// cover on its brackets, the guide bars on their posts, the grooves
    /// beside the embedded rails.
    static func addDetails(_ kind: Map3DTrackKind, along line: [Map3DPoint], railOffset: Float, into mesh: inout Map3DMesh) {
        let bedDrop = Map3DScene.Builder.bedDrop
        switch kind {
        case .ballast:
            break
        case .slab, .thirdRail:
            mesh.addRibbon(along: line, width: slabWidth, lift: slabTop, depth: bedDrop + slabTop, top: slabColour, side: slabColour)
            for side in [Float(-1), 1] {
                mesh.addRibbon(along: line, width: fasteningWidth, offset: side * railOffset, lift: slabTop + 0.02, top: fastening)
            }
            guard kind == .thirdRail else { break }
            mesh.addRibbon(along: line, width: conductorWidth, offset: thirdRailOffset, lift: conductorTop, depth: 0.06, top: Map3DPalette.railTop,
                           side: Map3DPalette.rail)
            mesh.addRibbon(along: line, width: coverWidth, offset: thirdRailOffset, lift: coverTop, depth: 0.08, top: cover,
                           side: Map3DColor.shaded(cover, 0.82))
            addPosts(along: line, every: bracketSpacing, offset: thirdRailOffset + 0.08, across: 0.1, bottom: -bedDrop, top: coverTop - 0.02,
                     colour: insulator, into: &mesh)
        case .rubber:
            mesh.addRibbon(along: line, width: 2 * guideOffset + 0.4, lift: slabTop, depth: bedDrop + slabTop, top: slabColour, side: slabColour)
            for side in [Float(-1), 1] {
                mesh.addRibbon(along: line, width: 0.06, offset: side * guideOffset, lift: guideTop, depth: guideTop - guideBottom,
                               top: Map3DPalette.railTop, side: Map3DPalette.steel)
                addPosts(along: line, every: guidePostSpacing, offset: side * (guideOffset + 0.08), across: 0.1, bottom: slabTop, top: guideTop - 0.03,
                         colour: insulator, into: &mesh)
            }
        case .embedded:
            for side in [Float(-1), 1] {
                mesh.addRibbon(along: line, width: grooveWidth, offset: side * railOffset, lift: -embeddedDrop + 0.015, top: fastening)
            }
        }
    }

    /// A post 0.1 m along the line every `spacing` metres of it, half a
    /// spacing in from its start, `offset` right of its middle, `across`
    /// wide, from `bottom` to `top` over the rails' top.
    static func addPosts(along line: [Map3DPoint], every spacing: Float, offset: Float, across: Float, bottom: Float, top: Float, colour: UInt32,
                         into mesh: inout Map3DMesh) {
        guard let path = Map3DStreetLife.Path(line), top > bottom else { return }
        var distance = spacing / 2
        while distance < path.length {
            let at = path.at(distance)
            if let forward = Map3DPoint(at.along.x, 0, at.along.z).normalized {
                let right = Map3DPoint(-forward.z, 0, forward.x)
                mesh.addBox(base: at.point + right * offset + Map3DPoint(0, bottom, 0), forward: forward, length: 0.1, width: across,
                            height: top - bottom, top: colour, side: colour)
            }
            distance += spacing
        }
    }
}

/// Decision 964: what tells whether the kinds of the track can have
/// changed without the track's count changing: every line with a train,
/// its trains' kinds, its stops and which of its stopping patterns have
/// trains. Empty while every train runs on ballast. For the 3D map's
/// scene key.
public struct Map3DTrackKindSignature: Hashable, Sendable {
    let lines: [Int]

    public init(world: GameWorld) {
        var kinds: [TrainID: Map3DTrackKind] = [:]
        for train in world.trains {
            let kind = Map3DTrackKind(train.type)
            if kind != .ballast { kinds[train.id] = kind }
        }
        var lines: [Int] = []
        var special = false
        for line in world.lines {
            let trains = line.assignedTrains
            guard !trains.isEmpty else { continue }
            let fast = line.isHighSpeed
            let mask = trains.reduce(fast ? 1 << Map3DTrackKind.slab.rawValue : 0) { $0 | 1 << (kinds[$1] ?? .ballast).rawValue }
            if mask != 1 << Map3DTrackKind.ballast.rawValue { special = true }
            var hasher = Hasher()
            hasher.combine(line.id.rawValue)
            hasher.combine(mask)
            hasher.combine(fast)
            hasher.combine(line.stops)
            hasher.combine(line.patterns.map(\.trains.isEmpty))
            hasher.combine(line.trains.isEmpty)
            lines.append(hasher.finalize())
        }
        self.lines = special ? lines : []
    }
}

extension Map3DScene.Builder {
    /// Decision 964: the kind of each edge of `snapshot`'s track that is
    /// not ballast (``Map3DTrackKind/edges(in:)``, kept by the scene's
    /// shared build).
    mutating func trackKinds(of snapshot: RailwaySnapshot) -> [TrackEdgeID: Map3DTrackKind] {
        if let trackKindEdges { return trackKindEdges }
        let edges = shared.trackKinds(of: snapshot, world: world)
        trackKindEdges = edges
        return edges
    }
}
