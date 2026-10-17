import Foundation

// Decision 244: the street furniture of a real-world map's 3D streets —
// street trees, street lights and Taiwan's ubiquitous utility poles —
// each one small model (``Map3DModelPack``) drawn as instances near the
// camera, as the trains are (decision 230). The models are this project's
// own low-poly shapes in the 3D map's colours, sized after this
// repository's 3D city view (`Web/CityView/src/world/props.js`, MIT:
// `poleGeometry`, `lightGeometry`, `blobTreeGeometry`).

/// A kind of street furniture and its model.
public enum Map3DProp: String, CaseIterable, Sendable {
    /// A street tree: a trunk 2.4 m tall under a crown of three lumps. The
    /// crown takes the instance's colour (alpha 0), so each tree is its
    /// own green.
    case tree
    /// A street light: a mast 8.6 m tall, a 2.1 m arm over the road and a
    /// flat head.
    case lamp
    /// A concrete utility pole (電線桿) 10.2 m tall: two crossarms with
    /// their insulators and a pole-top transformer.
    case pole

    /// The model's name in ``Map3DModelPack``.
    public var modelName: String { "prop-" + rawValue }

    /// Its model, in the pack's space (+x along the street, +y toward the
    /// road, +z up, its foot at the origin).
    func model() -> Map3DModelPack.Model {
        var mesh = Map3DMesh()
        // Built in the scene's axes (x, y up, z): the road is toward −z, as
        // the model's +y.
        switch self {
        case .tree:
            mesh.addCylinder(base: .zero, radius: 0.16, height: 2.4, sides: 6, top: Map3DPalette.trunk, side: Map3DPalette.trunk)
            // Three lumps, lighter on top: the colour's alpha is 0, so the
            // instance's green shows, shaded by each face.
            for (centre, size) in [(Map3DPoint(0, 4.4, 0), Float(2.3)), (Map3DPoint(1.1, 3.9, 0.6), 1.6), (Map3DPoint(-1.0, 4.0, -0.7), 1.7)] {
                Self.addLump(&mesh, centre: centre, radius: size)
            }
        case .lamp:
            let steel = Map3DColor.rgb(0x9AA0A8)
            mesh.addCylinder(base: .zero, radius: 0.09, height: 8.6, sides: 6, top: steel, side: steel)
            mesh.addBox(base: Map3DPoint(0, 8.5, -1.05), forward: Map3DPoint(0, 0, -1), length: 2.1, width: 0.1, height: 0.1, top: steel, side: steel)
            // The head, lit from within at night in a warm white (the
            // sodium and LED lights of Taiwan's streets).
            let head = mesh.vertices.count
            mesh.addBox(base: Map3DPoint(0, 8.48, -2.25), forward: Map3DPoint(0, 0, -1), length: 0.75, width: 0.3, height: 0.12,
                        top: Self.lampLight, side: Self.lampLight)
            mesh.makeGlowing(from: head)
        case .pole:
            let concrete = Map3DColor.rgb(0xC9C8C2), steel = Map3DColor.rgb(0x7D838B)
            mesh.addCylinder(base: .zero, radius: 0.15, height: 10.2, sides: 6, top: concrete, side: concrete)
            for (height, length) in [(Float(9.6), Float(1.9)), (8.9, 1.5)] {
                mesh.addBox(base: Map3DPoint(0, height, 0), length: 0.09, width: length, height: 0.09, top: steel, side: steel)
            }
            for x: Float in [-0.85, 0, 0.85] {
                mesh.addBox(base: Map3DPoint(x, 9.69, 0), length: 0.08, width: 0.08, height: 0.16, top: Map3DColor.rgb(0xE6E4DC),
                            side: Map3DColor.rgb(0xE6E4DC))
            }
            mesh.addCylinder(base: Map3DPoint(0, 7.3, 0.42), radius: 0.3, height: 0.85, sides: 8, top: steel, side: Map3DColor.rgb(0x8E949B))
        }
        return Map3DModelPack.Model.flat(named: modelName, from: mesh)
    }

    /// A rough ball of twenty faces (a cap, two staggered rings of five
    /// and a base), its colour the instance's.
    static func addLump(_ mesh: inout Map3DMesh, centre: Map3DPoint, radius: Float) {
        let top = centre + Map3DPoint(0, radius * 0.95, 0), bottom = centre - Map3DPoint(0, radius * 0.6, 0)
        func ring(_ height: Float, _ size: Float, _ turn: Float) -> [Map3DPoint] {
            (0..<5).map { index in
                let angle = (Float(index) + turn) * 2 * Float.pi / 5
                return centre + Map3DPoint(cosf(angle) * radius * size, radius * height, sinf(angle) * radius * size)
            }
        }
        let upper = ring(0.45, 0.78, 0), lower = ring(-0.2, 0.98, 0.5)
        let leaf = Map3DColor.rgb(0x6FA85A) & 0x00FF_FFFF
        for index in 0..<5 {
            let next = (index + 1) % 5
            mesh.addFacet([top, upper[next], upper[index]], color: leaf)
            mesh.addFacet([upper[index], upper[next], lower[index]], color: leaf)
            mesh.addFacet([upper[next], lower[next], lower[index]], color: leaf)
            mesh.addFacet([bottom, lower[index], lower[next]], color: leaf)
        }
    }

    /// A street light's light: its head, and its pool on the ground.
    public static let lampLight = Map3DColor.rgb(0xFFE3B0)
    /// How far a street light's head is from its foot, along its left
    /// (the way its arm reaches).
    static let lampReach: Float = 2.25
    /// Ten level directions round a circle, for a light's pool.
    static let poolRing: [Map3DPoint] = (0..<10).map { index in
        let angle = Float(index) * 2 * Float.pi / 10
        return Map3DPoint(cosf(angle), 0, sinf(angle))
    }

    /// The street trees' greens, one picked for each tree (decision 272:
    /// livelier, as the parks').
    public static let greens: [UInt32] = [0x5FAD48, 0x4E9E3E, 0x6FBA52, 0x58A240, 0x7CC058].map(Map3DColor.rgb)
}

extension Map3DModelPack.Model {
    /// `mesh` in a model's space (+x the front, +y the left, +z up), three
    /// vertices to a triangle, each with the triangle's own normal.
    static func flat(named name: String, from mesh: Map3DMesh) -> Map3DModelPack.Model {
        var vertices: [Map3DVertex] = []
        vertices.reserveCapacity(mesh.indices.count)
        for start in stride(from: 0, to: mesh.indices.count, by: 3) {
            let corners = (0..<3).map { mesh.vertices[Int(mesh.indices[start + $0])] }
            let points = corners.map { Map3DPoint($0.x, -$0.z, $0.y) }
            guard let normal = (points[1] - points[0]).cross(points[2] - points[0]).normalized else { continue }
            for (corner, point) in zip(corners, points) {
                vertices.append(Map3DVertex(point, normal: normal, color: corner.color, layer: corner.glows ? Map3DVertex.glowing : Map3DVertex.plain))
            }
        }
        var low = Map3DPoint(.infinity, .infinity, .infinity), high = Map3DPoint(-.infinity, -.infinity, -.infinity)
        for v in vertices {
            low = Map3DPoint(min(low.x, v.x), min(low.y, v.y), min(low.z, v.z))
            high = Map3DPoint(max(high.x, v.x), max(high.y, v.y), max(high.z, v.z))
        }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }
}

extension Map3DInstance {
    /// A prop of model `index` standing on `foot`, its front along
    /// `forward` (its left, where a lamp's arm reaches, then toward the
    /// road), `scale` times its size, `tint` showing where its colour's
    /// alpha is 0.
    static func prop(_ index: Int, at foot: Map3DPoint, forward: Map3DPoint, scale: Float, tint: UInt32) -> Map3DInstance {
        let along = Map3DPoint(forward.x, 0, forward.z).normalized ?? Map3DPoint(1, 0, 0)
        let left = Map3DPoint(along.z, 0, -along.x)
        let up = along.cross(left)
        let x = along * scale, y = left * scale, z = up * scale
        func channel(_ shift: UInt32) -> Float { Float((tint >> shift) & 0xFF) / 255 }
        return Map3DInstance(model: index, transform: [x.x, x.y, x.z, 0, y.x, y.y, y.z, 0, z.x, z.y, z.z, 0, foot.x, foot.y, foot.z, 1],
                             stripe: (channel(0), channel(8), channel(16)))
    }
}
