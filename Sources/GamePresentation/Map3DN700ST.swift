import Foundation

/// N700ST-PAINT (the owner, 2026-11-26: 「把台灣高鐵 n700s 改成 n700st 塗裝
/// 不就解決了」「這樣也不用刪 n700s 了」「跟真實車輛一樣吧」): the N700S in the
/// Taiwan High Speed Rail's paint, the N700ST, the train the player's own
/// high-speed lines run beside the 700T
/// (``Map3DTrainSet/variant(of:number:locked:)``: a train of the high-speed
/// type, `HSR`, numbered odd).
///
/// Its cars are the N700S's (``Map3DN700S``, decision 979: the owner's old
/// cars, their shape, doors, windows, lamps, hoods and lengths untouched),
/// their paint cut again by the local studio from the Taiwan High Speed
/// Rail's drawing of 2025-08 and a photograph of the first train painted,
/// 2026-04 (`railway-assets-private-2`
/// `game-art-previews/docs/art/n700st-paint-2026-11/revision-1/`, its
/// `tools/n700st.py`), and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``): a white nose with a
/// black oval mask round the driver's windows; by the cab car's first
/// doors a large orange block, from the skirt up to under the windows, its
/// front edge leaning forward and down, and right behind it a black band
/// parallel to it; along every car under the windows a narrow black line
/// over a wider orange one (as on the 700T), the white body under them and
/// the grey skirt. No company mark, lettering or number is drawn.
public enum Map3DN700ST {
    /// The key of its set (``Map3DTrainSet``).
    public static let key = "n700st"

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, orange, grey, glass,
    /// dark, headlamp, taillamp. The N700S's palette (``Map3DN700S``) with
    /// the 700T's orange (``Map3DTrainShapeRefresh/highSpeedBandColor``) in
    /// the place of its blue; the black mask, band and line are the dark
    /// of its bogies (``Map3DPalette/dark``), the 700T's black line's.
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, Map3DTrainShapeRefresh.highSpeedBandColor, Map3DPalette.steel,
        Map3DTrainStyle.glass, Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 3

    /// `unit`'s doors, from its front to its back, in the places the
    /// N700S's are (``Map3DN700S/doors(_:)``), their triangles this mesh's:
    /// as the studio's GLBs have their nodes (`report.json`'s `doors`).
    public static func doors(_ unit: Map3DN700S.Unit) -> [Map3DN700S.Door] {
        typealias Door = Map3DN700S.Door
        return switch unit {
        case .cab:
            [Door(x: 4.998...5.498, z: 1.341...2.791, crew: true, left: 4507..<4595, right: 4805..<4929),
             Door(x: 3.987...4.725, z: 1.272...2.906, crew: false, left: 4595..<4689, right: 4929..<5025),
             Door(x: -10.975 ... -10.236, z: 1.252...2.982, crew: false, left: 4689..<4805, right: 5025..<5143)]
        case .middle:
            [Door(x: 10.142...10.875, z: 1.265...2.954, crew: false, left: 2903..<3015, right: 3119..<3244),
             Door(x: -9.154 ... -8.415, z: 1.253...2.980, crew: false, left: 3015..<3119, right: 3244..<3384)]
        case .pantograph:
            [Door(x: 11.334...12.077, z: 1.265...2.953, crew: false, left: 3220..<3314, right: 3422..<3532),
             Door(x: -9.155 ... -8.416, z: 1.253...2.980, crew: false, left: 3314..<3422, right: 3532..<3682)]
        }
    }

    /// `unit`'s car in this paint, its cab (if it has one) at +x; `nil` if
    /// its mesh does not decode.
    public static func model(_ unit: Map3DN700S.Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[name(unit)], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name(unit), palette: meshPalette, glass: glassIndex)
    }

    /// The name of `unit`'s car in this paint (its GLB's).
    static func name(_ unit: Map3DN700S.Unit) -> String {
        "n700st-" + unit.rawValue.dropFirst("n700s-".count)
    }

    /// Its set and showcase row, with the N700S's lengths; its cars'
    /// triangles 5,143 the cab car (the mask and the block's slanting
    /// edges cut 278 more than the N700S's), 3,384 the middle car and
    /// 3,682 the car under the pantograph: some 45,000 a twelve-car train,
    /// few enough for no far set.
    static let registration = Map3DTrainRegistration(
        id: "n700st",
        sets: [Map3DTrainSet.n700st()],
        showcase: [
            Map3DShowcase.Entry(key, "N700ST", "N700ST", .highSpeed, cars: Map3DN700S.cars),
        ],
        triangles: 2_500...5_500, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// The N700S's train (``n700s()``: the pantograph car fourth and ninth,
    /// the back half turned, the lamps lit at the ends) in the N700ST's
    /// paint.
    static func n700st() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DN700ST.key, pantographCars: [3, 8], ownLengths: true) {
            func model(_ unit: Map3DN700S.Unit) -> Map3DModelPack.Model {
                Map3DN700ST.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: Map3DN700ST.name(unit))
            }
            let cab = model(.cab), middle = model(.middle), pantograph = model(.pantograph)
            return Cars(head: litEnd(cab, leading: true), middle: middle, tail: litEnd(cab.turned, leading: false), single: nil,
                        pantograph: pantograph, middleBack: middle.turned, pantographBack: pantograph.turned)
        }
    }
}
