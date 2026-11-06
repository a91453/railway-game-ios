import Foundation

/// Decision 581, later: the locomotives standing in the Changhua
/// Roundhouse. They are scenery, drawn with the roundhouse, not trains the
/// player runs. Each stall keeps the same locomotive every time; none is
/// picked at random.
///
/// A stall of decision 581's model is a closed shell behind a dark door
/// panel, and its doorway is narrower than a locomotive in stalls 5–9. So
/// a locomotive stands in one of the wider stalls (1–4, 10–12) on the
/// stall's centre line, its front towards the turntable and through the
/// doorway, the rest under the roof, as the real roundhouse's engines wait
/// with their noses at the open doors.
enum Map3DRoundhouseStock {
    /// The locomotives the roundhouse keeps: the depot's diesels. No
    /// electric one, the model draws no overhead wire; no steam one yet,
    /// ``Map3DSteamTender`` standing 4.76 m on the rails, above the
    /// doorway's 4.50 m lintel (the decision's next step).
    enum Kind: CaseIterable, Sendable {
        /// The R100 in TRA orange (``Map3DR100``).
        case r100
        /// The R200 (``Map3DR200``), the newer diesel.
        case r200

        /// The locomotive, wheels at 0, its front +x, its left +y: its
        /// own far model when `far`.
        func model(far: Bool) -> Map3DModelPack.Model {
            switch self {
            case .r100: Map3DR100.model(far: far)
            case .r200: Map3DR200.model(far: far)
            }
        }
    }

    /// Which stall (1 = east … 12 = west, as decision 581 numbers them)
    /// holds which locomotive, and how far its front stands out of the
    /// doorway, in metres. No two side by side, so the noses keep apart.
    static let parked: [(stall: Int, kind: Kind, out: Float)] = [
        (1, .r100, 2.0),
        (4, .r200, 2.0),
        (10, .r100, 2.0),
        (12, .r200, 2.0),
    ]

    /// The rails' top above the ground, where the wheels stand (decision
    /// 581's stall rails, 0.08 m bed and 0.11 m rail).
    static let railTop: Float = 0.19

    /// The middle of stall `stall`'s track, in degrees round the
    /// roundhouse's focus.
    static func axis(ofStall stall: Int) -> Float {
        let bounds = LandmarkMesh.roundhouseStallBounds
        return 0.5 * (bounds[stall - 1] + bounds[stall])
    }

    /// The radius from the focus of the locomotive's own origin, so that its
    /// front stands `out` metres outside the doorway.
    static func originRadius(stall: Int, front: Float, out: Float) -> Float {
        LandmarkMesh.roundhouseStallRIn[stall - 1] - out + front
    }

    /// The locomotives in the roundhouse model's own space (as
    /// ``Map3DTaipeiLandmark/model(full:)``: +x east, +y north, +z up,
    /// metres round the roundhouse's middle): close by in full, far off
    /// their own far models.
    static func model(full: Bool) -> LandmarkMesh {
        var mesh = LandmarkMesh(full: full)
        let focus = LandmarkMesh.roundhouseFocus
        for spot in parked {
            let deg = axis(ofStall: spot.stall), rad = deg * .pi / 180
            let outward = (x: cos(rad), y: sin(rad))
            let model = spot.kind.model(far: !full)
            let r0 = originRadius(stall: spot.stall, front: model.maximum.x, out: spot.out)
            let origin = (x: focus.x + r0 * outward.x, y: focus.y + r0 * outward.y)
            // Its front (+x) inwards, towards the turntable.
            let c = -outward.x, s = -outward.y
            let base = UInt32(mesh.vertices.count)
            for v in model.vertices {
                let x = origin.x + v.x * c - v.y * s, y = origin.y + v.x * s + v.y * c
                // Parked: its lamps are not lit.
                let layer = v.layer == Map3DVertex.glowing ? Map3DVertex.plain : v.layer
                mesh.vertices.append(Map3DVertex(Map3DPoint(x, y, v.z + railTop),
                                                 normal: Map3DPoint(v.nx * c - v.ny * s, v.nx * s + v.ny * c, v.nz),
                                                 color: v.color, u: v.u, v: v.v, layer: layer))
            }
            mesh.indices += (0 ..< UInt32(model.vertices.count)).map { base + $0 }
        }
        return mesh
    }
}

extension LandmarkMesh {
    /// Decision 581: the focus the 12 stalls radiate from (OSM turntable
    /// way 220285048 relative to way 220285047's bounding-box middle).
    static let roundhouseFocus: P2 = (6.64, -32.91)

    /// Decision 581: the 13 pier angles (degrees round the focus) bounding
    /// stalls 1…12, east to west, as OSM way 220285047's stepped rear wall.
    static let roundhouseStallBounds: [Float] = [
        55.65, 64.10, 72.55, 81.00, 91.72,
        98.42, 105.12, 111.82, 118.52,
        123.72, 134.98, 146.24, 157.50,
    ]

    /// Decision 581: each stall's doorway radius.
    static let roundhouseStallRIn: [Float] = [
        28.60, 28.65, 28.85, 28.95,
        29.10, 29.20, 29.40, 29.55,
        29.50, 29.65, 29.95, 30.35,
    ]

    /// Decision 581: the stepped rear wall's radii from OSM way 220285047:
    /// stalls 1–4 (v12..v16) about 52.4 m; 5–8 (v07..v11) about 58.4 m,
    /// reaching y = +24.895 m; 9 (v05..v06) about 55.9 m; 10–12 (v00..v04)
    /// about 52.9 m, reaching x = −42.515 m.
    static let roundhouseStallROut: [Float] = [
        52.20, 52.35, 52.48, 52.60,
        57.76, 58.44, 58.65, 58.40,
        55.90,
        52.72, 52.90, 53.20,
    ]
}
