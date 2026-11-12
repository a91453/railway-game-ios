import Foundation
import GameCore

/// Decision 701: the collection's aircraft and airports up close, in the
/// train garage's stage (decisions 434 and 632): the four aircraft of
/// decision 698's studies nose to nose on an apron, and the two airports
/// their producer lays out as scenes (`tools/airport-aircraft-studies/produce.py`,
/// `assembly`): the city terminal with its apron, taxiway and runway and
/// three aircraft at their stands, and the island terminal with one.
///
/// The studies are not in the 3D map's model pack (decision 699 brings them
/// to the map), so the stage draws them as part of its ground: each model's
/// triangles stood in place once, with their own colours and night lamps.
/// Nothing here changes a recipe: it only reads `Map3DAircraftStudies` and
/// `Map3DAirportStudies`.
///
/// Laid out in the studies' own space (x forward, y left, z up, metres) and
/// then turned to the scene's (x, y up, z): a point (x, y, z) goes to
/// (x, z, −y).
public enum Map3DAirShowcase {
    public typealias Exhibit = Map3DCollectionShowcase.Exhibit

    /// The ground round the aprons: the studies' grass.
    static let groundColour = Map3DStudyColor.grass
    /// The clear apron between two aircraft's wing tips.
    public static let wingGap: Float = 8
    /// How far a boarding bridge's cab stands off the door it serves.
    static let bridgeStandOff: Float = 1.9

    /// An aircraft stood on the stage: where its middle is on the ground
    /// and the way its nose points, in the scene's space.
    public struct Parked: Equatable, Sendable {
        public let kind: Map3DAircraftStudies.Kind
        public let middle: Map3DPoint
        public let forward: Map3DPoint
        public var length: Float { Map3DAircraftStudies.dimensions(kind).length }
        public var wingspan: Float { Map3DAircraftStudies.dimensions(kind).wingspan }
        public var height: Float { Map3DAircraftStudies.dimensions(kind).height }
    }

    /// The four aircraft's middles across the apron (the studies' y),
    /// smallest first, each ``wingGap`` clear of the one before.
    static func rowOffsets() -> [Float] {
        var offsets: [Float] = [], next: Float = 0
        var before: Float?
        for kind in Map3DAircraftStudies.Kind.allCases {
            let span = Map3DAircraftStudies.dimensions(kind).wingspan
            if let before { next -= before / 2 + wingGap + span / 2 }
            offsets.append(next)
            before = span
        }
        return offsets
    }

    /// The aircraft `exhibit` shows, in the order the camera's close view
    /// can be asked for them; empty for the collection's other pages.
    public static func parked(_ exhibit: Exhibit) -> [Parked] {
        switch exhibit {
        case .ferries, .cableways:
            return []
        case .aircraft:
            // Noses level at x 0, pointing +x, as the ferries' bows.
            return zip(Map3DAircraftStudies.Kind.allCases, rowOffsets()).map { kind, y in
                Parked(kind: kind, middle: scene(-Map3DAircraftStudies.dimensions(kind).length / 2, y, 0), forward: Map3DPoint(1, 0, 0))
            }
        case .cityAirport:
            return cityStands.map { Parked(kind: $0.kind, middle: scene($0.x, $0.y, 0), forward: Map3DPoint(-1, 0, 0)) }
        case .islandAirport:
            return [Parked(kind: .commuter19, middle: scene(26, -4, 0), forward: scene(0, 1, 0))]
        }
    }

    /// The city airport's three stands, as the producer's scene: two
    /// narrow-body jets nose-in at the second and third boarding bridges
    /// (each door ``bridgeStandOff`` off its bridge's cab), and the
    /// 70-seat turboprop on a remote stand with boarding stairs.
    static var cityStands: [(kind: Map3DAircraftStudies.Kind, palette: Int?, x: Float, y: Float)] {
        let door = Map3DAircraftStudies.metadata(.narrowJet).door
        let bridges = Map3DAirportStudies.connections(.cityTerminal).jetbridges
        return [
            (.narrowJet, nil, bridges[1].exit.x + door.x, bridges[1].exit.y + door.y + bridgeStandOff),
            (.narrowJet, 2, bridges[2].exit.x + door.x, bridges[2].exit.y + door.y + bridgeStandOff),
            (.regional70, nil, 78, 84),
        ]
    }

    /// A point of the studies' space in the scene's.
    static func scene(_ x: Float, _ y: Float, _ z: Float) -> Map3DPoint { Map3DPoint(x, z, -y) }

    /// What `exhibit` shows, low and high corners in the scene's space
    /// (y the ground's 0 to its tallest), `nil` for the other pages.
    static func extent(_ exhibit: Exhibit) -> (low: Map3DPoint, high: Map3DPoint)? {
        // x0, x1, y0, y1 in the studies' space, and the height.
        let box: (Float, Float, Float, Float, Float)
        switch exhibit {
        case .ferries, .cableways:
            return nil
        case .aircraft:
            let pad = apron()
            // The floodlight masts stand a little over the largest fin.
            box = (pad.x0, pad.x1, pad.y0, pad.y1, 18.4)
        case .cityAirport:
            box = (-104, 184, -111, 130, 36)
        case .islandAirport:
            box = (-31, 111, -91, 91, 12)
        }
        return (Map3DPoint(box.0, 0, -box.3), Map3DPoint(box.1, box.4, -box.2))
    }

    /// The aircraft page's apron, in the studies' space: past the longest
    /// aircraft's tail and the outer wing tips.
    static func apron() -> (x0: Float, x1: Float, y0: Float, y1: Float) {
        let kinds = Map3DAircraftStudies.Kind.allCases, offsets = rowOffsets()
        let longest = kinds.map { Map3DAircraftStudies.dimensions($0).length }.max() ?? 0
        let firstSpan = Map3DAircraftStudies.dimensions(kinds[0]).wingspan
        let lastSpan = Map3DAircraftStudies.dimensions(kinds[kinds.count - 1]).wingspan
        return (-longest - 16, 14, (offsets.last ?? 0) - lastSpan / 2 - 12, firstSpan / 2 + 12)
    }

    // MARK: - The mesh

    /// The models stood in place, in the studies' space.
    struct Stage {
        private(set) var vertices: [Map3DVertex] = []

        /// `model` turned `degrees` (a multiple of 90) about the upright
        /// axis and moved to (x, y), as the producer's `place`.
        mutating func place(_ model: Map3DModelPack.Model, x: Float = 0, y: Float = 0, degrees: Int = 0) {
            let turn: (c: Float, s: Float) = switch ((degrees % 360) + 360) % 360 {
            case 90: (0, 1)
            case 180: (-1, 0)
            case 270: (0, -1)
            default: (1, 0)
            }
            vertices.reserveCapacity(vertices.count + model.vertices.count)
            for v in model.vertices {
                var moved = v
                moved.x = x + turn.c * v.x - turn.s * v.y
                moved.y = y + turn.s * v.x + turn.c * v.y
                moved.nx = turn.c * v.nx - turn.s * v.ny
                moved.ny = turn.s * v.nx + turn.c * v.ny
                vertices.append(moved)
            }
        }

        /// What the scene adds between its models: paint, pavement, masts.
        mutating func add(_ build: (inout Map3DStudyMesh) -> Void) {
            var mesh = Map3DStudyMesh()
            build(&mesh)
            vertices += mesh.model(named: "").vertices
        }

        /// Turned to the scene's space, one triangle to three vertices.
        func mesh() -> Map3DMesh {
            let turned = vertices.map { v in
                Map3DVertex(Map3DAirShowcase.scene(v.x, v.y, v.z), normal: Map3DAirShowcase.scene(v.nx, v.ny, v.nz), color: v.color, u: v.u, v: v.v,
                            layer: v.layer)
            }
            return Map3DMesh(vertices: turned, indices: (0..<UInt32(turned.count)).map { $0 })
        }
    }

    /// Everything `exhibit` stands on its ground, in the scene's space;
    /// empty for the collection's other pages.
    public static func mesh(_ exhibit: Exhibit, far: Bool = false) -> Map3DMesh {
        guard exhibit.isAir else { return Map3DMesh() }
        // Made once: the stage asks again each time its near or far
        // models are chosen.
        let key = exhibit.rawValue + (far ? "-far" : "")
        if let made = Made.shared.mesh(key) { return made }
        var stage = Stage()
        switch exhibit {
        case .ferries, .cableways: break
        case .aircraft: aircraftRow(&stage, far)
        case .cityAirport: cityAirport(&stage, far)
        case .islandAirport: islandAirport(&stage, far)
        }
        let mesh = stage.mesh()
        Made.shared.keep(mesh, key)
        return mesh
    }

    /// The meshes made so far, by exhibit and near or far.
    private final class Made: @unchecked Sendable {
        static let shared = Made()
        private let lock = NSLock()
        private var meshes: [String: Map3DMesh] = [:]

        func mesh(_ key: String) -> Map3DMesh? {
            lock.lock()
            defer { lock.unlock() }
            return meshes[key]
        }

        func keep(_ mesh: Map3DMesh, _ key: String) {
            lock.lock()
            meshes[key] = mesh
            lock.unlock()
        }
    }

    private static func aircraftRow(_ stage: inout Stage, _ far: Bool) {
        let c = Map3DStudyColor.self
        let kinds = Map3DAircraftStudies.Kind.allCases, offsets = rowOffsets(), pad = apron()
        stage.add { m in
            m.pavement(pad.x0, pad.x1, pad.y0, pad.y1, c.deck, joints: far ? nil : 12)
            for (kind, y) in zip(kinds, offsets) {
                // The stand's lead-in line and the bar its nose wheel stops at.
                m.box((pad.x0 + 6) / 2, y, 0.09, 6 - pad.x0, 0.30, 0.015, c.warm)
                m.box(-Map3DAircraftStudies.shape(kind).noseGear.s, y, 0.09, 0.4, 3, 0.015, c.warm)
            }
            // A floodlight mast at the apron's edge behind each gap.
            for (a, b) in zip(offsets, offsets.dropFirst()) {
                m.mast(pad.x0 + 3, (a + b) / 2, 18)
            }
            m.box((pad.x0 + pad.x1) / 2, pad.y0 + 1, 0.09, pad.x1 - pad.x0 - 2, 0.3, 0.015, c.red)
        }
        for (kind, y) in zip(kinds, offsets) {
            stage.place(Map3DAircraftStudies.model(kind, far: far), x: -Map3DAircraftStudies.dimensions(kind).length / 2, y: y)
        }
    }

    private static func cityAirport(_ stage: inout Stage, _ far: Bool) {
        let c = Map3DStudyColor.self
        stage.place(Map3DAirportStudies.model(.cityTerminal, far: far))
        let stands = cityStands
        stage.add { m in
            m.pavement(14, 118, -110, 130, c.deck, joints: far ? nil : 12)
            for y: Float in [-22, 100] {
                m.box(143, y, 0, 20, 12, 0.08, c.taxi)
                m.box(143, y, 0.09, 20, 0.36, 0.015, c.warm)
            }
            for y: Float in [-88, -44, 0, 44, 88] {
                m.mast(17, y, 18)
            }
            m.box(116, 10, 0.09, 0.3, 236, 0.015, c.red)
            for stand in stands {
                let nose = stand.x - Map3DAircraftStudies.dimensions(stand.kind).length / 2
                m.box(nose + 20, stand.y, 0.09, 40, 0.30, 0.015, c.warm)
                m.box(nose + Map3DAircraftStudies.shape(stand.kind).noseGear.s, stand.y, 0.09, 0.4, 3, 0.015, c.warm)
            }
        }
        // The parallel taxiway and a stretch of runway, its threshold first.
        for i in 0..<8 { stage.place(Map3DAirportStudies.model(.taxiway, far: far), x: 127, y: -95 + Float(i) * 30, degrees: 90) }
        for i in 0..<4 {
            stage.place(Map3DAirportStudies.model(i == 0 ? .runwayEnd : .runway, far: far), x: 168, y: -80 + Float(i) * 60, degrees: 90)
        }
        for stand in stands {
            stage.place(Map3DAircraftStudies.model(stand.kind, far: far, palette: stand.palette), x: stand.x, y: stand.y, degrees: 180)
        }
        stage.place(Map3DAirportStudies.model(.tug, far: far), x: 33.5, y: stands[0].y)
        stage.place(Map3DAirportStudies.model(.fuelTruck, far: far), x: 52, y: 4, degrees: 90)
        stage.place(Map3DAirportStudies.model(.baggageCart, far: far), x: 64, y: -42)
        stage.place(Map3DAirportStudies.model(.boardingStairs, far: far), x: 78 - 9.0 + 3.2, y: 84 - 5.6, degrees: 90)
    }

    private static func islandAirport(_ stage: inout Stage, _ far: Bool) {
        let c = Map3DStudyColor.self
        stage.place(Map3DAirportStudies.model(.islandTerminal, far: far))
        stage.add { m in
            m.pavement(6, 50, -28, 28, c.deck, joints: far ? nil : 10)
            m.box(26, -2, 0.09, 0.30, 30, 0.015, c.warm)
            for y: Float in [-22, 22] {
                m.mast(8, y, 10)
            }
        }
        stage.place(Map3DAirportStudies.model(.taxiway, far: far), x: 65)
        for (i, piece) in [(Map3DAirportStudies.Kind.runwayEnd, 90), (.runway, 90), (.runwayEnd, 270)].enumerated() {
            stage.place(Map3DAirportStudies.model(piece.0, far: far), x: 95, y: -60 + Float(i) * 60, degrees: piece.1)
        }
        stage.place(Map3DAircraftStudies.model(.commuter19, far: far), x: 26, y: -4, degrees: 90)
        stage.place(Map3DAirportStudies.model(.baggageCart, far: far), x: 14, y: -16)
        stage.place(Map3DAirportStudies.model(.windsock, far: far), x: 76, y: 40)
        stage.place(Map3DAirportStudies.model(.papi, far: far), x: 76, y: -70, degrees: 90)
        for i in 0..<5 { stage.place(Map3DAirportStudies.model(.fence, far: far), x: -29.8, y: -16 + Float(i) * 8, degrees: 90) }
    }
}

private extension Map3DStudyMesh {
    /// A sealed plate with its slab joints, as the studies' own.
    mutating func pavement(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ color: UInt32, joints: Float?) {
        let h: Float = 0.08
        box((x0 + x1) / 2, (y0 + y1) / 2, 0, x1 - x0, y1 - y0, h, color)
        guard let joints else { return }
        var k = (x0 / joints).rounded(.up) * joints
        while k < x1 - 0.01 {
            if k > x0 + 0.01 { box(k, (y0 + y1) / 2, h + 0.004, 0.14, y1 - y0 - 0.2, 0.006, Map3DStudyColor.joint) }
            k += joints
        }
        k = (y0 / joints).rounded(.up) * joints
        while k < y1 - 0.01 {
            if k > y0 + 0.01 { box((x0 + x1) / 2, k, h + 0.004, x1 - x0 - 0.2, 0.14, 0.006, Map3DStudyColor.joint) }
            k += joints
        }
    }

    /// An apron floodlight mast, its three lamps toward +x.
    mutating func mast(_ x: Float, _ y: Float, _ height: Float) {
        let c = Map3DStudyColor.self
        cylinder(Map3DPoint(x, y, 0), Map3DPoint(x, y, height), 0.22, c.metal, sides: 6, endRadius: 0.14)
        box(x, y, height, 1.0, 2.6, 0.35, c.metal)
        for dy: Float in [-0.8, 0, 0.8] { box(x + 0.3, y + dy, height - 0.22, 0.5, 0.55, 0.22, c.lamp, glow: true) }
    }
}
