import Foundation

/// Decision 408: the N700S-G, the author's own N700S model in the game's
/// dark green line (#1214, `docs/art/n700s-n700st/README.md`; the author's
/// mesh in the reference repository, `Railway/n700s-n700st-2026-10-24/
/// n700s-g/`), in two forms:
///
/// - near (``mesh(_:)``, ``Map3DTrainSet/n700sG()``): the author's mesh
///   itself with fewer triangles (`tools/hsr-trains-408/decimate.py`,
///   ``encodedMeshes``), the palette's colours;
/// - from 500 m out (``model(_:)``, ``Map3DTrainSet/n700sGFar()``): rebuilt
///   in the game's look with the train builder every other high-speed set
///   uses (decision 230): some 1,150 triangles a cab and 450 a middle car.
///
/// What the rebuild keeps from the author's mesh, measured off it (×1.22
/// along and across, so its 20.5-unit middle car is 25 m and its 2.8 units
/// 3.36 m; up, its skirt-to-roof 3.28 units onto the 3.03 m of the 700T's
/// section): the long nose (7.7 units, 9.4 m) and how its crown, sides and
/// chin run to the tip; the windscreen's place on it; the green line in two
/// bands under the windows; each of the five units' doors where they
/// stand; the pantograph cover on D and the fin on E. Its colours are
/// already the palette's (the body, skirt, roof, glass and doors are
/// ``Map3DTrainStyle``'s own, the line #1D4A44).
///
/// The units: A the cab, B to E the middle cars as the author's assembly
/// has them (A B C D E | E D C B A), each facing its own way; the game
/// draws A, C and D.
public enum Map3DN700SG {
    public enum Unit: String, CaseIterable, Sendable {
        case a, b, c, d, e
    }

    /// The line's dark green (`docs/art/n700-game-style-2026-10-16/`).
    static let green = Map3DColor.rgb(0x1D4A44)
    static let grey = Map3DColor.rgb(0x8F959B)

    /// Unit `unit`, its front at +x.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model {
        let name = "n700s-g-" + unit.rawValue
        var builder = StationKitBuilder()
        let body = Map3DTrainBuilder(style: style(unit), cab: unit == .a).model(named: name)
        builder.add(Map3DTrainSet.baked(body, tint: green), at: .zero)
        if unit == .a { windscreen(&builder) }
        let roof: Float = 3.62
        switch unit {
        case .d:
            // The pantograph cover over the car's back half (the author's
            // −7.8 to −3.1 units): a low wide step and a narrower top.
            builder.box(-6.65, roof, 0, 5.7, 2.6, 0.30, Map3DTrainStyle.roofColour)
            builder.box(-6.65, roof + 0.30, 0, 3.6, 2.1, 0.36, grey)
        case .e:
            // The fin at its back end (−10.2 to −9.6 units).
            builder.box(-12.0, roof, 0, 0.8, 0.22, 0.6, grey)
            builder.box(-11.4, roof, 0, 0.6, 0.22, 0.3, grey)
        default:
            break
        }
        return .flat(named: name, from: builder.mesh)
    }

    /// Decision 408 (third): unit `unit` near, the author's own mesh with
    /// fewer triangles (``encodedMeshes``, `tools/hsr-trains-408/decimate.py`):
    /// every colour boundary where the author drew it, about 4,600 to 5,600
    /// triangles where the author's have 9,000 to 13,000, in the same units
    /// and heights as ``model(_:)``; matte, a flat colour of the palette
    /// to a triangle; on the 700T's bogies. `nil` for a unit the game does
    /// not draw near (B, E).
    public static func mesh(_ unit: Unit) -> Map3DModelPack.Model? {
        let name = "n700s-g-mesh-" + unit.rawValue
        guard let text = encodedMeshes[unit], let centres = bogieCentres[unit],
              let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let body = decodedMesh([UInt8](data), named: name) else { return nil }
        // The 700T's bogies where the author's stood (the owner liked the
        // 700T's wheels better; the tool leaves the author's out).
        var builder = StationKitBuilder()
        builder.add(body, at: .zero)
        builder.refreshHighSpeedRunning(centres)
        return .flat(named: name, from: builder.mesh)
    }

    /// The palette each of the mesh's triangles takes its colour from, by
    /// index: the 700T's white, the line, glass, skirt, doors, roof, wheels,
    /// underframe and the lamps (lit by ``Map3DTrainSet/lit(_:front:)``).
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, green, Map3DTrainStyle.glass, grey, Map3DTrainStyle.doorColour,
        Map3DTrainStyle.roofColour, Map3DTrainStyle.darkLine, Map3DTrainStyle.under, Map3DPalette.tunnelLamp,
    ]

    /// The model in `bytes`, little-endian: the vertex count (UInt16), each
    /// vertex x, y, z in millimetres (Int16); the triangle count (UInt16),
    /// each triangle's three vertex indices (UInt16) and palette index
    /// (UInt8). A triangle with no area is left out.
    static func decodedMesh(_ bytes: [UInt8], named name: String) -> Map3DModelPack.Model? {
        var at = 0
        func u16() -> Int? {
            guard at + 2 <= bytes.count else { return nil }
            defer { at += 2 }
            return Int(UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)
        }
        guard let vertexCount = u16() else { return nil }
        var points: [Map3DPoint] = []
        points.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            guard let x = u16(), let y = u16(), let z = u16() else { return nil }
            func metres(_ n: Int) -> Float { Float(Int16(truncatingIfNeeded: n)) / 1000 }
            points.append(Map3DPoint(metres(x), metres(y), metres(z)))
        }
        guard let triangleCount = u16() else { return nil }
        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(triangleCount * 3)
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for _ in 0..<triangleCount {
            guard let a = u16(), let b = u16(), let c = u16(), at < bytes.count else { return nil }
            let paint = Int(bytes[at])
            at += 1
            guard [a, b, c].allSatisfy(points.indices.contains), meshPalette.indices.contains(paint) else { return nil }
            let corners = [points[a], points[b], points[c]]
            guard let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { continue }
            for p in corners {
                vertices.append(Map3DVertex(p, normal: normal, color: meshPalette[paint], layer: Map3DVertex.plain))
                low = Map3DPoint(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                high = Map3DPoint(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
            }
        }
        guard at == bytes.count, !vertices.isEmpty else { return nil }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }

    /// Unit `unit` turned round, for the train's back half.
    public static func reversed(_ unit: Unit) -> Map3DModelPack.Model {
        let model = model(unit).turned
        return Map3DModelPack.Model(name: "n700s-g-" + unit.rawValue + "-reversed", vertices: model.vertices,
                                    minimum: model.minimum, maximum: model.maximum)
    }

    /// The windscreen as a panel of its own laid on the nose (the author's
    /// 4.9 to 6.5 units along, ±0.72 across), a hand's breadth proud, its
    /// edges sharp where the shell's painted vertices would blur them.
    static func windscreen(_ builder: inout StationKitBuilder) {
        let style = style(.a), shell = Map3DTrainBuilder(style: style, cab: true)
        let noseStart = style.length / 2 - style.nose, top = Map3DTrainBuilder.ringPoints / 2
        let steps: [Float] = [0.28, 0.33, 0.38, 0.43, 0.48, 0.52]
        let rings = steps.map { t in shell.ring(at: noseStart + style.nose * t, t: t).map { $0.point + Map3DPoint(0, 0.03, 0) } }
        for (a, b) in zip(rings, rings.dropFirst()) {
            for k in top - 2..<top + 2 {
                let inside = Map3DPoint((a[k].x + b[k].x) / 2, 1, 0)
                builder.face([a[k], a[k + 1], b[k + 1], b[k]], inside: inside, color: Map3DTrainStyle.glass)
            }
        }
    }

    /// The car's length: the cab 25.3 m (the author's 20.75 units), the
    /// middle cars 25 m (20.5).
    static func length(_ unit: Unit) -> Float { unit == .a ? 25.3 : 25.0 }

    /// Where each unit's doors stand, metres from its middle (the author's
    /// units ×1.22): A behind the nose and at its back, B and D one in from
    /// the back and at (or near) the front, C at both ends, E at its back.
    static func doors(_ unit: Unit) -> [Float] {
        switch unit {
        case .a: return [-9.87, 3.15]
        case .b: return [-9.0, 10.8]
        case .c: return [-12.1, 12.1]
        case .d: return [-9.0, 12.1]
        case .e: return [-12.1]
        }
    }

    static func style(_ unit: Unit) -> Map3DTrainStyle {
        var style = Map3DTrainStyle(
            name: "n700sG", length: length(unit), halfWidth: 1.68, floor: 0.62, roof: 3.65,
            nose: 9.36, drop: 1.8, lift: 0.4, tuck: 0.26, cap: 0.5,
            wing: 0.04, shoulder: 0.64, canopy: 0.06, dive: 0.08,
            body: Map3DColor.rgb(0xF6F6F4), skirt: grey, skirtTop: 0.24,
            band: 0.478...0.542, line: 0.434...0.463, lineColour: green,
            windows: 0.546...0.826, windowPitch: 1.06, windowWidth: 0.52, doors: 2,
            doorWidth: 0.8, doorLayout: .carEnds, doorWindows: true,
            roofKind: .cableShrouds,
            screenFrom: 0.28, screenTo: 0.52, screenDown: 2, screenAcross: 0.62)
        style.doorsAt = doors(unit)
        style.lampSpan = 0.78...0.86
        style.lampShare = 0.40
        return style
    }
}
