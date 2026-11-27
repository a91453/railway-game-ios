import Foundation

/// Decision 1028 (continued): JR Kyushu's 885 series, the Relay Kamome's
/// train between Hakata and Takeo-Onsen, the owner's old cars
/// (SwiftRailMac's ba960a08, the cab car, and 145eb227, the middle car)
/// ported by the local studio (`railway-assets-private-2`
/// `game-art-previews/docs/art/kyushu-885-2026-11/revision-1/`, its
/// `tools/build.py`; reviewed once, as an old car's port is) and written
/// here by `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// The real cars' size: the cab car 21.65 m from its nose to its coupling,
/// the middle car 20.50 m, 2.91 m wide, the cab car's roof 3.825 m up and
/// the middle car's air conditioners 3.734 m, on the 1,067 mm gauge. The
/// old egg-shaped nose is kept as it was, scaled the same in every
/// direction; only the straight body behind the crew door is longer. The
/// livery since 2012: a white body, the blue frame round the front window
/// and a thin blue line along the skirts, in the palette's colours (the
/// owner, 2026-11-27: the game's own colours). Each coupled end has a white
/// hood all the way round whose mouth, seen from above, is a shallow V.
/// No company mark, lettering or number is drawn, and no pantograph.
public enum Map3DKyushu885 {
    /// The cars the game draws: the cab car and the middle car.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "kyushu-885-cab"
        case middle = "kyushu-885-middle"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 21.65 : 20.5 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "kyushu885"

    /// How many cars its trains have: the SM sets' six.
    public static let cars = 6

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, blue, grey, glass,
    /// dark, headlamp, taillamp, door. The body's white is the high-speed
    /// trains' white (``Map3DPalette/shopAwnings``' last), the blue the
    /// Airport Express's (``Map3DPalette/mtrAirportBlue``, nearest the
    /// photographs' front frame), the door frames and the roof's grilles
    /// steel, the trains' glass, the dark masks, bogies and floor, and the
    /// lamps: no new colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.shopAwnings[3], Map3DPalette.mtrAirportBlue, Map3DPalette.steel, Map3DTrainStyle.glass,
        Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.shopAwnings[3],
    ]

    /// The palette index of the door panels: the body's white again, kept
    /// as its own index in ``encoded`` so that a door's faces can be told
    /// from the wall's.
    static let doorIndex = 7

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night.
    static let glassIndex = 3

    /// A door of a car, on one of its side walls (``Map3DCarDoor``).
    public typealias Door = Map3DCarDoor

    /// `unit`'s doors, from its front to its back, the left wall's before
    /// the right's at each place, as the studio's `report.json` gives them
    /// (its GLB's nodes `…-door-left-1` and so on, and their triangles):
    /// the cab car's crew doors and the passenger door in its middle, the
    /// middle car's one door at its back.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            return [
                Door(x: 6.818...7.526, z: 1.118...3.063, crew: true, side: 1, wall: 1.3, left: 3334..<3400),
                Door(x: 6.818...7.526, z: 1.118...3.063, crew: true, side: -1, wall: 1.3, right: 3476..<3542),
                Door(x: -1.536 ... -0.615, z: 1.12...3.044, side: 1, wall: 1.3, left: 3400..<3476),
                Door(x: -1.536 ... -0.615, z: 1.12...3.044, side: -1, wall: 1.3, right: 3542..<3614),
            ]
        case .middle:
            return [
                Door(x: -9.104 ... -8.202, z: 1.12...3.044, side: 1, wall: 1.3, left: 1672..<1744),
                Door(x: -9.104 ... -8.202, z: 1.12...3.044, side: -1, wall: 1.3, right: 1744..<1816),
            ]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x. `nil` if its mesh does
    /// not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }

    /// Decision 782: its set, its showcase row (six cars) and its cars'
    /// triangles (3,614 the cab car, 1,816 the middle car: few enough to be
    /// drawn at any distance a train's model is, so no far set) and
    /// lengths.
    static let registration = Map3DTrainRegistration(
        id: "kyushu885",
        sets: [Map3DTrainSet.kyushu885()],
        showcase: [
            Map3DShowcase.Entry(key, "JR Kyushu 885 series", "JR 九州 885 系", .japan, cars: cars, fixed: true,
                                gauge: 1.067),
        ],
        triangles: 1_500...3_700, length: 20.4...21.7)
}

extension Map3DTrainSet {
    /// Decision 1028 (continued): the 885 series (``Map3DKyushu885``), each
    /// car its own length: the cab car, four middle cars (the back two
    /// turned round, as the real set's back half faces the other way), the
    /// cab car turned round at the back. The front's white lamps and the
    /// back's red ones lit (``litEnd(_:leading:)``): the two share each
    /// lamp housing, so the model itself lights neither.
    static func kyushu885() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DKyushu885.key, ownLengths: true) {
            func model(_ unit: Map3DKyushu885.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DKyushu885.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litEnd(model(.cab), leading: true), middle: model(.middle),
                        tail: litEnd(model(.cab).turned, leading: false), single: nil,
                        middleBack: model(.middle).turned)
        }
    }
}
