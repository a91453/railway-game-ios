import Foundation

/// Decision 977: the Kyushu Shinkansen's N700 series 7000 and 8000 (the
/// through trains "Mizuho" and "Sakura"), the owner's old cars
/// (SwiftRailMac's bc97d3e5, the cab car, and fd0310c2, the middle car: a
/// long nose, two bogies and eight wheels), their texture cut into faces
/// of the palette's colours by `tools/texture-palette/kyushu_n700.py` and
/// written here by `tools/train-models/glb_to_swift.py` (``encoded``).
/// The colours are the real train's (the owner, 2026-11-25): a pale
/// white-blue body to the skirts' foot, and under the windows a navy line
/// with a thin gold line along each edge.
///
/// The old game drew every car 21 m long and 2.80 m wide; here they are
/// the real cars' size again: 25 m from coupling to coupling, the cab car
/// 27.35 m, 3.36 m wide and 3.60 m high, on the 1,435 mm gauge, at the
/// real cars' proportions (decision 977, section 8, measured on
/// photographs with the windows as the ruler, as the 800 series in
/// decision 978): the windows 1.04 m apart as the seats are, the cab car
/// fourteen windows a side (one more than the old car) and its nose the
/// old one's shape, and the middle car's doors 0.3 m nearer its ends.
/// Between two cars a full-width gangway hood in the real train's beige,
/// its mouth a shallow V so two cars on a curve do not touch. No company
/// mark, lettering or number is drawn, and no pantograph (the old cars
/// have none).
public enum Map3DKyushuN700 {
    /// The cars the game draws: the cab car and the middle car.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "kyushu-n700-cab"
        case middle = "kyushu-n700-middle"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 27.35 : 25 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "kyushuN700"

    /// How many cars its trains have.
    public static let cars = 8

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: whiteBlue, navy, gold,
    /// glass, dark, headlamp, taillamp, doorLine, hood. The first three are
    /// the real train's (``Map3DPalette/kyushuWhiteBlue``); then the trains'
    /// glass, the dark bogies, couplers and floor, the lamps, the doors'
    /// seams in steel grey (the doors themselves are the body's colour:
    /// without their seams the doors' small windows float on the wall, the
    /// owner 2026-11-25), and the gangway hoods in the real train's beige
    /// (measured on a photograph of the real cars, #DFD8B8; the palette's
    /// nearest, the MTR's cream).
    static let meshPalette: [UInt32] = [
        Map3DPalette.kyushuWhiteBlue, Map3DPalette.kyushuNavy, Map3DPalette.kyushuGold, Map3DTrainStyle.glass,
        Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DPalette.steel, Map3DPalette.mtrCream,
    ]

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 3

    /// A door of a car: where its leaf, with its seams, its window and the
    /// piece of the navy and gold line across it, is on each of the car's
    /// two side walls. The mesh is cut along this outline, so every
    /// triangle is wholly a door's or wholly the wall's (the tool writes
    /// each door as a node of its own too): the doors can be moved apart
    /// from the wall, to open at a station, without the mesh being cut
    /// again. (A passenger door's outline is this box, leaning up to 2.2 cm
    /// in its height as the old texture lies on the wall; the driver's
    /// door is on the nose's taper, its outline not square to the car, so
    /// its box is only its place and the tool's node its piece. Either
    /// way the box holds every face of its door and no whole face of the
    /// wall's.) As the N700S has them (decision 979).
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
    /// As `tools/texture-palette/kyushu_n700.py` reports them.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            [Door(x: 4.871...5.560, z: 1.424...3.120, crew: true), Door(x: 3.632...4.652, z: 1.373...3.231, crew: false),
             Door(x: -13.114 ... -12.083, z: 1.376...3.231, crew: false)]
        case .middle:
            [Door(x: 11.083...12.037, z: 1.375...3.232, crew: false), Door(x: -12.037 ... -11.083, z: 1.375...3.232, crew: false)]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x. `nil` if its mesh does
    /// not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DPalette {
    /// Decision 977: the Kyushu Shinkansen N700's livery, measured on a
    /// photograph of the real car in soft light (the body, the line and
    /// its gold edges on the same picture, scaled together so the body is
    /// a bright white-blue): the body's 白藍, far paler than the colour
    /// of that name in a colour chart (#C1E4E9), the line's 濃藍 and its
    /// gold. Registered by the owner's word (2026-11-25).
    public static let kyushuWhiteBlue = Map3DColor.rgb(0xD8E5EB)
    public static let kyushuNavy = Map3DColor.rgb(0x214168)
    public static let kyushuGold = Map3DColor.rgb(0x897455)
}

extension Map3DKyushuN700 {
    /// Decision 782: its set, its showcase row (eight cars) and its cars'
    /// triangles (2,812 the cab car, 2,764 the middle car: few enough to be
    /// drawn at any distance a train's model is, so no far set) and
    /// lengths.
    static let registration = Map3DTrainRegistration(
        id: "kyushuN700",
        sets: [Map3DTrainSet.kyushuN700()],
        showcase: [
            Map3DShowcase.Entry(key, "Kyushu Shinkansen N700 series", "九州新幹線 N700 系", .japan, cars: cars, fixed: true,
                                gauge: 1.435),
        ],
        triangles: 2_300...3_000, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// Decision 977: the owner's old N700 cars (``Map3DKyushuN700``), each
    /// its own length: the cab car, middle cars, the cab car turned round
    /// at the back. The ends' lamp lenses lit.
    static func kyushuN700() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DKyushuN700.key, ownLengths: true) {
            func model(_ unit: Map3DKyushuN700.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DKyushuN700.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            return Cars(head: litLenses(model(.cab), front: true), middle: model(.middle), tail: litLenses(model(.cab).turned, front: false),
                        single: nil)
        }
    }
}
