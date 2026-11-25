import Foundation
import GameCore

/// Decision 986: the Keikyu New 1000 (京急新1000形) at its real size, the
/// train of the type ``TrainType/keikyuNew1000``. The same cars as the
/// general train's of four cars or more (``Map3DRedCommuter``, decision
/// 956: the owner's old detailed cars, a red body, a white band round the
/// windows, three doors a side), shortened from their 20.00 m to the real
/// car's 18.00 m from coupler to coupler: a middle car scaled along the
/// car as a whole; a cab car keeps its nose, crew door and the small
/// window behind the cab as they were (so the nose's length to its width
/// is unchanged) and only its body behind them is shortened, which puts
/// its doors and windows nearest the real car's. The two bogies are
/// moved and not squashed, so a wheel stays round. Across the car nothing moved: it
/// is 2.80 m wide and its wheels stand on the 1,435 mm gauge. The roof is
/// 3.904 m above the rail, as the 20 m car's.
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/keikyu-new1000-2026-11/revision-5`, written
/// here by `tools/train-models/glb_to_swift.py`, ``encoded``.)
public enum Map3DKeikyuNew1000 {
    /// The key of its set (``Map3DTrainSet/keikyuNew1000(far:)``).
    public static let key = "keikyuNew1000"

    /// A car from coupler to coupler, metres: the real train's.
    public static let carLength: Float = 18

    /// The cab car, its cab at +x; `far`, the light version drawn from
    /// 500 m out. `nil` if its mesh does not decode.
    public static func cab(far: Bool = false) -> Map3DModelPack.Model? {
        decoded("keikyu-new1000-cab" + (far ? "-far" : ""))
    }

    /// The middle car; `nil` if its mesh does not decode.
    public static func middle(far: Bool = false) -> Map3DModelPack.Model? {
        decoded("keikyu-new1000-middle" + (far ? "-far" : ""))
    }

    /// As ``Map3DRedCommuter`` reads its own: the same materials in the
    /// same order, so its colours, its glass and its lamps.
    static func decoded(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, glass: Map3DRedCommuter.glassIndex,
                                            lamps: Map3DRedCommuter.lampIndices)
    }

    /// Decision 782: its set, near and far, its showcase row and its cars'
    /// triangles (1,100 and 1,314 near, 532 and 634 far) and length.
    static let registration = Map3DTrainRegistration(
        id: "keikyuNew1000",
        sets: [Map3DTrainSet.keikyuNew1000(), .keikyuNew1000(far: true)],
        showcase: [
            Map3DShowcase.Entry(key, "Keikyu New 1000", "京急新1000形", .japan, cars: 8, most: 12, gauge: 1.435),
        ],
        triangles: 500...1_400, length: 17.99...18.01)
}

extension Map3DTrainSet {
    /// Decision 986: the Keikyu New 1000 at its own 18.00 m
    /// (``Map3DKeikyuNew1000``): its cab car at the front, turned round at
    /// the back, its middle car between, the lamps its own lenses; `far`,
    /// its light cars from 500 m out. Should its mesh not decode, the
    /// general train's cars (``redCommuter(far:)``).
    static func keikyuNew1000(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DKeikyuNew1000.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far") {
            guard let cab = Map3DKeikyuNew1000.cab(far: far), let middle = Map3DKeikyuNew1000.middle(far: far) else {
                return redCommuter(far: far).build()
            }
            return Cars(head: cab, middle: middle, tail: cab.turned, single: nil)
        }
    }
}

extension TrainLivery {
    /// The Keikyu New 1000 (decision 986): its red body and the white band
    /// round its windows, the colours the 3D map draws it in
    /// (``Map3DRedCommuter/meshPalette``), and the rounded front its cab's
    /// slanted windscreen gives it.
    public static let keikyuNew1000 = TrainLivery(body: 0x8C1C1C, stripe: 0xE9E7DF, cab: 0x8C1C1C, nose: .round)
}
