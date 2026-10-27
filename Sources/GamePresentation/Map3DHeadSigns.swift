/// Decision 436: the lit destination sign over a Taiwan Railway multiple
/// unit's windscreen, in its class's colour (the local trains' blue, the
/// Tze-Chiang's red), on each cab car close up. It is drawn with the
/// frame's boxes, not into the train models (whose shapes stay as they
/// are), where the model's own front is at the sign's height.
///
/// Only a lit strip: words (the terminus) would need a texture per train,
/// left for later (decision 436, next step).
public struct Map3DHeadSign: Equatable, Sendable {
    /// The class a train runs as, which colours its sign.
    public enum Service: Equatable, Sendable {
        /// 區間車.
        case local
        /// 自強號.
        case express

        /// The class's colour on Taiwan Railway's timetable data
        /// (`taiwan-rail-reference-clean` `data/tra_schedule_dense.json`,
        /// from TRA's open data: 區間車 `#2E6FB0`, 自強 `#C0392B`).
        public var colour: UInt32 {
            switch self {
            case .local: Map3DColor.rgb(0x2E6FB0)
            case .express: Map3DColor.rgb(0xC0392B)
            }
        }
    }

    /// The sign's middle in the model's space (+x its front, +z up): just
    /// proud of the cab's front at that height.
    public let middle: Map3DPoint
    /// +1 when the cab is at the model's front (+x), -1 at its back (a
    /// set's tail car).
    public let facing: Float
    public let service: Service

    /// The sign's size, metres, and how far below the roof its middle is.
    public static let width: Float = 1.1
    public static let height: Float = 0.22
    static let belowRoof: Float = 0.75
    /// How near the eye a cab's sign is drawn: the closest detail's
    /// reach (``Map3DCamera/closeReach``).
    public static let reach: Float = Map3DCamera.closeReach

    /// The sets whose cab cars carry a sign, and their class.
    static let services: [String: Service] = [
        "emu500": .local, "emu800": .local, "emu900": .local,
        "emu3000": .express, "taroko": .express, "puyuma": .express,
    ]

    /// Where the sign goes on `model`, the cab at its front (`facing` 1) or
    /// back (-1): at ``belowRoof`` under its top, in front of the
    /// farthest point of the cab within 0.55 m of its middle and 0.12 m of
    /// that height. `nil` for a model with nothing there.
    public static func anchor(of model: Map3DModelPack.Model, facing: Float, service: Service) -> Map3DHeadSign? {
        let height = model.maximum.z - belowRoof
        var front: Float?
        for vertex in model.vertices where abs(vertex.y) <= 0.55 && abs(vertex.z - height) <= 0.12 {
            let x = vertex.x * facing
            front = max(front ?? x, x)
        }
        guard let front else { return nil }
        return Map3DHeadSign(middle: Map3DPoint((front + 0.03) * facing, 0, height), facing: facing, service: service)
    }

    /// The signs of `models`' cab cars, by model index: each set of
    /// ``services``' head (and far head), and its tail turned the other way.
    static func anchors(in models: [Map3DModelPack.Model]) -> [Int: Map3DHeadSign] {
        var signs: [Int: Map3DHeadSign] = [:]
        var byName: [String: Int] = [:]
        for (index, model) in models.enumerated() where model.name.hasPrefix("set-") { byName[model.name] = index }
        for (key, service) in services {
            for set in [key, key + "Far"] {
                for (unit, facing) in [("head", Float(1)), ("tail", -1)] {
                    guard let index = byName["set-\(set)-\(unit)"],
                          let sign = anchor(of: models[index], facing: facing, service: service) else { continue }
                    signs[index] = sign
                }
            }
        }
        return signs
    }

    /// Each sign of a cab car in `frame` within ``reach`` of `eye`, added to
    /// its boxes: a dark board and, a little proud of it, the lit strip.
    public static func add(to frame: inout Map3DTrains.Frame, signs: [Int: Map3DHeadSign], eye: Map3DPoint) {
        guard !signs.isEmpty else { return }
        for instance in frame.instances {
            guard let sign = signs[instance.model], instance.transform.count == 16 else { continue }
            let t = instance.transform
            let x = Map3DPoint(t[0], t[1], t[2]), y = Map3DPoint(t[4], t[5], t[6]), z = Map3DPoint(t[8], t[9], t[10])
            let origin = Map3DPoint(t[12], t[13], t[14])
            func scene(_ p: Map3DPoint) -> Map3DPoint { origin + x * p.x + y * p.y + z * p.z }
            guard (scene(sign.middle) - eye).length <= reach else { continue }
            sign.draw(into: &frame.boxes, scene: scene)
        }
    }

    /// The board and its strip, the strip lit from within at night.
    func draw(into mesh: inout Map3DMesh, scene: (Map3DPoint) -> Map3DPoint) {
        // Corners in the model's space: across (+y its left) and up (+z),
        // counter-clockwise seen from in front of the cab.
        func face(_ out: Float, _ halfWidth: Float, _ halfHeight: Float) -> [Map3DPoint] {
            let x = middle.x + facing * out
            return [Map3DPoint(x, -halfWidth * facing, middle.z - halfHeight), Map3DPoint(x, halfWidth * facing, middle.z - halfHeight),
                    Map3DPoint(x, halfWidth * facing, middle.z + halfHeight), Map3DPoint(x, -halfWidth * facing, middle.z + halfHeight)]
        }
        let board = face(0, Self.width / 2, Self.height / 2).map(scene)
        mesh.addQuad(board[0], board[1], board[2], board[3], color: Map3DPalette.playerRim)
        let strip = face(0.01, Self.width / 2 - 0.06, Self.height / 2 - 0.05).map(scene)
        let first = mesh.vertices.count
        mesh.addQuad(strip[0], strip[1], strip[2], strip[3], color: service.colour)
        mesh.makeGlowing(from: first)
    }
}
