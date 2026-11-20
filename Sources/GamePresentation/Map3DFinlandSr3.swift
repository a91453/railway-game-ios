import Foundation

/// FINLAND-TRAINS-2: the Finnish Sr3 electric locomotive (green and white,
/// the livery it runs in now), as the local studio modelled it in Blender
/// from photographs and the published dimensions (19.05 m over buffers,
/// 3.02 m wide, 4.40 m to its lowered pantographs, Bo'Bo' on the 1,524 mm
/// gauge): a cab at each end with a flat, folded face, the white band
/// across the green body, six grey grilles and two dark ones on the roof,
/// the pantographs' lower arms dark red, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/finland-sr3-loco-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). No
/// company mark, lettering or number is drawn. As the Sr2's
/// (``Map3DFinlandSr2``), its cab windows are dark and mirror the sky,
/// but none lights at night.
public enum Map3DFinlandSr3 {
    /// The locomotive, one of its cabs at +x.
    public static let name = "finland-sr3-loco"

    /// The key of its intercity's set: the Sr3, the double-deck coaches
    /// (``Map3DFinlandDoubleDeck``) and the control car
    /// (``Map3DFinlandControlCar``).
    public static let key = "finlandIntercitySr3"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names white, roofSilver, green, skirt, mask, steel, dark, headlamp,
    /// taillamp, pantographRed. The Sr2's colours and the palette's train
    /// red (the work order's table); no new colour.
    static let meshPalette: [UInt32] = Map3DFinlandSr2.meshPalette + [Map3DPalette.trainRed]

    /// The palette index of the studio's `mask`, the cab windows' dark
    /// (and the doors' windows' and frames'): the work order gives the
    /// Sr3 no glass, so no window of it lights at night.
    static let maskIndex = 4

    /// How far from the middle the cab windows start, metres: the cab
    /// side windows from 7.3 m, the doors' windows and frames inside 6.9 m.
    static let cabWindows: Float = 7.1

    /// The locomotive; `far`, the light version drawn from 500 m out.
    /// `nil` if its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        guard let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: maskIndex) else { return nil }
        // Only the cabs' dark windows mirror the sky: the doors' windows
        // and frames, the same dark, stay plain.
        var vertices = model.vertices
        for start in stride(from: 0, to: vertices.count, by: 3) where vertices[start].layer == Map3DVertex.trainGlass {
            let x = (vertices[start].x + vertices[start + 1].x + vertices[start + 2].x) / 3
            guard abs(x) < cabWindows else { continue }
            for i in start..<start + 3 { vertices[i].layer = Map3DVertex.plain }
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }
}

extension Map3DFinlandSr3 {
    /// Decision 782: its intercity set, near and far, its showcase row
    /// and its cars' triangles (the Sr3 4,816 near and 2,200 far, the
    /// coach 6,736 and 3,076, the control car 7,104 and 3,362) and lengths
    /// (the Sr3 19.05 m, the coach 26.40 m, the control car 27.40 m).
    static let registration = Map3DTrainRegistration(
        id: "finlandIntercitySr3",
        sets: [Map3DTrainSet.finlandIntercity(sr3: true), .finlandIntercity(sr3: true, far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Finnish intercity, Sr3 electric", "芬蘭城際列車（Sr3 電力機車）", .finland,
                                cars: Map3DFinlandSr2.cars, most: 10, gauge: 1.524),
        ],
        triangles: 2_200...7_200, length: 19.0...27.45)
}
