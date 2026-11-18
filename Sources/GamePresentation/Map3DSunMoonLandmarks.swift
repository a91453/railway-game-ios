import Foundation
import GameCore

// Decision 879: the owner's earlier Sun Moon Lake on Taiwan's 3D map. Its
// models are the owner's own (`a91453/railway-reference-private`,
// `OpenWorld/reference_snapshot/play/assets/sunmoon/`: the Shuishe pier,
// a tour boat, the Wenwu temple and a lakeside pavilion, made in Blender),
// stood as `play/src/sunmoon-main.js` stands them (its `assetParts`: the
// pier 0.67 × 1 × 2.5, the temple 2.1 × 1.3 × 2, three boats in a row off
// the pier's head, each on its stone base). That scene is a lake of its
// own, some 200 m across; here each stands where the real one does
// (OpenStreetMap). `tools/sunmoon-landmarks/glb_to_swift.py` writes the
// models into `Map3DSunMoonLandmarkMeshes.swift`; the colours are the
// game's (``materialColours``), not the models' textures. The ropeway
// there is the game's own (decisions 615 and 870).

/// Decision 879: one of the earlier Sun Moon Lake's models where it stands.
struct Map3DSunMoonLandmark: Sendable, Equatable {
    /// The models, by their file's name; each in its own metres (x right,
    /// y back, z up: its front faces -y), its origin on the ground or, the
    /// boat's, on its waterline.
    enum Model: String, CaseIterable, Sendable {
        case pier, temple, boat, pavilion

        /// The snapshot has no far model of the pavilion (5 m across).
        var hasFar: Bool { self != .pavilion }

        /// The model in full close by, or its far model (none: empty).
        func mesh(full: Bool) -> LandmarkMesh {
            guard full || hasFar, let text = Map3DSunMoonLandmark.encodedMeshes[rawValue + (full ? "" : "-lod1")],
                  let data = Data(base64Encoded: text), let mesh = Map3DSunMoonLandmark.decoded(Array(data), full: full)
            else { return LandmarkMesh(full: full) }
            return mesh
        }
    }

    let name: String
    let model: Model
    /// Where it is anchored: its own origin, or the boats' pier's.
    let latitude: Double
    let longitude: Double
    /// Degrees counter-clockwise seen from above; at 0 its front faces
    /// south.
    let rotation: Float
    /// Its origin from the anchor, metres right and back in the anchor's
    /// turned frame (the boats off the pier's head).
    var offset: (x: Float, y: Float) = (0, 0)
    /// Its own turn on top of the anchor's, degrees.
    var turn: Float = 0
    /// How high its origin stands over the water.
    var lift: Float = 0
    /// On the water: how far towards its front from the anchor the pier's
    /// shore end is, which is brought to the shore as the map draws it
    /// (``Map3DScene/Builder/shoreSlide(anchor:front:end:)``).
    var shoreEnd: Float?
    /// Half the length (right) and width (back) of the stone base it
    /// stands on, down to the lowest ground under it; none on the water.
    var base: (x: Float, y: Float)?

    static func == (a: Map3DSunMoonLandmark, b: Map3DSunMoonLandmark) -> Bool { a.name == b.name }

    /// The Shuishe pier's turn: its head towards the lake (south-east),
    /// along OpenStreetMap's pier (way 528958442).
    private static let pierRotation: Float = -133.6

    /// The models where they stand.
    ///
    /// - The pier: 30 m out from the shore end of OpenStreetMap's way
    ///   528958442 at 水社碼頭, 0.45 m over the water (the earlier scene's
    ///   pier at y 0.55 over water at 0.1). The base map's shore is
    ///   drawn coarser than OpenStreetMap's (tens of metres off
    ///   here), so the pier and its boats are moved along the pier until
    ///   its shore end is at the shore as drawn.
    ///   Behind it the scene's timber ramp to the shore (``rampMiddle``).
    /// - The boats: three in a row 14 m apart off the pier's head, each
    ///   turned 0.05 rad more than the last (the earlier scene's
    ///   `[-58, -44, -30]` at z 18 beside a pier at x -42, z 35; 3 m
    ///   farther out here, where the Blender pier's head, longer than the
    ///   scene's first boxes, would stand in the middle boat).
    /// - The temple: on the middle hall of 文武廟 (OpenStreetMap's way
    ///   799608745), its front down the hill to the lake as the real
    ///   halls', on the earlier scene's 39 m by 29 m stone base. It takes
    ///   the middle hall's place (its footprint is not drawn again,
    ///   ``Map3DScene/Builder/replacedPlots``); the real temple's front
    ///   and rear halls, 27 m and 29 m from its middle, stay as the map's
    ///   real buildings draw them, so the three halls stand in a row up
    ///   the hill as the real ones do.
    /// - The pavilion: at 梅荷園 on the shore west of the pier
    ///   (OpenStreetMap's node 3605024438), as the earlier scene's stood
    ///   66 m west of its pier, turned 0.5 rad from it, on its 8 m base.
    static let all: [Map3DSunMoonLandmark] = [
        Map3DSunMoonLandmark(name: "shuishe-pier", model: .pier, latitude: 23.864247, longitude: 120.911915, rotation: pierRotation, lift: 0.45, shoreEnd: rampEnd),
    ] + [Float(-16), -2, 12].enumerated().map { index, x in
        Map3DSunMoonLandmark(name: "boat-\(index)", model: .boat, latitude: 23.864247, longitude: 120.911915, rotation: pierRotation,
                             offset: (x, 20), turn: 0.05 * Float(index - 1) * 180 / .pi, shoreEnd: rampEnd)
    } + [
        Map3DSunMoonLandmark(name: "wenwu-temple", model: .temple, latitude: 23.869939, longitude: 120.927681, rotation: -57.2,
                             base: (19.5, 14.5)),
        Map3DSunMoonLandmark(name: "shore-pavilion", model: .pavilion, latitude: 23.863852, longitude: 120.911119,
                             rotation: pierRotation + 0.5 * 180 / .pi, base: (4, 4)),
    ]

    /// The game's colour of each of the models' materials, in
    /// `tools/sunmoon-landmarks/glb_to_swift.py`'s `MATERIALS` order: all
    /// the palette's own (``Map3DPalette``; the gold is Hong Kong's
    /// landmarks'). The models' stone, tile and wood textures are not used.
    static let materialColours: [UInt32] = [
        Map3DPalette.stone, // stone: steps, bases, the pier's abutment
        Map3DPalette.timber, // wood: the pier's deck and posts, beams
        Map3DPalette.templeRoof, // tile: the temple's and pavilion's roofs
        Map3DPalette.templeWall, // red: the temple's columns
        Map3DHongKongLandmark.materialColours[5], // gold: the temple's ridge ornaments
        Map3DPalette.terrazzo, // plaster: the temple's walls
        Map3DPalette.steel, // metal: bollards and rails
        Map3DPalette.dark, // rubber: fenders
        Map3DPalette.tankWhite, // boat: the hull
        Map3DPalette.gymGreen, // accent: the hull's stripe
        Map3DPalette.glazing, // glass: the boat's windows
        Map3DPalette.gymGreen, // seat
    ]

    /// Reads `tools/sunmoon-landmarks/glb_to_swift.py`'s encoding: the
    /// vertices in centimetres, each triangle with its material. Whole or
    /// not at all.
    static func decoded(_ bytes: [UInt8], full: Bool) -> LandmarkMesh? {
        var at = 0
        func u16() -> Int? {
            guard at + 2 <= bytes.count else { return nil }
            defer { at += 2 }
            return Int(UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)
        }
        func metres(_ n: Int) -> Float { Float(Int16(truncatingIfNeeded: n)) / 100 }
        guard let vertexCount = u16() else { return nil }
        var points: [LandmarkMesh.P3] = []
        points.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            guard let x = u16(), let y = u16(), let z = u16() else { return nil }
            points.append((metres(x), metres(y), metres(z)))
        }
        guard let triangleCount = u16() else { return nil }
        var mesh = LandmarkMesh(full: full)
        for _ in 0..<triangleCount {
            guard let a = u16(), let b = u16(), let c = u16(), at < bytes.count else { return nil }
            let paint = Int(bytes[at])
            at += 1
            guard [a, b, c].allSatisfy(points.indices.contains), materialColours.indices.contains(paint) else { return nil }
            mesh.tri(points[a], points[b], points[c], materialColours[paint], LandmarkMesh.plain)
        }
        guard at == bytes.count else { return nil }
        return mesh
    }

    /// Its origin in the scene, the anchor being at `anchor`.
    func origin(anchor: Map3DPoint) -> Map3DPoint {
        let r = rotation * .pi / 180, c = cos(r), s = sin(r)
        return Map3DPoint(anchor.x + offset.x * c - offset.y * s, 0, anchor.z - (offset.x * s + offset.y * c))
    }

    /// The way its anchor's front faces, across the scene's ground.
    var front: Map3DPoint {
        let r = rotation * .pi / 180
        return Map3DPoint(sin(r), 0, cos(r))
    }

    /// The earlier scene's timber ramp from the pier back to the shore
    /// (`sunmoon-main.js`: a deck 6 m by 20 m and 0.28 m thick, its middle
    /// 23 m behind the pier's and 0.5 m over the water, a post every 3 m
    /// down each side, 3 m from the middle line, 1.75 m over the water).
    static let rampMiddle: Float = 23, rampLength: Float = 20, rampWidth: Float = 6
    static let rampThickness: Float = 0.28, rampTop: Float = 0.64
    static let rampPostSpacing: Float = 3, rampPostAcross: Float = 3, rampPostTop: Float = 1.75, rampPostSide: Float = 0.14
    /// How far under the water the ramp's posts reach: as the pier's piles.
    static let pileDepth: Float = 1.8
    /// The ramp's shore end, from the pier's origin.
    static let rampEnd = rampMiddle + rampLength / 2

    /// The farthest a pier is moved to the shore as drawn, and the step.
    static let shoreReach: Float = 80
    static let shoreStep: Float = 2
}

extension Map3DScene.Builder {
    /// Decision 879: the earlier Sun Moon Lake's models where they stand,
    /// each when the scene holds its anchor and no track or platform but a
    /// tunnel's runs within it: in full in the closest detail, its far
    /// model from farther.
    /// The pier and the boats stand on the water; the temple and the
    /// pavilion on a stone base from the highest ground under them down
    /// to the lowest (as the earlier scene's), and the real building
    /// whose middle is within their body is not drawn again
    /// (``replacedPlots``; the houses round it stay). Returns the names
    /// of those built.
    @discardableResult
    mutating func addSunMoonLandmarks(frame: RealWorldFrame) -> [String] {
        var built: [String] = []
        for landmark in Map3DSunMoonLandmark.all {
            let place = frame.worldPosition(latitude: landmark.latitude, longitude: landmark.longitude)
            guard contains(x: place.x, y: place.y) else { continue }
            var anchor = point(x: place.x, y: place.y, height: 0)
            if let end = landmark.shoreEnd { anchor = anchor + landmark.front * shoreSlide(anchor: anchor, front: landmark.front, end: end) }
            let centre = landmark.origin(anchor: anchor)
            let rotation = landmark.rotation + landmark.turn
            let models = [true: landmark.model.mesh(full: true), false: landmark.model.mesh(full: false)]
            let body = LandmarkMesh.corners(Map3DHongKongLandmark.body(of: models[true]!), origin: centre, rotation: rotation)
            guard isClearOfTrack(body) else { continue }
            // The map's water lies on its ground, which is not level:
            // the pier over the highest of it along its length.
            let sunk = landmark.model == .pier ? [Float(-15), -7.5, 0, 7.5, 15].map { centre + landmark.front * $0 } : [centre]
            var ground = (sunk.map { drawnGround(x: $0.x, z: $0.z) }.max() ?? 0) + landmark.lift
            let saved = target
            if let base = landmark.base {
                // On the highest ground under its base, the base down to
                // the lowest.
                let corners = LandmarkMesh.corners(base, origin: centre, rotation: rotation)
                let heights = (corners + [centre]).map { drawnGround(x: $0.x, z: $0.z) }
                ground = heights.max() ?? ground
                let foot = (heights.min() ?? ground) - 0.25
                let r = rotation * .pi / 180
                for level in [Target.close, .standIn, .far] {
                    target = level
                    mesh(at: centre) { mesh in
                        mesh.addBox(base: Map3DPoint(centre.x, foot, centre.z), forward: Map3DPoint(cos(r), 0, -sin(r)),
                                    length: base.x * 2, width: base.y * 2, height: ground - foot,
                                    top: Map3DPalette.stone, side: Map3DPalette.stone)
                    }
                }
                keptColours.insert(Map3DPalette.stone)
            }
            // In full only in the closest detail (the pier and the temple
            // are 10,000 and 15,000 triangles); its far model in its
            // place from farther (the pavilion, which has none, in full
            // until the far city takes over).
            for (level, full) in [(Target.close, true), (.standIn, !landmark.model.hasFar), (.far, false)] {
                target = level
                let mesh = models[full]!.placed(origin: centre, ground: ground, rotation: rotation)
                keptColours.formUnion(mesh.vertices.map(\.color))
                self.mesh(at: centre) { $0.append(mesh) }
            }
            if landmark.model == .pier { addPierRamp(pier: centre, front: landmark.front, water: ground - landmark.lift) }
            target = saved
            if landmark.base != nil {
                // The square within its body whichever way it is turned:
                // the real hall or shelter it stands for has its middle
                // there, its neighbours (the temple's other halls) not.
                let size = Map3DHongKongLandmark.body(of: models[true]!), half = min(size.x, size.y) * 0.75
                replacedPlots.append(PlacedSquare(minX: centre.x - half, minZ: centre.z - half, maxX: centre.x + half, maxZ: centre.z + half))
            }
            built.append(landmark.name)
        }
        return built
    }

    /// Decision 879: the earlier scene's timber ramp behind the pier at
    /// `pier`, towards `front`, the pier standing over water `water`
    /// high: its deck at every distance, its posts close by. The map's water
    /// lies on its ground, which rises to the shore, so the deck climbs
    /// with it in 2 m steps (never down), each post on its own ground.
    mutating func addPierRamp(pier: Map3DPoint, front: Map3DPoint, water: Float) {
        typealias L = Map3DSunMoonLandmark
        let side = front.cross(.up), timber = Map3DPalette.timber, step: Float = 2
        let start = L.rampMiddle - L.rampLength / 2
        // Each step's middle along the pier's line, and its top.
        var steps: [(along: Float, top: Float)] = []
        var top = water + L.rampTop
        for index in 0..<Int(L.rampLength / step) {
            let along = start + (Float(index) + 0.5) * step, at = pier + front * along
            top = max(top, drawnGround(x: at.x, z: at.z) + L.rampTop)
            steps.append((along, top))
        }
        for level in [Target.close, .standIn, .far] {
            target = level
            mesh(at: pier) { mesh in
                var under = water + L.rampTop - L.rampThickness
                for step in steps {
                    let at = pier + front * step.along
                    mesh.addBox(base: Map3DPoint(at.x, under, at.z), forward: front, length: 2, width: L.rampWidth,
                                height: step.top - under, top: timber, side: timber)
                    under = step.top - L.rampThickness
                }
            }
        }
        target = .close
        var posts: [(foot: Map3DPoint, top: Float)] = []
        var along = start + 1
        while along <= start + L.rampLength - 1 {
            let deck = steps[min(Int((along - start) / step), steps.count - 1)].top
            for across in [-L.rampPostAcross, L.rampPostAcross] {
                let foot = pier + front * along + side * across
                posts.append((Map3DPoint(foot.x, drawnGround(x: foot.x, z: foot.z) - L.pileDepth, foot.z), deck - L.rampTop + L.rampPostTop))
            }
            along += L.rampPostSpacing
        }
        mesh(at: pier) { mesh in
            for post in posts {
                mesh.addBox(base: post.foot, forward: front, length: L.rampPostSide, width: L.rampPostSide, height: post.top - post.foot.y,
                            top: timber, side: timber)
            }
        }
        keptColours.insert(timber)
    }

    /// Decision 879: how far along `front` a pier anchored at `anchor`
    /// is moved for its shore end, `end` metres towards `front`, to stand
    /// at the shore as the base map draws it: the first step at which the
    /// end is on land (towards the shore when it is over water, back out
    /// to the last such step when it is inland). None where no shore is
    /// within ``Map3DSunMoonLandmark/shoreReach``, or no base map is read.
    func shoreSlide(anchor: Map3DPoint, front: Map3DPoint, end: Float) -> Float {
        let step = Map3DSunMoonLandmark.shoreStep, steps = Int(Map3DSunMoonLandmark.shoreReach / step)
        func wet(_ slide: Float) -> Bool { isOverWater(anchor + front * (end + slide)) }
        if wet(0) {
            return (1...steps).map { Float($0) * step }.first { !wet($0) } ?? 0
        }
        guard let out = (1...steps).map({ -Float($0) * step }).first(where: wet) else { return 0 }
        return out + step
    }
}
