import Foundation

/// Decision 930: Hong Kong's Peak Tram car of 2022 (the sixth generation),
/// the two coupled cars as one model, as the local studio modelled it in
/// Blender from photographs (some 28 m over both cars, 2.86 m wide,
/// 3.63 m tall): the dark green body, the white roof with its long strip
/// of glass, the gold trim, and the windows' sills stepping down as the
/// cars' floors do on the slope, one palette colour a triangle
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/hk-peak-tram-car-2026-11/revision-2`),
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``). No
/// company mark, lettering or number is drawn.
///
/// The game has no Peak Tram line yet: the car is in the train showcase,
/// and the line's own work lays it on the slope.
public enum Map3DHKPeakTram {
    /// The two cars, the uphill end at +x.
    public static let name = "hk-peak-tram-car"

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "hkPeakTram"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: the studio's material
    /// names green, roof, gold, mask, glass, hardware, dark, taillamp,
    /// headlamp. The container wagon's dark green, the tile white, the
    /// palette's gold, the urban line train's mask and greys (decision
    /// 786) and the lamps; no new colour.
    static let meshPalette: [UInt32] = [
        Map3DContainerWagon.green, Map3DPalette.tileWhite, Map3DPalette.gold, Map3DMTRUrbanLine.meshPalette[5],
        Map3DTrainStyle.glass, Map3DMTRUrbanLine.meshPalette[10], Map3DMTRUrbanLine.meshPalette[11],
        Map3DPalette.lantern, Map3DTrainStyle.headlamp,
    ]

    /// The palette index of the studio's glass material.
    static let glassIndex = 4

    /// The two cars; `far`, the light version drawn from 500 m out.
    /// `nil` if its mesh does not decode.
    public static func model(far: Bool = false) -> Map3DModelPack.Model? {
        let name = Self.name + (far ? "-far" : "")
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, palette: meshPalette, glass: glassIndex)
    }

    /// Decision 782: its set, near and far, its showcase row (always the
    /// one model) and its triangles (4,984 near, 2,208 far) and length
    /// (28.00 m).
    static let registration = Map3DTrainRegistration(
        id: "hkPeakTram",
        sets: [Map3DTrainSet.hkPeakTram(), .hkPeakTram(far: true)],
        showcase: [Map3DShowcase.Entry(key, "Peak Tram car (2022)", "山頂纜車車廂（2022 年）", .hongKong, cars: 1, fixed: true, gauge: 1.52)],
        triangles: 2_200...5_000, length: 27.95...28.05)
}

extension Map3DTrainSet {
    /// Decision 930: the Peak Tram's two coupled cars
    /// (``Map3DHKPeakTram``), one model whatever the count, a cab at each
    /// end: the lamp lenses of both ends lit.
    static func hkPeakTram(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DHKPeakTram.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, fixedCars: 1, far: far ? nil : key + "Far") {
            let car = litLenses(Map3DHKPeakTram.model(far: far)
                ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: true).model(named: Map3DHKPeakTram.name), front: true)
            return Cars(head: car, middle: nil, tail: nil, single: litLenses(car, front: false))
        }
    }
}
