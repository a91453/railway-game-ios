import Foundation

/// N700ST-PAINT (the owner, 2026-11-26: 「把台灣高鐵 n700s 改成 n700st 塗裝
/// 不就解決了」「這樣也不用刪 n700s 了」): the N700S in the Taiwan High
/// Speed Rail's paint, the N700ST, the train the player's own high-speed
/// lines run beside the 700T (``Map3DTrainSet/variant(of:number:locked:)``:
/// a train of the high-speed type, `HSR`, numbered odd).
///
/// Its cars are the N700S's own (``Map3DN700S``, decision 979: the same
/// mesh, doors, lamps, glass and lengths), only their two lines painted
/// another way. The real N700ST (Taiwan High Speed Rail, 2025-08: a white
/// body, an orange line and a black line meeting at the nose and running
/// side by side along the cars, as the 700T's do) has the 700T's colours:
/// the wide line under the windows, and its sweep up the nose, the 700T's
/// orange (``Map3DTrainShapeRefresh/highSpeedBandColor``), the narrow one
/// under it the 700T's black (``Map3DPalette/dark``). The N700S's lines are
/// one colour of its palette; every triangle of it wholly under
/// ``lowerLineTop`` is the narrow one (its triangles reach 1.71 m at most,
/// the wide line's start at 1.74 m, on every car). No company mark,
/// lettering or number is drawn, as on the N700S.
public enum Map3DN700ST {
    /// The key of its set (``Map3DTrainSet``).
    public static let key = "n700st"

    /// Over the rail, metres: a triangle of the N700S's lines whose every
    /// corner is under this is the narrow lower line's, and is black.
    static let lowerLineTop: Float = 1.725

    /// The N700S's palette with its lines the 700T's orange.
    static let meshPalette: [UInt32] = {
        var palette = Map3DN700S.meshPalette
        palette[lineIndex] = Map3DTrainShapeRefresh.highSpeedBandColor
        return palette
    }()

    /// The palette index of the N700S's lines.
    static let lineIndex = 1

    /// The colour of the narrow line: the 700T's black line's.
    static let lowerLineColor = Map3DPalette.dark

    /// `unit`'s car in this paint (the N700S's ``Map3DN700S/model(_:)``,
    /// named `n700st-…`); `nil` if its mesh does not decode.
    public static func model(_ unit: Map3DN700S.Unit) -> Map3DModelPack.Model? {
        guard let text = Map3DN700S.encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
              let model = Map3DRedCommuter.decodedMesh([UInt8](data), named: name(unit), palette: meshPalette, glass: Map3DN700S.glassIndex)
        else { return nil }
        var vertices = model.vertices
        let orange = meshPalette[lineIndex]
        for first in stride(from: 0, to: vertices.count - 2, by: 3)
            where vertices[first].color == orange && (first ..< first + 3).allSatisfy({ vertices[$0].z < lowerLineTop }) {
            for at in first ..< first + 3 { vertices[at].color = lowerLineColor }
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }

    /// The name of `unit`'s car in this paint.
    static func name(_ unit: Map3DN700S.Unit) -> String {
        "n700st-" + unit.rawValue.dropFirst("n700s-".count)
    }

    /// Its set and showcase row, with the N700S's limits.
    static let registration = Map3DTrainRegistration(
        id: "n700st",
        sets: [Map3DTrainSet.n700st()],
        showcase: [
            Map3DShowcase.Entry(key, "N700ST", "N700ST", .highSpeed, cars: Map3DN700S.cars),
        ],
        triangles: 2_500...5_000, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// The N700S's train (``n700s()``) in the N700ST's paint.
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
