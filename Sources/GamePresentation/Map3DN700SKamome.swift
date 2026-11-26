import Foundation

/// Decision 998 (continued): the Nishi-Kyushu Shinkansen's N700S series
/// 8000, the "Kamome", in its own livery: the owner's old Kamome cars
/// (SwiftRailMac's 54c3717d, the cab car, 54d4d264, the middle car, and
/// 44c98270, the car under the pantograph), cut by the local studio into
/// faces of the game's palette colours (`railway-assets-private-2`
/// `game-art-previews/docs/art/n700s-kamome-2026-11/revision-1`, its
/// `tools/build.py`) and written here by `tools/train-models/glb_to_swift.py`
/// (``encoded``).
///
/// The same body as the Tokaido N700S (``Map3DN700S``, decision 979), at
/// the real cars' size: 25 m from coupling to coupling (the cab car 27.35 m,
/// one window more than the old one, eleven a side, and its nose the old
/// one's shape), 3.36 m wide and 3.60 m to the roof, on the 1,435 mm gauge.
/// A white body, a red skirt and nose foot, one thin red line under the
/// windows (5.9 cm, broken at each door) and a curved one along the nose,
/// a black cab mask, the windows' corners cut off as the real ones are
/// rounded. No lettering, swallow mark, company mark or number is drawn.
/// Each coupled end has a hood of the body's outline (white over the red
/// skirt), its mouth a shallow V seen from above, so two cars turned up to
/// 4 degrees to each other on a curve keep their hoods apart; only the
/// couplers' tips meet at the joint. Each door is a node of its own in the
/// studio's GLB and a run of triangles here (``doors(_:)``).
public enum Map3DN700SKamome {
    /// The cars the game draws: the cab car, the middle car and the car
    /// under the pantograph (its pantograph and cover at its back, -x).
    public enum Unit: String, CaseIterable, Sendable {
        case cab = "n700s-kamome-cab"
        case middle = "n700s-kamome-middle"
        case pantograph = "n700s-kamome-pantograph"

        public var isCab: Bool { self == .cab }
        public var pitch: Float { isCab ? 27.35 : 25 }
    }

    /// The key of its set (``Map3DTrainSet``).
    public static let key = "n700sKamome"

    /// How many cars its trains have: the real six.
    public static let cars = 6

    /// The colours of the mesh's palette indices, in the order
    /// `glb_to_swift.py --materials` gave them: white, red, grey, glass,
    /// dark, headlamp, taillamp, door. The body's white is the N700S's (the
    /// 700T's, ``Map3DTrainShapeRefresh/highSpeedBodyColor``), the skirt and
    /// the lines the old red commuter's deep red (``Map3DPalette/trainRed``,
    /// within what photographs of the real skirt measure, #861E25 to
    /// #8B1A16), the door frames and the pantograph steel, the trains'
    /// glass, the dark cab mask, bogies, couplers and hoods' mouths, and the
    /// lamps: no new colour. The doors are the body's white again, kept as
    /// their own index so a door's faces can be told from the wall's.
    static let meshPalette: [UInt32] = [
        Map3DTrainShapeRefresh.highSpeedBodyColor, Map3DPalette.trainRed, Map3DPalette.steel, Map3DTrainStyle.glass,
        Map3DPalette.dark, Map3DTrainStyle.headlamp, Map3DPalette.lantern, Map3DTrainShapeRefresh.highSpeedBodyColor,
    ]

    /// The palette index of the glass: its faces, and only they, are the
    /// windows the game lights at night and mirrors the sky in.
    static let glassIndex = 3

    /// A door of a car (``Map3DCarDoor``): its frame, its panel and the
    /// window in it, on one of the two side walls, and its run of the
    /// model's triangles (the GLB's node `…-door-left-N` or `…-door-right-N`).
    public typealias Door = Map3DCarDoor

    /// `unit`'s doors, from its front to its back, the left wall's before
    /// the right's at each place. As the studio's `report.json` gives them
    /// (each node's outline, `first` and `triangles`). The driver's door
    /// is on the nose's taper, its outline not square to the car, so its
    /// box is only its place and its triangles its piece.
    public static func doors(_ unit: Unit) -> [Door] {
        switch unit {
        case .cab:
            [Door(x: 5.248...5.799, z: 1.327...2.75, crew: true, side: 1, left: 2879..<2959),
             Door(x: 5.248...5.799, z: 1.327...2.75, crew: true, side: -1, right: 3126..<3258),
             Door(x: 4.326...5.035, z: 1.303...2.926, side: 1, left: 2959..<3030),
             Door(x: 4.326...5.035, z: 1.304...2.926, side: -1, right: 3258..<3349),
             Door(x: -10.982 ... -10.183, z: 1.253...3.052, side: 1, left: 3030..<3126),
             Door(x: -10.983 ... -10.184, z: 1.253...3.052, side: -1, right: 3349..<3448)]
        case .middle:
            [Door(x: 8.71...9.477, z: 1.253...3.052, side: 1, left: 3095..<3189),
             Door(x: 8.71...9.477, z: 1.253...3.052, side: -1, right: 3267..<3357),
             Door(x: -11.824 ... -11.027, z: 1.252...3.058, side: 1, left: 3189..<3267),
             Door(x: -11.824 ... -11.027, z: 1.252...3.058, side: -1, right: 3357..<3447)]
        case .pantograph:
            [Door(x: 11.235...12.032, z: 1.265...3.06, side: 1, left: 3255..<3329),
             Door(x: 11.168...11.965, z: 1.265...3.06, side: -1, right: 3409..<3483),
             Door(x: -11.99 ... -11.194, z: 1.265...3.06, side: 1, left: 3329..<3409),
             Door(x: -11.99 ... -11.194, z: 1.265...3.06, side: -1, right: 3483..<3567)]
        }
    }

    /// `unit`'s car, its cab (if it has one) at +x. `nil` if its mesh does
    /// not decode.
    public static func model(_ unit: Unit) -> Map3DModelPack.Model? {
        guard let text = encoded[unit.rawValue], let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters) else { return nil }
        return Map3DRedCommuter.decodedMesh([UInt8](data), named: unit.rawValue, palette: meshPalette, glass: glassIndex)
    }
}

extension Map3DN700SKamome {
    /// Decision 782: its set, its showcase row (six cars) and its cars'
    /// triangles (3,448 the cab car, 3,447 the middle car, 3,567 the car
    /// under the pantograph: a six-car train some 21,000, few enough to be
    /// drawn at any distance a train's model is, so no far set) and
    /// lengths.
    static let registration = Map3DTrainRegistration(
        id: "n700sKamome",
        sets: [Map3DTrainSet.n700sKamome()],
        showcase: [
            Map3DShowcase.Entry(key, "Nishi-Kyushu Shinkansen N700S Kamome", "西九州新幹線 N700S かもめ", .japan, cars: cars,
                                fixed: true, gauge: 1.435),
        ],
        triangles: 3_400...3_600, length: 24.9...27.4)
}

extension Map3DTrainSet {
    /// Decision 998 (continued): the Kamome's six cars as the real train
    /// runs them (``Map3DN700SKamome``): the cab car at the front and
    /// turned round at the back, the pantograph car second and fifth, the
    /// back half's cars turned round so the two pantographs face each
    /// other, as the N700S's (decision 979). The white lamps lit on the
    /// car that leads and the red ones on the last car
    /// (``litEnd(_:leading:)``).
    static func n700sKamome() -> Map3DTrainSet {
        Map3DTrainSet(key: Map3DN700SKamome.key, pantographCars: [1, 4], ownLengths: true) {
            func model(_ unit: Map3DN700SKamome.Unit) -> Map3DModelPack.Model {
                // A unit that fails to decode draws as a plain car of its
                // length rather than nothing.
                Map3DN700SKamome.model(unit)
                    ?? Map3DTrainShell(style: Map3DTrainStyle.all[0], cab: unit.isCab).model(named: unit.rawValue)
            }
            let cab = model(.cab), middle = model(.middle), pantograph = model(.pantograph)
            return Cars(head: litEnd(cab, leading: true), middle: middle, tail: litEnd(cab.turned, leading: false), single: nil,
                        pantograph: pantograph, middleBack: middle.turned, pantographBack: pantograph.turned)
        }
    }
}
