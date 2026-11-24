import Foundation

/// The owner's old commuter car (SwiftRailMac's model e752e7a2, 19.75 m, a
/// red body with a light band round the windows and one cab; the earlier
/// version's 京急新1000形, Keikyu New 1000, decision 891, later: e752e7a2
/// is that set's simplified car, without bogies), brought into
/// the game as the owner's untextured style asks: its flat texture cut into
/// faces of their own (`tools/texture-palette/cut_faces.py`), one palette
/// colour a triangle, and written here by `tools/texture-palette/to_swift.py`
/// (``encodedCab``, ``encodedMiddle``).
///
/// It runs as a commuter EMU of no type four cars or longer
/// (``Map3DTrainSet/set(forKey:count:locked:)``): the cab car at the front,
/// the same car turned round at the back and the middle car, the cab car's
/// back half and that half mirrored, between. About 1,500 triangles a car,
/// fewer than the far versions of the detailed sets, so it has no far set
/// of its own (decision 417's rule 1 is for the detailed cars).
public enum Map3DRedCommuter {
    /// The set's key (``Map3DTrainSet/redCommuter()``).
    static let key = "redCommuter"

    /// The colour of each of the mesh's palette indices: steel (the roof,
    /// the door frames), the grey-white body, the dark underframe and cab
    /// panels, the light band round the windows, the red body, the blue
    /// marks and the glass (which lights at night and catches the sky,
    /// ``Map3DTrainLights``, ``Map3DTrainMaterial``). Decision 891: the
    /// grey-white body and the light band are the palette's nearest
    /// (``Map3DPalette/shedWalls`` [2] for #C9CECC, ``Map3DPalette/acUnit``
    /// for #E9EBE5, ΔE 1.2 and 2.1).
    static let meshPalette: [UInt32] = [
        Map3DPalette.steel, Map3DPalette.shedWalls[2], Map3DPalette.dark, Map3DPalette.acUnit,
        Map3DPalette.trainRed, Map3DPalette.canopy, Map3DTrainStyle.glass,
    ]

    /// The cab car, its cab at +x; `nil` if its mesh does not decode.
    public static func cab() -> Map3DModelPack.Model? {
        decoded(encodedCab, named: "red-commuter-cab")
    }

    /// The middle car; `nil` if its mesh does not decode.
    public static func middle() -> Map3DModelPack.Model? {
        decoded(encodedMiddle, named: "red-commuter-car")
    }

    static func decoded(_ text: String, named name: String) -> Map3DModelPack.Model? {
        guard let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return decodedMesh([UInt8](data), named: name)
    }

    /// The model in `bytes`, little-endian: the vertex count (UInt16), each
    /// vertex x, y, z in millimetres (Int16); the triangle count (UInt16),
    /// each triangle's three vertex indices (UInt16) and palette index
    /// (UInt8). A triangle with no area is left out.
    /// Decision 780: `palette`, the colours of the indices (the local
    /// studio's cars, ``Map3DMTRAirportLine``, have their own).
    /// `glass`: the palette index of the studio's glass material. Its
    /// faces, and only they, are the car's window glass
    /// (``Map3DVertex/trainGlass``, ``Map3DTrainMaterial/marksOwnGlass(_:)``):
    /// the dark greys of a door or a window's frame, close to the glass in
    /// colour, stay what they are.
    ///
    /// Decision 893: `lamps`, the palette indices of the studio's lamp
    /// lenses, lit (``Map3DVertex/glowing``) face by face: for a car whose
    /// lenses share their colour with its paint (the Kaizuka line's red
    /// band and tail lamps), so the lamps are its materials', not its
    /// colours' (``Map3DTrainLights/marksOwnLamps(_:)``).
    static func decodedMesh(_ bytes: [UInt8], named name: String, palette: [UInt32] = meshPalette, glass: Int? = nil,
                            lamps: Set<Int> = [], perMetre: Float = 1000) -> Map3DModelPack.Model? {
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
            // Millimetres, or centimetres for a model over 32.7 m from its
            // origin (`glb_to_swift.py --centimetres`, decision 909).
            func metres(_ n: Int) -> Float { Float(Int16(truncatingIfNeeded: n)) / perMetre }
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
            guard [a, b, c].allSatisfy(points.indices.contains), palette.indices.contains(paint) else { return nil }
            let corners = [points[a], points[b], points[c]]
            guard let normal = (corners[1] - corners[0]).cross(corners[2] - corners[0]).normalized else { continue }
            // A face looking down is not glass (the pack's rule,
            // ``Map3DTrainMaterial/lowestNormal``): not seen against the sky.
            let layer = lamps.contains(paint) ? Map3DVertex.glowing
                : paint == glass && normal.z >= Map3DTrainMaterial.lowestNormal ? Map3DVertex.trainGlass : Map3DVertex.plain
            for p in corners {
                vertices.append(Map3DVertex(p, normal: normal, color: palette[paint], layer: layer))
                low = Map3DPoint(min(low.x, p.x), min(low.y, p.y), min(low.z, p.z))
                high = Map3DPoint(max(high.x, p.x), max(high.y, p.y), max(high.z, p.z))
            }
        }
        guard at == bytes.count, !vertices.isEmpty else { return nil }
        return Map3DModelPack.Model(name: name, vertices: vertices, minimum: low, maximum: high)
    }
}
