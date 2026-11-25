import Foundation

/// Decision 988: the Taiwan High Speed Rail 700T, the owner's old 700
/// series cars (SwiftRailMac's 7a188937, the cab car, and e33da7fa, the
/// middle car: a long nose, two bogies and eight wheels) painted as the
/// real train by `tools/texture-palette/thsr_700t.py` and written here by
/// `tools/train-models/glb_to_swift.py` (``encoded``).
///
/// It takes the place of the 700T the recipe drew
/// (``Map3DTrainShapeRefresh``, decisions 408 and 422, whose cab car was
/// 25.2 m, shorter than the real one's 27 m, and its far set): the
/// high-speed trains' set, `highSpeed`.
///
/// The old game drew every car 21 m long and 2.80 m wide; here they are
/// the real cars' size: 25 m from coupling to coupling, the cab car 27 m,
/// 3.38 m wide and 3.65 m to the roof, on the 1,435 mm gauge. The cab
/// car's nose and doors are scaled as the middle car's are, its nose given
/// no stretch of its own and no other shape (the owner's rule), and its
/// straight body is 2 m longer, with fourteen windows at the middle car's
/// spacing where the old car had twelve (the old cab car's windows and
/// doors were already the middle car's size, so scaling it whole would
/// have made them 8 % larger than the cars behind it).
///
/// The old car wore a white and blue livery; the paint is the real
/// 700T's, measured on photographs (Wikimedia Commons): a white body, a
/// black line over an orange band under the windows, the band running
/// through the doors to the nose, deep from the skirt up before the front
/// door, its top falling toward the nose's tip and round it; a black
/// piece leaning back over the skirt behind the front door, and the black
/// line starting in a point two metres behind it; and on the nose a black
/// mask over the windscreen and the lamps, from the lamps up to the
/// windscreen's top (the old car's were two patches with white between
/// them; the owner, 2026-11-25). The driver's door of
/// the old car is not drawn (the 700T's cab car has only its passenger
/// doors). The old game had no car under the pantograph: it is the middle
/// car with a single-arm pantograph, its insulator cover and its two wind
/// shields written by the tool. No company mark, lettering or number is
/// drawn.
public enum Map3DTHSR700T {
    /// The cars the game draws: the cab car, the middle car and the car
    /// under the pantograph.
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "thsr-700t-cab"
        case middle = "thsr-700t-middle"
        case pantograph = "thsr-700t-pantograph"

        public var isCab: Bool { self == .cab }
    }

    /// The key of its set (``Map3DTrainSet``): the high-speed trains'.
    public static let key = "highSpeed"

    /// The key the recipe's far set had (decision 422), which now names
    /// this train (``Map3DTrainSet/named(_:)``).
    static let formerFarKey = "highSpeedFar"

    /// How many cars its trains have.
    public static let cars = 12

    /// A middle car's length (the pantograph car's too), coupling to
    /// coupling, metres.
    public static let pitch: Float = 25

    /// The cab car's length, its nose's tip to its coupling, metres: the
    /// real car's.
    public static let cabLength: Float = 27

    /// `unit`'s length, metres.
    public static func length(_ unit: Unit) -> Float { unit.isCab ? cabLength : pitch }

    /// How far short of its coupling a car's hood ends, metres. The old
    /// cars' bodies end 0.30 m short of their couplings, as the real cars'
    /// do, with only a gangway 1.2 m wide between them: 0.6 m of open air
    /// beside it. The real train covers it with a hood of the body's own
    /// outline (photographs), and so does the tool, as the N700S's does
    /// (``Map3DN700S``, decision 979): the end wall's outline drawn out to
    /// this far from the coupling, white over the skirt's grey, the band
    /// and the line not carried across it.
    public static let hoodGap: Float = 0.02

    /// What a car may have, triangles (1,999 the cab car, 1,360 the middle
    /// car, 1,444 the car under the pantograph: a twelve-car train some
    /// 17,800, few enough to be drawn at any distance a train's model is,
    /// so no far set).
    static let triangles = 1_200...2_000

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, orange, black,
    /// skirt, glass, dark, headlamp, taillamp, frame. The body's white and
    /// the band's orange are the 700T's
    /// (``Map3DTrainShapeRefresh/highSpeedBodyColor`` and
    /// ``Map3DTrainShapeRefresh/highSpeedBandColor``, the colour the teal
    /// paint of decision 983 swaps), the line black, the skirts a darker
    /// grey than the door frames' steel, the trains' glass, the dark
    /// bogies, gangways and pantograph, and the lamps.
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, Map3DTrainShapeRefresh.highSpeedBandColor, Map3DPalette.dark,
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
    public struct Door: Sendable, Equatable {
        /// Along the car, metres from its middle, the cab's end positive.
        public let x: ClosedRange<Float>
        /// Over the rail, metres.
        public let z: ClosedRange<Float>

        /// Whether `point` is on this door, on the side wall its `y` is on.
        public func contains(_ point: Map3DPoint, margin: Float = 0.002) -> Bool {
            abs(point.y) > 1.5 && point.x >= x.lowerBound - margin && point.x <= x.upperBound + margin
                && point.z >= z.lowerBound - margin && point.z <= z.upperBound + margin
        }
    }

    /// `unit`'s doors, from its front to its back; each is on both sides.
    /// As `tools/texture-palette/thsr_700t.py` reports them.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            [Door(x: 4.726...5.481, z: 1.38...3.07), Door(x: -10.778 ... -10.036, z: 1.38...3.07)]
        case .middle, .pantograph:
            [Door(x: 11.113...11.855, z: 1.38...3.07), Door(x: -11.851 ... -11.11, z: 1.38...3.07)]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x; the pantograph car's
    /// pantograph over its back half. `nil` if its mesh does not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DTrainSet {
    /// Decision 988: the owner's old 700 series cars as the 700T
    /// (``Map3DTHSR700T``): the cab car at the front and turned round at
    /// the back, middle cars between, the pantograph car fourth and ninth
    /// of twelve (as the real train's, and decision 408's), the back
    /// half's cars turned round so the two pantographs face each other.
    /// The front's white lamps and the back's red ones lit (``litEnd(_:leading:)``).
    static func highSpeed700T() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DTHSR700T.key, pantographCars: [3, 8], ownLengths: true) {
            func model(_ unit: Map3DTHSR700T.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DTHSR700T.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            let cab = model(.cab), middle = model(.middle), pantograph = model(.pantograph)
            return Cars(head: litEnd(cab, leading: true), middle: middle, tail: litEnd(cab.turned, leading: false), single: nil,
                        pantograph: pantograph, middleBack: middle.turned, pantographBack: pantograph.turned)
        }
    }

    /// A cab car whose nose has a white lamp and a red one side by side
    /// (the old 700 series cars'), with the lamps a train shows at that
    /// end lit: the white ones when the car leads, the red ones when it
    /// is last. The others stay as unlit lenses.
    static func litEnd(_ model: Map3DModelPack.Model, leading: Bool) -> Map3DModelPack.Model {
        let lamp = leading ? Map3DTrainStyle.headlamp : Map3DPalette.lantern
        var vertices = model.vertices
        for start in stride(from: 0, to: vertices.count, by: 3) where vertices[start].color == lamp {
            for i in start..<start + 3 { vertices[i].layer = Map3DVertex.glowing }
        }
        return Map3DModelPack.Model(name: model.name, vertices: vertices, minimum: model.minimum, maximum: model.maximum)
    }
}
