import Foundation

/// Decision 897: the Ngong Ping cable car's own cabins, made by the local
/// studio (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/hongkong-ngong-ping-cabin-2026-11/revision-2`,
/// #156; lessons in `docs/studio/lessons/hongkong-ngong-ping-cabin.md`) and
/// written in with `tools/train-models/glb_to_swift.py`
/// (``Map3DNgongPingCabinMesh``): the standard cabin (silver corner
/// posts, six gold slats on its lower half) and the crystal cabin with its
/// glass floor. Native space as ``CableParts``: the origin on the rope, +x
/// along it, +y left, +z up, metres; the floor at ``CableParts/cabinFloor``.
public enum Map3DNgongPingCabin {
    public enum Kind: String, CaseIterable, Sendable { case standard, crystal }

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py`:
    /// tankSteel, steel, dark, glass, white, slatGold, seat,
    /// cabinLight_lit (the brief's table: the colours are the palette's
    /// and the cable cars' own).
    static let meshPalette: [UInt32] = [
        Map3DPalette.tankSteel, CableParts.Paint.steel, Map3DPalette.dark, CableParts.Paint.glass,
        CableParts.Paint.white, Map3DPalette.slatGold, CableParts.Paint.deck, Map3DPalette.tunnelLamp,
    ]

    /// The cabin of `kind`, near or `far`; its glass see-through near as
    /// the other cabins' (``Map3DCableCar/seeThrough(_:far:)``) and lit
    /// after dark with its benches and ceiling lamp, as every cabin is
    /// (decision 897). `nil` if its mesh does not decode.
    public static func model(_ kind: Kind, far: Bool = false) -> Map3DModelPack.Model? {
        let name = "cablecar-cabin-ngongping-" + kind.rawValue + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let decoded = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette) else { return nil }
        // Every glass face is glass, the crystal floor's underside too (as
        // the Maokong crystal floor); the glass, benches and lamp lit.
        let lit: Set<UInt32> = [CableParts.Paint.deck, Map3DPalette.tunnelLamp]
        let vertices = decoded.vertices.map { original -> Map3DVertex in
            var v = original
            if v.color == CableParts.Paint.glass {
                v.layer = Map3DVertex.trainGlassLit
            } else if lit.contains(v.color) {
                v.layer = Map3DVertex.glowing
            }
            return v
        }
        let model = Map3DModelPack.Model(name: name, vertices: vertices, minimum: decoded.minimum, maximum: decoded.maximum)
        return Map3DCableCar.seeThrough(model, far: far)
    }

    /// The kind of Ngong Ping cabin `number`: crystal as the other lines'
    /// rule picks (``CablewayCabins/isCrystal(_:)``), standard otherwise.
    public static func kind(_ number: Int) -> Kind { CablewayCabins.isCrystal(number) ? .crystal : .standard }
}
