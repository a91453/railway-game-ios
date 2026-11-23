import Foundation

/// Decision 930: the Wulai cable car's two large cabins, the green one and
/// the red one, made by the local studio from photographs of 2010 and 2011
/// (`a91453/railway-assets-private-2`
/// `game-art-previews/docs/art/wulai-cable-car-cabin-2026-11/revision-2`,
/// #285; lessons in `docs/studio/lessons/wulai-cable-car-cabin.md`) and
/// written in with `tools/train-models/glb_to_swift.py`
/// (``Map3DWulaiCabinMesh``): a long rounded box 6.64 m by 2.74 m, a band
/// of windows round its upper half, its lower half the cabin's colour, a
/// tray under it, and over its roof a steel frame up to the carriage that
/// runs on the ropes. The two are one shape in two colours. No name, mark,
/// lettering or painted picture.
///
/// The cabins of those years: the line's cabins today, its sixth, are
/// white (decision 930's gap). Native space as ``CableParts``: the origin
/// on the rope, +x along it, +y left, +z up, metres; the floor at
/// −4.38 m, the tray's underside at −5.30 m.
public enum Map3DWulaiCabin {
    public enum Kind: String, CaseIterable, Sendable { case green, red }

    /// The colours of the mesh's palette indices, in the order the
    /// studio's material names were given to `glb_to_swift.py`:
    /// paintGreen, paintRed, frame, glass, hanger, amber, underside,
    /// tailLamp_lit, cabinLight_lit (the brief's table and revision 2's
    /// `amber`: the palette's and the cable cars' own).
    static let meshPalette: [UInt32] = [
        Map3DPalette.emu900Green, Map3DPalette.mtrRed, CableParts.Paint.white, CableParts.Paint.glass, Map3DPalette.tankSteel,
        Map3DPalette.platformEdge, Map3DPalette.dark, Map3DPalette.lantern, CableParts.Paint.warm,
    ]

    /// The cabin of `kind`, near or `far`; its glass see-through near as
    /// the other cabins' (``Map3DCableCar/seeThrough(_:far:)``) and lit
    /// after dark with its ceiling's lamp panel and its red end lamps.
    /// `nil` if its mesh does not decode.
    public static func model(_ kind: Kind, far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name(kind) + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let decoded = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette) else { return nil }
        let lit: Set<UInt32> = [Map3DPalette.lantern, CableParts.Paint.warm]
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

    public static func name(_ kind: Kind) -> String { "cablecar-cabin-wulai-" + kind.rawValue }

    /// The cabin that is number `number` of its line's two
    /// (``CablewayCabins/numbers(of:pair:)``): the first green, the other red.
    public static func kind(_ number: Int) -> Kind { number == 0 ? .green : .red }
}
