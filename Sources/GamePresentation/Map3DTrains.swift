import GameCore

/// The trains on the native 3D map (ARCHITECTURE decision 229), worked out
/// for each frame: each car a box along the track where the 2D map draws it
/// (``TrainMotion`` gliding between ticks, decision 182; ``TrainCars`` laying
/// the cars 20 m long, decision 205), at the track's height there.
///
/// A car is 2.9 m wide and 3.65 m tall, Taiwan Railway's EMU3000 and the
/// commuter formations in `Railway/` rail-3d (`integration/formations.js`;
/// the mesh bounds in `assets/blender-map-v1/`), standing on the rail. The
/// body is white with a band in the line's colour, the way most TRA and
/// metro stock runs.
public enum Map3DTrains {
    public static let carWidth: Float = 2.9
    public static let carHeight: Float = 3.65
    /// The gap between cars, in metres.
    public static let carGap: Float = 0.6
    static let body = Map3DColor.rgb(0xF3F4F2)
    static let roof = Map3DColor.rgb(0xC9CDD1)
    static let freight = Map3DColor.rgb(0x5E6B78)
    static let band = Map3DColor.rgb(0x2F6DB5)

    /// The heights of the trains' bodies at a tick, to put the 2D cars at:
    /// ``RailwaySnapshot/Train/body`` in world units.
    public struct Heights: Sendable {
        let bodies: [TrainID: [WorldCoordinate]]

        public init(_ snapshot: RailwaySnapshot) {
            var bodies: [TrainID: [WorldCoordinate]] = [:]
            for train in snapshot.trains { bodies[train.id] = [train.head.position] + train.body }
            self.bodies = bodies
        }

        public init() {
            bodies = [:]
        }

        /// The bodies of `world`'s trains now, without the rest of a
        /// snapshot (each tick's, on the main actor).
        public init(world: GameWorld) {
            var bodies: [TrainID: [WorldCoordinate]] = [:]
            for train in world.trains where train.position != nil {
                bodies[train.id] = world.bodyPath(of: train.id)
            }
            self.bodies = bodies
        }

        /// The height of train `id`'s body nearest world point (`x`, `y`),
        /// in world units; 0 when it has none.
        func height(of id: TrainID, x: Double, y: Double) -> Double {
            guard let body = bodies[id], var best = body.first else { return 0 }
            var bestDistance = Double.infinity
            for point in body {
                let dx = Double(point.x) - x, dy = Double(point.y) - y
                let distance = dx * dx + dy * dy
                if distance < bestDistance {
                    bestDistance = distance
                    best = point
                }
            }
            return Double(best.z)
        }
    }

    /// Every car of every train in `motion` at `progress` (0 where they were
    /// at the last tick, 1 where they are), in `scene`'s space.
    public static func mesh(
        _ motion: TrainMotion, progress: Double, heights: Heights, in scene: Map3DScene, palette: LinePalette = .standard
    ) -> Map3DMesh {
        var mesh = Map3DMesh()
        let gap = Double(carGap) * Double(WorldCoordinate.unitsPerMetre)
        for run in motion.runs {
            guard let head = run.head(at: progress) else { continue }
            let body = run.body(at: progress)
            let count = TrainCars.count(length: run.length)
            let cars = TrainCars.cars(body: body, heading: head.heading, count: count, gap: gap)
            let (side, stripe) = colours(of: run.look, palette: palette)
            for car in cars {
                guard let front = car.first, let back = car.last else { continue }
                let middleX = (front.x + back.x) / 2, middleY = (front.y + back.y) / 2
                let height = heights.height(of: run.train, x: middleX, y: middleY)
                let a = scene.point(worldX: front.x, worldY: front.y, height: height)
                let b = scene.point(worldX: back.x, worldY: back.y, height: height)
                let length = (a - b).length
                guard length > 1 else { continue }
                let base = (a + b) * 0.5
                mesh.addBox(base: base + Map3DPoint(0, 0.3, 0), forward: a - b, length: length, width: carWidth, height: carHeight - 0.3,
                            top: roof, side: side)
                if let stripe {
                    // The band under the windows, a hand's breadth proud of the
                    // body so it never flickers into it.
                    mesh.addBox(base: base + Map3DPoint(0, 1.0, 0), forward: a - b, length: length + 0.04, width: carWidth + 0.04, height: 0.45,
                                top: stripe, side: stripe)
                }
            }
        }
        return mesh
    }

    /// A train's body colour and the band's, if any.
    static func colours(of look: TrainLook, palette: LinePalette) -> (UInt32, UInt32?) {
        switch look {
        case .freight:
            return (freight, nil)
        case .plain:
            return (body, band)
        case .line(_, let color):
            guard let color else { return (body, band) }
            return (body, Map3DColor.rgb(UInt32(palette.color(for: color.rgb))))
        }
    }
}
