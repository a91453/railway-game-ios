import Foundation
import GameCore

/// Decision 1033: 西螺大橋 over the Zhuoshui River and 大樹舊鐵橋 over
/// the Gaoping River, the local studio's two long truss bridges
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/tw-truss-bridges-2026-11/revision-2`,
/// #622; lessons in `docs/studio/lessons/tw-truss-bridges.md`). Each is
/// 1.5 to 2 km long, more than `glb_to_swift.py`'s ±327 m, so the studio
/// made one span (with the pier at its −X end), an end span and a pier
/// on their own (``Map3DXiluoBridge/encoded``,
/// ``Map3DDashuIronBridge/encoded``: +X along the bridge, the span's
/// middle at the origin, z 0 on the water), and the game lays them one
/// after another at their pitch along OpenStreetMap's line.
///
/// Every piece of one bridge stands on one foot, the lowest drawn ground
/// under its piers (``Map3DScene/Builder/foot(of:)``), so the deck runs
/// level and no pier hangs over the river bed. 西螺大橋 carries the base
/// map's road on its deck as 關渡大橋 does (decision 944, ``deck``); 大樹
/// 舊鐵橋 is drawn as it stands since Typhoon Haitang (2005) took its
/// middle: OpenStreetMap's `railway=razed` ways 1255512175 and 1255512176
/// are the gaps either side of its one lone span (way 1255512177).
enum Map3DTrussBridge: CaseIterable, Sendable {
    case xiluo, dashu

    /// One piece of the bridge: its model, how far along the bridge its
    /// middle stands from the bridge's (metres, +X), and whether it is
    /// turned round (the far end span).
    struct Piece: Equatable, Sendable {
        let model: String
        let along: Float
        let turned: Bool
    }

    /// The bridge's line and, for 西螺大橋, the deck the road is held on.
    var line: Map3DArchBridgeDeck {
        switch self {
        case .xiluo:
            // OpenStreetMap's way 49744833 (1,932 m, 190.6° from north),
            // its middle; 31 spans of 62.5 m, the road on top 8.5 m over
            // the water, the deck 4.4 m either side of its line.
            Map3DArchBridgeDeck(latitude: 23.8138020, longitude: 120.4611280, bearing: 190.61, half: 31 * 62.5 / 2, width: 4.4,
                                top: 8.5, piers: Self.xiluoPiers)
        case .dashu:
            // The ends of OpenStreetMap's seven ways (1,552 m, 95.1°), the
            // middle between them; 24 spans of 63.5 m.
            Map3DArchBridgeDeck(latitude: 22.6615599, longitude: 120.4342915, bearing: 95.08, half: 24 * 63.5 / 2, width: 3.9,
                                top: 8.5, piers: Self.dashuPiers)
        }
    }

    /// 西螺大橋's 32 piers, metres along from its middle: one under each
    /// joint and each end.
    static let xiluoPiers: [Float] = (0...31).map { (j: Int) -> Float in (Float(j) - 15.5) * 62.5 }
    /// The spans of 大樹舊鐵橋 that stand, counted from the west: the
    /// first seven, the lone one in the river (way 1255512177's 50 m) and
    /// the eastern eleven; 7, 8, 9, 11 and 12 fell.
    static let dashuStanding: [Int] = [0, 1, 2, 3, 4, 5, 6, 10, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23]
    /// The piers that still stand where the span east of them fell: under
    /// the west gap's edge (7), under the lone span's east end (11) and
    /// at the bridge's east end (24); the rest are their spans' own.
    static let dashuLonePiers: [Int] = [7, 11, 24]
    /// 大樹舊鐵橋's piers that stand, metres along from its middle.
    static let dashuPiers: [Float] = (dashuStanding + dashuLonePiers).sorted().map { (j: Int) -> Float in (Float(j) - 12) * 63.5 }

    /// The bridge's pieces, west (or north) first.
    var pieces: [Piece] {
        switch self {
        case .xiluo:
            // The entrance span at each bank (the far one turned round, so
            // its pier is the bank's abutment), the spans between, and the
            // pier under the last joint, which the turned span leaves bare.
            var pieces: [Piece] = (0...30).map { (k: Int) -> Piece in
                let end = k == 0 || k == 30
                return Piece(model: end ? "tw-xiluo-end" : "tw-xiluo-span", along: (Float(k) - 15) * 62.5, turned: k == 30)
            }
            pieces.append(Piece(model: "tw-xiluo-pier", along: 14.5 * 62.5, turned: false))
            return pieces
        case .dashu:
            let spans = Self.dashuStanding.map { (k: Int) -> Piece in Piece(model: "tw-dashu-span", along: (Float(k) - 11.5) * 63.5, turned: false) }
            let piers = Self.dashuLonePiers.map { (j: Int) -> Piece in Piece(model: "tw-dashu-pier", along: (Float(j) - 12) * 63.5, turned: false) }
            return spans + piers
        }
    }

    /// Its materials' colours, in `glb_to_swift.py --materials` order.
    var palette: [UInt32] {
        switch self {
        // archRed, deck, concrete, dark.
        case .xiluo: [Map3DPalette.mtrRed, Map3DPalette.portal, Map3DPalette.concrete, Map3DPalette.dark]
        // ironSteel, brickPier, stoneCap, trackBed.
        case .dashu: [Map3DPalette.steel, Map3DPalette.redBrick, Map3DPalette.concrete, Map3DPalette.ballast]
        }
    }

    var encoded: [String: String] {
        switch self {
        case .xiluo: Map3DXiluoBridge.encoded
        case .dashu: Map3DDashuIronBridge.encoded
        }
    }

    /// The model `name` in full close by, or its far model; empty if it
    /// does not decode (`Map3DTrussBridgesTests` keeps that from happening).
    func model(_ name: String, full: Bool) -> LandmarkMesh {
        guard let text = encoded[full ? name : name + "-far"], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let mesh = LandmarkMesh.decodedLandmark(Array(data), full: full, palette: palette, glass: [])
        else { return LandmarkMesh(full: full) }
        return mesh
    }

    /// The near triangles of the whole bridge, for the landmarks' budget
    /// (`Map3DLandmarkRegistryTests.testTheBudgets`).
    var nearTriangles: Int {
        pieces.reduce(0) { $0 + model($1.model, full: true).indices.count / 3 }
    }
}

/// The two models' meshes (``encoded``, `Map3DXiluoBridgeMesh.swift`).
enum Map3DXiluoBridge {}
/// The two models' meshes (``encoded``, `Map3DDashuIronBridgeMesh.swift`).
enum Map3DDashuIronBridge {}

extension Map3DScene.Builder {
    /// Decision 1033: the foot every piece of a landmark bridge stands on,
    /// and its road's deck is held over: the lowest drawn ground under its
    /// piers, or, with none given, the water at its middle (decision 944).
    mutating func foot(of bridge: Map3DArchBridgeDeck.Placed) -> Float {
        guard !bridge.deck.piers.isEmpty else { return drawnGround(x: bridge.middle.x, z: bridge.middle.z) }
        return bridge.deck.piers.map { at -> Float in
            let p = bridge.point(along: at)
            return drawnGround(x: p.x, z: p.z)
        }.min() ?? 0
    }

    /// Decision 1033: the truss bridges' pieces the scene holds, each
    /// where no track or platform but a tunnel's runs within it; in full
    /// close by, the far model from afar. Returns how many were built.
    @discardableResult
    mutating func addTrussBridges(frame: RealWorldFrame) -> Int {
        var built = 0
        for bridge in Map3DTrussBridge.allCases {
            guard let line = bridge.line.placed(frame: frame, origin: (originX, originY)) else { continue }
            let rotation = atan2(-line.along.z, line.along.x) * 180 / .pi
            var models: [String: [Bool: LandmarkMesh]] = [:]
            var ground: Float?
            for piece in bridge.pieces {
                let centre = line.point(along: piece.along)
                let world = (x: originX + Double(centre.x) * Self.metre, y: originY + Double(centre.z) * Self.metre)
                guard contains(x: world.x, y: world.y) else { continue }
                if models[piece.model] == nil {
                    models[piece.model] = [true: bridge.model(piece.model, full: true), false: bridge.model(piece.model, full: false)]
                }
                let model = models[piece.model]!
                let turn = rotation + (piece.turned ? 180 : 0)
                let body = LandmarkMesh.corners(Map3DHongKongLandmark.body(of: model[true]!), origin: centre, rotation: turn)
                guard isClearOfTrack(body) else { continue }
                let foot: Float
                if let ground { foot = ground } else {
                    foot = self.foot(of: line)
                    ground = foot
                }
                let anchor = Map3DPoint(centre.x, 0, centre.z)
                let saved = target
                var far: Map3DMesh?
                for (level, full) in [(Target.near, true), (.far, false)] {
                    target = level
                    let mesh = model[full]!.placed(origin: centre, ground: foot, rotation: turn)
                    keptColours.formUnion(mesh.vertices.map(\.color))
                    self.mesh(at: anchor) { $0.append(mesh) }
                    if !full { far = mesh }
                }
                target = saved
                if let far { state.landmarks.landmarkPlans.append(LandmarkPlan(far)) }
                built += 1
            }
        }
        return built
    }
}
