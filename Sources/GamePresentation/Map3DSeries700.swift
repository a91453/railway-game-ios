import Foundation

/// Decision 989: the 700 series in its own paint, the owner's old cars
/// (SwiftRailMac's 7a188937, the cab car, ede98f53, the cab car of the
/// other end, e33da7fa, the middle car, and 48634371, the car with one
/// door and wide windows: a long nose, a white body, a broad blue band
/// and a thin blue line under the windows, grey skirts, two bogies and
/// eight wheels), painted by `tools/texture-palette/thsr_700t.py
/// --train series700` and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// The same cars, at the same size, as the 700T's (``Map3DTHSR700T``,
/// decision 988: 25 m from coupling to coupling, the cab cars 27 m,
/// 3.38 m wide and 3.65 m to the roof, on the 1,435 mm gauge; the cab
/// cars longer by two windows at the middle car's spacing, their noses
/// given no stretch of their own), in the paint the old cars wore: where
/// the band and the line are, how wide the windows are and where the
/// band starts on the nose are measured on the old cars. Unlike the 700T
/// it has the driver's door beside the cab, a second cab car whose back
/// door is at its end, and the car with wide windows. The old game had
/// no car under the pantograph: it is the middle car with the 700T's
/// pantograph, cover and shields. No company mark, lettering or number
/// is drawn.
/// The bogies stand where the real cars' do, 3.75 m from a coupling face
/// and 17.5 m apart, and the skirts' openings are moved to them, each
/// with its bogie in its middle; the cab car's front opening, shallow and
/// narrow on the old car, is made as wide as the back one and 0.70 m high,
/// a strip of the nose's skirt left over the wheels as on the real car
/// (the owner, 2026-11-26: the wheels were not in their openings).
///
/// A train of the garage (``registration``): no line's trains are drawn
/// with it yet.
public enum Map3DSeries700 {
    /// The cars the game draws: the cab car, the other end's cab car, the
    /// middle car, the car with wide windows and the car under the
    /// pantograph.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "series-700-cab"
        case tail = "series-700-tail"
        case middle = "series-700-middle"
        case green = "series-700-green"
        case pantograph = "series-700-pantograph"

        public var isCab: Bool { self == .cab || self == .tail }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "series700"

    /// How many cars its trains have: the real train's sixteen.
    public static let cars = 16

    /// The cars under a pantograph (the fifth and the twelfth) and the
    /// cars with wide windows (the eighth, ninth and tenth), counted from
    /// 0 at the front: the real train's.
    static let pantographCars: Set<Int> = [4, 11]
    static let wideWindowCars: Set<Int> = [7, 8, 9]

    /// A car's length that is not a cab car's, coupling to coupling,
    /// metres.
    public static let pitch: Float = 25

    /// A cab car's length, its nose's tip to its coupling, metres: the
    /// real car's.
    public static let cabLength: Float = 27

    /// `unit`'s length, metres.
    public static func length(_ unit: Unit) -> Float { unit.isCab ? cabLength : pitch }

    /// What a car may have, triangles (1,881 and 1,845 the cab cars,
    /// 1,384 the middle car, 1,165 the car with wide windows, 1,468 the
    /// car under the pantograph: a sixteen-car train some 22,600, few
    /// enough to be drawn at any distance a train's model is, so no far
    /// set).
    static let triangles = 1_100...2_000

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, band, line, skirt,
    /// glass, dark, headlamp, taillamp, frame. The body's white is the
    /// 700T's (``Map3DTrainShapeRefresh/highSpeedBodyColor``), the band
    /// and the line the blue of the N700S's lines
    /// (``Map3DPalette/shinkansenBlue``, decision 979: the same railway's
    /// blue), and the skirts, the glass, the dark bogies, gangways and
    /// pantograph, the lamps and the door frames are the 700T's.
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, Map3DPalette.shinkansenBlue, Map3DPalette.shinkansenBlue,
        Map3DPalette.tankStand, Map3DTrainStyle.glass, Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern,
        Map3DPalette.steel,
    ]

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 4

    /// A door of a car: where its leaf, with its frame, its window and the
    /// piece of the band and line across it, is on each of the car's two
    /// side walls. The mesh is cut along this outline, so every triangle
    /// is wholly a door's or wholly the wall's (the tool writes each door
    /// as a node of its own too): the doors can be moved apart from the
    /// wall, to open at a station, without the mesh being cut again.
    /// SPLIT-HOTSPOTS-2: the doors every ported car shares (``Map3DCarDoor``).
    public typealias Door = Map3DCarDoor

    /// `unit`'s doors, from its front to its back; each is on both sides.
    /// As `tools/texture-palette/thsr_700t.py` reports them.
    public static func doors(_ unit: Unit) -> [Door] {
        let crew = Door(x: 5.734...6.266, z: 1.469...2.896, crew: true)
        let front = Door(x: 4.726...5.481, z: 1.38...3.07, crew: false)
        let back = Door(x: -11.851 ... -11.11, z: 1.38...3.07, crew: false)
        switch unit {
        case .cab:
            return [crew, front, Door(x: -10.778 ... -10.036, z: 1.38...3.07, crew: false)]
        case .tail:
            return [crew, front, Door(x: -13.047 ... -12.305, z: 1.38...3.07, crew: false)]
        case .middle, .pantograph:
            return [Door(x: 11.113...11.855, z: 1.38...3.07, crew: false), back]
        case .green:
            return [back]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x; the pantograph car's
    /// pantograph over its back half, the wide-windowed car's door at its
    /// back. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }

    /// Decision 782: its set, its showcase row (sixteen cars) and its
    /// cars' triangles and lengths.
    static let registration = Map3DTrainRegistration(
        id: "series700",
        sets: [Map3DTrainSet.series700()],
        showcase: [
            Map3DShowcase.Entry(key, "700 Series", "700 系", .highSpeed, cars: cars),
        ],
        triangles: triangles, length: 24.9...27.1)
}

extension Map3DTrainSet {
    /// Decision 989: the owner's old 700 series cars in their own paint
    /// (``Map3DSeries700``): the cab car at the front, the other end's cab
    /// car turned round at the back, the car under a pantograph fifth and
    /// twelfth of sixteen and the cars with wide windows eighth to tenth
    /// (as the real train's), middle cars between; the back half's middle
    /// and pantograph cars turned round, so the two pantographs face each
    /// other. The front's white lamps and the back's red ones lit.
    static func series700() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DSeries700.key, pantographCars: Map3DSeries700.pantographCars,
                      centreCars: Map3DSeries700.wideWindowCars, ownLengths: true) {
            func model(_ unit: Map3DSeries700.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DSeries700.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            let middle = model(.middle), pantograph = model(.pantograph)
            return Cars(head: litEnd(model(.cab), leading: true), middle: middle, tail: litEnd(model(.tail).turned, leading: false),
                        single: nil, pantograph: pantograph, centre: model(.green), middleBack: middle.turned,
                        pantographBack: pantograph.turned)
        }
    }
}
