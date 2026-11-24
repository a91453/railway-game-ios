import Foundation

/// Decision 956 (decision 891, later): the Keikyu New 1000 (京急新1000形),
/// the owner's old detailed cars (SwiftRailMac's 54af03fa, the cab car, and
/// a78b3de8, the middle car: a red body, a white band round the windows,
/// three doors a side, two bogies and eight wheels), which the local studio
/// cut from their texture into faces of the game's palette colours
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/keikyu-new1000-2026-11/revision-3`), written
/// here by `tools/train-models/glb_to_swift.py` (``encoded``). Each car is
/// 20.00 m from coupler to coupler (its gangways), its floor 1.00 m and its
/// roof 3.904 m above the rail, on the 1,435 mm gauge. No number or
/// lettering is drawn.
///
/// It runs as a commuter EMU of no type four cars or longer
/// (``Map3DTrainSet/set(forKey:count:locked:)``): the cab car at the front,
/// the same car turned round at the back and the middle car between, and
/// from 500 m out its far cars.
public enum Map3DRedCommuter {
    /// The set's key (``Map3DTrainSet/redCommuter(far:)``).
    static let key = "redCommuter"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material names
    /// red, white, silver, roof, glass, dark, headlamp, taillamp. The red
    /// body, the white window band (``Map3DPalette/acUnit``), the
    /// air-conditioners' grey white (``Map3DPalette/shedWalls`` [2]), the
    /// steel roof and door frames, the trains' glass, the dark gangways,
    /// underframe and bogies, and the lamps (decision 891's colours, the
    /// earlier car's blue marks left out).
    static let meshPalette: [UInt32] = [
        Map3DPalette.trainRed, Map3DPalette.acUnit, Map3DPalette.shedWalls[2], Map3DPalette.steel,
        Map3DTrainStyle.glass, Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the studio's glass material: its faces, and
    /// only they, are the windows the game lights at night and mirrors the
    /// sky in (decision 851).
    static let glassIndex = 4

    /// The palette indices of the lamp lenses, lit (decision 893).
    static let lampIndices: Set<Int> = [6, 7]

    /// The cab car, its cab at +x; `far`, the light version drawn from
    /// 500 m out. `nil` if its mesh does not decode.
    public static func cab(far: Bool = false) -> Map3DModelPack.Model? {
        decoded("keikyu-new1000-cab" + (far ? "-far" : ""))
    }

    /// The middle car; `nil` if its mesh does not decode.
    public static func middle(far: Bool = false) -> Map3DModelPack.Model? {
        decoded("keikyu-new1000-middle" + (far ? "-far" : ""))
    }

    static func decoded(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return decodedMesh([UInt8](data), named: name, glass: glassIndex, lamps: lampIndices)
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
