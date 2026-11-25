import Foundation

/// Decision 978: the Kyushu Shinkansen's 800 series (the "Tsubame"), the
/// owner's old cars (SwiftRailMac's d7f7f5e4, the cab car, and 652fb052,
/// the middle car: a long nose under a black cab mask, a white body, a
/// red roof, a thin red line under the windows, upright lamps on the
/// nose's shoulders, two bogies and eight wheels), their texture cut into
/// faces of the game's palette colours by
/// `tools/texture-palette/kyushu_800.py` and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// The old game drew every car 21 m long and 2.80 m wide; here they are
/// the real cars' size again: the middle car 25 m from coupling to
/// coupling and the cab car 27.35 m, 3.38 m wide and 3.65 m to the roof,
/// on the 1,435 mm gauge. The cab car is the old one made longer as a
/// whole, its nose not stretched or reshaped on its own (the owner,
/// 2026-11-25). No company mark, lettering or number is drawn, and no
/// pantograph (the old cars have none).
public enum Map3DKyushu800 {
    /// The cars the game draws: the cab car and the middle car.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "kyushu-800-cab"
        case middle = "kyushu-800-middle"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 27.35 : 25 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "kyushu800"

    /// How many cars its trains have.
    public static let cars = 6

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, red, grey, glass,
    /// dark, headlamp, taillamp, door. The body's white is the clinics' tile
    /// white (``Map3DPalette/tileWhite``), the roof and the line the old
    /// red commuter's deep red (``Map3DPalette/trainRed``, as dark as the
    /// old texture's roof), the skirts and the door frames steel, the trains' glass, the dark
    /// cab mask, car ends, bogies, gangways and floor, and the lamps: no
    /// new colour.
    static let meshPalette: [UInt32] = [
        Map3DPalette.tileWhite, Map3DPalette.trainRed, Map3DPalette.steel, Map3DTrainStyle.glass,
        Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.tileWhite,
    ]

    /// The palette index of the door panels: the body's white again, kept
    /// as its own index in ``encoded`` so that the faces of a door can be
    /// told from the wall's (to open the doors at a station one day). A
    /// door's window is the glass's faces, inside the panel's frame.
    static let doorIndex = 7

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 3

    /// A door of a car: its frame, its panel and the window in it, on each
    /// of the car's two side walls. The mesh is cut along this outline, so
    /// every triangle is wholly a door's or wholly the wall's: the doors
    /// can be moved apart from the wall, to open at a station, without the
    /// mesh being cut again. (A passenger door's outline is this box; the
    /// driver's door has a slanted top, so its box is only its place.) The
    /// same shape as the N700S's doors (`Map3DN700S.Door`).
    public struct Door: Sendable, Equatable {
        /// Along the car, metres from its middle, the cab's end positive.
        public let x: ClosedRange<Float>
        /// Over the rail, metres.
        public let z: ClosedRange<Float>
        /// The driver's own door, by the cab.
        public let crew: Bool

        /// Whether `point` is on this door, on the side wall its `y` is on.
        public func contains(_ point: Map3DPoint, margin: Float = 0.002) -> Bool {
            abs(point.y) > 1.5 && point.x >= x.lowerBound - margin && point.x <= x.upperBound + margin
                && point.z >= z.lowerBound - margin && point.z <= z.upperBound + margin
        }
    }

    /// `unit`'s doors, from its front to its back; each is on both sides.
    /// As `tools/texture-palette/kyushu_800.py` reports them.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            [Door(x: 4.396...5.141, z: 1.247...3.119, crew: true), Door(x: -12.782 ... -11.771, z: 1.247...3.119, crew: false)]
        case .middle:
            [Door(x: 10.531...11.647, z: 1.247...3.119, crew: false), Door(x: -7.924 ... -6.761, z: 1.247...3.119, crew: false)]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x. `nil` if its mesh does
    /// not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DKyushu800 {
    /// Decision 782: its set, its showcase row (six cars) and its cars'
    /// triangles (1,487 the cab car, 1,066 the middle car: few enough to be
    /// drawn at any distance a train's model is, so no far set) and
    /// lengths.
    static let registration = Map3DTrainRegistration(
        id: "kyushu800",
        sets: [Map3DTrainSet.kyushu800()],
        showcase: [
            Map3DShowcase.Entry(key, "Kyushu Shinkansen 800 series", "九州新幹線 800 系", .japan, cars: cars, fixed: true,
                                gauge: 1.435),
        ],
        triangles: 1_000...1_600, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// Decision 978: the owner's old 800 series cars (``Map3DKyushu800``),
    /// each its own length: the cab car, middle cars, the cab car turned
    /// round at the back. The ends' lamp lenses lit.
    static func kyushu800() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DKyushu800.key, ownLengths: true) {
            func model(_ unit: Map3DKyushu800.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DKyushu800.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.middle), tail: litLenses(model(.cab).turned, front: false),
                        single: nil)
        }
    }
}
