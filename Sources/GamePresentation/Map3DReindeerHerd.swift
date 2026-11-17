import Foundation

/// Decision 840: a small herd of the studio's reindeer (``Map3DReindeer``)
/// by the Santa Claus village's plaza on a real-world map that holds it
/// (``Map3DWinterLights/plazas``): two standing, two grazing and one
/// pulling a visitor's wooden sled, as the village's reindeer farm keeps
/// them all year. Where they stand is worked out once, as the scene is
/// built (``Map3DScene/Builder/addReindeerHerd(frame:)``); each frame
/// draws those the camera is near.
public struct Map3DReindeerHerd: Equatable, Sendable {
    /// One reindeer: its model, where its feet are and the way its +x
    /// (its head) faces.
    public struct Placement: Equatable, Sendable {
        public let unit: Map3DReindeer.Unit
        public let point: Map3DPoint
        public let forward: Map3DPoint

        public init(unit: Map3DReindeer.Unit, point: Map3DPoint, forward: Map3DPoint) {
            self.unit = unit
            self.point = point
            self.forward = forward
        }
    }

    public let placements: [Placement]

    public init(placements: [Placement]) {
        self.placements = placements
    }

    public var isEmpty: Bool { placements.isEmpty }

    /// The ground reindeer's models, near and far, after Taiwan's cars and
    /// before the route bus.
    static let units: [Map3DReindeer.Unit] = [.standing, .grazing, .sledRide]
    static var drawn: [Map3DModelPack.Model] {
        units.flatMap { unit in [false, true].compactMap { Map3DReindeer.model(unit, far: $0) } }
    }

    /// The herd, from its middle: which model, metres east (x) and south
    /// (z), and the way it faces, degrees from east towards south. Spread
    /// a few metres apart, no two facing the same way, the sled at the
    /// edge with room before it.
    static let members: [(unit: Map3DReindeer.Unit, x: Float, z: Float, heading: Float)] = [
        (.standing, 0, 0, 20),
        (.grazing, 3.4, 2.0, 200),
        (.standing, -2.8, 2.6, 290),
        (.grazing, -1.4, -3.2, 110),
        (.sledRide, 4.0, -4.5, 160),
    ]
    /// How far round its middle the herd reaches, metres: the sled and its
    /// reindeer, 4.5 m long, at the edge.
    static let foot: Float = 8
    /// How far from the plaza's middle its middle may be, metres: clear of
    /// the plaza's 18 m tree's planter (5.3 m at its biggest) and its
    /// visitors, out to where the plaza ends.
    static let nearest: Float = 16
    static let farthest: Float = 56
    static let step: Float = 8

    /// How near the camera they are drawn near and at all: a coach stop's
    /// reaches (``Map3DCoaches``), as the plaza's tree.
    public static let nearReach: Float = Map3DCoaches.stopNearReach
    public static let farReach: Float = Map3DCoaches.stopFarReach

    /// Adds the reindeer seen from `eye` to `frame` (``Map3DCoaches``'s
    /// reach for the far models: `reach`), all year; nothing when the pack
    /// lacks their models.
    public func add(to frame: inout Map3DTrains.Frame, pack: Map3DModelPack, eye: Map3DPoint, reach: Float = 1) {
        guard !isEmpty else { return }
        var index: [String: Int] = [:]
        for unit in Self.units {
            for far in [false, true] {
                let name = unit.rawValue + (far ? "-far" : "")
                guard let found = pack.index(of: name) else { return }
                index[name] = found
            }
        }
        for placement in placements {
            let away = (placement.point - eye).length
            guard away < Self.farReach else { continue }
            let far = away >= Self.nearReach * reach
            let name = placement.unit.rawValue + (far ? "-far" : "")
            frame.instances.append(.prop(index[name]!, at: placement.point, forward: placement.forward, scale: 1, tint: 0xFFFFFF))
        }
    }
}

extension Map3DScene.Builder {
    /// Decision 840: where the Santa Claus village's reindeer stand
    /// (``reindeerHerd``): on a real-world map that holds its plaza, the
    /// nearest spot to the plaza's middle, ``Map3DReindeerHerd/nearest`` to
    /// ``Map3DReindeerHerd/farthest`` from it, with no road, track, station
    /// building or landmark under the herd. None anywhere else. After the
    /// winter decorations, so the herd keeps off the plaza's tree.
    mutating func addReindeerHerd(frame: RealWorldFrame?) {
        typealias Herd = Map3DReindeerHerd
        guard let frame, let plaza = Map3DWinterLights.plazas.first(where: { $0.name == "santa-claus-village" }) else { return }
        let place = frame.worldPosition(latitude: plaza.latitude, longitude: plaza.longitude)
        guard contains(x: place.x, y: place.y) else { return }
        let middle = point(x: place.x, y: place.y, height: 0)
        guard let spot = Self.herdSpot(round: middle, isClear: { spot in
            let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            let footprint = corners.map { spot + Map3DPoint($0.0 * Herd.foot, 0, $0.1 * Herd.foot) }
            return !underLandmark(spot) && isClear(footprint, facing: Map3DPoint(1, 0, 0))
                && isClearOfBuildings(spot, radius: Herd.foot)
        }) else { return }
        for member in Herd.members {
            let at = spot + Map3DPoint(member.x, 0, member.z)
            let angle = member.heading * Float.pi / 180
            reindeerHerd.append(.init(unit: member.unit, point: Map3DPoint(at.x, drawnGround(x: at.x, z: at.z), at.z),
                                      forward: Map3DPoint(cosf(angle), 0, sinf(angle))))
        }
    }

    /// Decision 840: the spot nearest `middle` that `isClear` says is
    /// clear, by rings ``Map3DReindeerHerd/step`` apart from
    /// ``Map3DReindeerHerd/nearest`` out to ``Map3DReindeerHerd/farthest``,
    /// eight ways round each, south first;
    /// `nil` when none is.
    static func herdSpot(round middle: Map3DPoint, isClear: (Map3DPoint) -> Bool) -> Map3DPoint? {
        typealias Herd = Map3DReindeerHerd
        var radius = Herd.nearest
        while radius <= Herd.farthest {
            for way in 0..<8 {
                let angle = Float.pi / 2 + Float(way) * Float.pi / 4
                let spot = middle + Map3DPoint(cosf(angle) * radius, 0, sinf(angle) * radius)
                if isClear(spot) { return spot }
            }
            radius += Herd.step
        }
        return nil
    }
}
