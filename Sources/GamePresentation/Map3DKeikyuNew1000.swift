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
/// Revision 6 brings it up to the rules the old cars ported since keep
/// (decision 978's 800 series): each door its own piece (``doors(_:)``);
/// the narrow gangway's mouth a shallow V seen from above, at the joint in
/// the middle and 25 mm short of it at its sides, so that two cars turned
/// up to 4 degrees to each other on a curve keep apart (the real
/// commuter car has a narrow gangway, not a hood all round); and only the
/// lamps a train shows at each end lit (``Map3DTrainSet/litEnd(_:leading:)``).
/// (`a91453/railway-assets-private-2`,
/// `game-art-previews/docs/art/keikyu-new1000-2026-11/revision-6`, written
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
    /// same order, so its colours and its glass. Its lamps are left unlit
    /// here: the set lights the white ones at the front and the red ones
    /// at the back (``Map3DTrainSet/keikyuNew1000(far:)``).
    static func decoded(_ name: String) -> Map3DModelPack.Model? {
        guard let text = encoded[name], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: name, glass: Map3DRedCommuter.glassIndex)
    }

    /// A door of a near car: its dark frame, its two leaves and their
    /// windows, on one of the two side walls. The mesh is cut along the
    /// frame's outer outline, so every triangle is wholly a door's or
    /// wholly the wall's (the tool writes each door as a node of its own,
    /// `…-door-left-1` and so on, and the wall is whole without it): the
    /// doors can be moved apart from the wall one day without the mesh
    /// being cut again. The same shape as the 800 series' doors
    /// (``Map3DKyushu800/Door``), on a car 2.80 m wide.
    public struct Door: Sendable, Equatable {
        /// Along the car, metres from its middle, the cab's end positive.
        public let x: ClosedRange<Float>
        /// Over the rail, metres.
        public let z: ClosedRange<Float>
        /// The driver's own door, by the cab.
        public let crew: Bool
        /// The wall it is on: 1 the left (+y), -1 the right.
        public let side: Float

        /// Whether `point` is on this door. Half a millimetre of slack, no
        /// more (the 800 series' second review: at 2 mm a door took in
        /// faces of the wall's).
        public func contains(_ point: Map3DPoint, margin: Float = 0.0005) -> Bool {
            point.y * side > 1.2 && point.x >= x.lowerBound - margin && point.x <= x.upperBound + margin
                && point.z >= z.lowerBound - margin && point.z <= z.upperBound + margin
        }
    }

    /// The near cab car's doors (`cab: true`) or the middle car's, from
    /// the front back, the left wall's before the right's at each place,
    /// as the tool reports them (revision-6's `report.json`). The far cars
    /// are drawn from 500 m out and have none of their own.
    public static func doors(cab: Bool) -> [Door] {
        let z: ClosedRange<Float> = 1.16...3.24
        let places: [ClosedRange<Float>] = cab
            ? [5.174...6.61, -0.442...0.893, -5.809 ... -4.461]
            : [4.819...6.219, -0.77...0.625, -6.278 ... -4.883]
        let crew: [Door] = cab ? [1, -1].map { Door(x: 8.065...8.76, z: 1.16...3.055, crew: true, side: $0) } : []
        return crew + places.flatMap { x in [1, -1].map { Door(x: x, z: z, crew: false, side: $0) } }
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
    /// the back, its middle car between; the front's white lamps and the
    /// back's red ones lit (``litEnd(_:leading:)``), as the real train's;
    /// `far`, its light cars from 500 m out. Should its mesh not decode, the
    /// general train's cars (``redCommuter(far:)``).
    static func keikyuNew1000(far: Bool = false) -> Map3DTrainSet {
        let key = Map3DKeikyuNew1000.key
        return Map3DTrainSet(key: far ? key + "Far" : key, ownLengths: true, far: far ? nil : key + "Far") {
            guard let cab = Map3DKeikyuNew1000.cab(far: far), let middle = Map3DKeikyuNew1000.middle(far: far) else {
                return redCommuter(far: far).build()
            }
            return Cars(head: litEnd(cab, leading: true), middle: middle, tail: litEnd(cab.turned, leading: false), single: nil)
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
