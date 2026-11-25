import Foundation

/// Decision 979: the N700S, the owner's old cars (SwiftRailMac's c264b30b,
/// the cab car, 2cf2255b, the middle car, and 8d903762, the car under the
/// pantograph with its cover and shields: a long nose, a white body, two
/// blue lines under the windows, grey skirts, two bogies and eight
/// wheels), their texture cut into faces of the game's palette colours by
/// `tools/texture-palette/n700s.py` and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// It takes the place of the N700S-G (decisions 408 and 422: the same
/// author's body with nine to thirteen thousand triangles a car, cut to
/// five to seven thousand, and its far set): the train pack's second
/// high-speed train, the odd-numbered high-speed trains once the pack is
/// unlocked (``Map3DTrainSet/variant(of:number:locked:)``).
///
/// The old game drew every car 20.5 m long and 2.80 m wide; here they are
/// the real cars' size: 25 m from coupling to coupling (the cab car
/// 27.35 m), 3.36 m wide and 3.60 m to the roof, on the 1,435 mm gauge.
/// The old game made the cab car as long as the others by pressing its
/// saloon short (twelve windows 0.92 m apart, doors 0.65 m wide, at the
/// scale that makes the middle cars' the real cars' own: windows 0.52 m
/// wide and 1.04 m apart, doors 0.74 m). Here the cab car has the middle
/// cars' scale, so its nose is the old car's in the same proportion, given
/// no stretch of its own and no other shape (the owner's rule), and the
/// 2.35 m it lacks is given back to its saloon as the real first car has
/// it (``cabWindows``, ``cabWindowPitch``): one more window, the windows
/// and doors as wide as the middle cars'. No company mark, lettering or
/// number is drawn.
public enum Map3DN700S {
    /// The cars the game draws: the cab car, the middle car and the car
    /// under the pantograph.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "n700s-cab"
        case middle = "n700s-middle"
        case pantograph = "n700s-pantograph"

        public var isCab: Bool { self == .cab }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "n700s"

    /// The keys the N700S-G's sets had (decisions 408 and 422), which now
    /// name this train (``Map3DTrainSet/named(_:)``).
    static let formerKeys = ["n700sG", "n700sGFar"]

    /// How many cars its trains have.
    public static let cars = 12

    /// A middle car's length (the pantograph car's too), coupling to
    /// coupling, metres.
    public static let pitch: Float = 25

    /// The cab car's length, its nose's tip to its coupling, metres: the
    /// real car's.
    public static let cabLength: Float = 27.35

    /// The cab car's saloon windows on each side: the real first car's
    /// thirteen rows of seats.
    public static let cabWindows = 13

    /// From one of the cab car's windows to the next, metres: the real
    /// cab cars' seat pitch (1,023 mm; the middle cars' is 1,040 mm).
    public static let cabWindowPitch: Float = 1.023

    /// The cab car's nose, its tip to where its side walls are the full
    /// width up to the roof, metres: the old car's 7.41 at the scale the
    /// middle cars have (25 m for the old 21 m), 0.99 of what the width's
    /// scale would make it.
    public static let noseLength: Float = 7.41 * 12.5 / 10.501

    /// How far short of its coupling a car's hood ends, metres. The old
    /// cars' bodies end 0.30 m short of their couplings, as the real cars'
    /// do, with only a gangway 1.2 m wide between them: 0.6 m of open air
    /// beside it, where the game's own
    /// cars leave 0.24 m (the owner: the first car and the second too far
    /// apart). The real train covers it with a hood of the body's own
    /// outline, and so does the tool: the end wall's outline drawn out to
    /// this far from the coupling, white over the skirt's grey, the blue
    /// lines not carried across it.
    public static let hoodGap: Float = 0.02

    /// `unit`'s length, metres.
    public static func length(_ unit: Unit) -> Float { unit.isCab ? cabLength : pitch }

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, navy, grey, glass,
    /// dark, headlamp, taillamp. The body's white is the 700T's
    /// (``Map3DTrainShapeRefresh/highSpeedBodyColor``), the lines the
    /// real train's blue (``Map3DPalette/shinkansenBlue``, the one new
    /// colour), the skirts steel, the trains' glass, the dark bogies,
    /// gangways and floor, and the lamps.
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, Map3DPalette.shinkansenBlue, Map3DPalette.steel, Map3DTrainStyle.glass,
        Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
    ]

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 3

    /// A door of a car: where its leaf, with its frame, its window and the
    /// piece of the blue lines across it, is on each of the car's two side
    /// walls. The mesh is cut along this outline, so every triangle is
    /// wholly a door's or wholly the wall's (the tool writes each door as
    /// a node of its own too): the doors can be moved apart from the wall,
    /// to open at a station, without the mesh being cut again. (A
    /// passenger door's outline is this box; the driver's door is on the
    /// nose's taper, its outline not square to the car, so its box is
    /// only its place and the tool's node its piece.)
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
    /// As `tools/texture-palette/n700s.py` reports them.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            [Door(x: 4.998...5.498, z: 1.341...2.791, crew: true), Door(x: 3.987...4.727, z: 1.272...2.906, crew: false),
             Door(x: -10.976 ... -10.236, z: 1.252...2.982, crew: false)]
        case .middle:
            [Door(x: 10.141...10.876, z: 1.265...2.954, crew: false), Door(x: -9.155 ... -8.414, z: 1.253...2.980, crew: false)]
        case .pantograph:
            [Door(x: 11.334...12.077, z: 1.265...2.953, crew: false), Door(x: -9.155 ... -8.416, z: 1.253...2.980, crew: false)]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x; the pantograph car's
    /// cover over its back half. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DPalette {
    /// Decision 979: the blue of the lines along the Tokaido Shinkansen's
    /// white trains, as the owner's old N700S texture has it (#203552) and
    /// within what photographs of the real trains measure (#0D2852 to
    /// #30426C, by the light): less purple than the EMU900's navy.
    public static let shinkansenBlue = Map3DColor.rgb(0x203552)
}

extension Map3DN700S {
    /// Decision 782: its set, its showcase row (twelve cars) and its cars'
    /// triangles (4,166 the cab car, 2,265 the middle car, 2,495 the car
    /// under the pantograph: a twelve-car train some 31,000, few enough
    /// to be drawn at any distance a train's model is, so no far set) and
    /// lengths.
    static let registration = Map3DTrainRegistration(
        id: "n700s",
        sets: [Map3DTrainSet.n700s()],
        showcase: [
            Map3DShowcase.Entry(key, "N700S", "N700S", .highSpeed, cars: cars),
        ],
        triangles: 2_100...4_300, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// Decision 979: the owner's old N700S cars (``Map3DN700S``): the cab
    /// car at the front and turned round at the back, middle cars between,
    /// the pantograph car fourth and ninth of twelve (as the N700S-G's
    /// were, decision 408), the back half's cars turned round so the two
    /// pantograph covers face each other. The nose has a white lamp and a
    /// red one side by side: the white ones are lit on the car that leads
    /// and the red ones on the last car, the others left as unlit lenses
    /// (``litEnd(_:leading:)``, the 700T's; ``litLenses(_:front:)`` would
    /// light both at each end).
    static func n700s() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DN700S.key, pantographCars: [3, 8], ownLengths: true) {
            func model(_ unit: Map3DN700S.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DN700S.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            let cab = model(.cab), middle = model(.middle), pantograph = model(.pantograph)
            return Cars(head: litEnd(cab, leading: true), middle: middle, tail: litEnd(cab.turned, leading: false), single: nil,
                        pantograph: pantograph, middleBack: middle.turned, pantographBack: pantograph.turned)
        }
    }
}
