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
        /// Each train's type code (``TrainTypeSpec/code``), `""` for none
        /// (decision 230: which model it is drawn with).
        let types: [TrainID: String]

        public init(_ snapshot: RailwaySnapshot) {
            var bodies: [TrainID: [WorldCoordinate]] = [:]
            for train in snapshot.trains { bodies[train.id] = [train.head.position] + train.body }
            self.bodies = bodies
            types = [:]
        }

        public init() {
            bodies = [:]
            types = [:]
        }

        /// The bodies and types of `world`'s trains now, without the rest of
        /// a snapshot (each tick's, on the main actor).
        public init(world: GameWorld) {
            var bodies: [TrainID: [WorldCoordinate]] = [:]
            var types: [TrainID: String] = [:]
            for train in world.trains where train.position != nil {
                bodies[train.id] = world.bodyPath(of: train.id)
                // Decision 318: or the set its performance has a model for.
                types[train.id] = Map3DTrainSet.key(type: train.type, performance: train.performance)
            }
            self.bodies = bodies
            self.types = types
        }

        func type(of id: TrainID) -> String {
            types[id] ?? ""
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

    /// A frame's trains: the cars drawn with a model (one instance each,
    /// decision 230) and the rest as boxes.
    public struct Frame: Sendable {
        public var boxes = Map3DMesh()
        public var instances: [Map3DInstance] = []
        /// Decision 232: each car's soft shadow on the bed under it.
        public var shadows = Map3DMesh()
        /// Decision 314: over each train's front, where its label goes.
        public var heads: [Head] = []
        /// Decision 342: each car's middle on its rails, for the buildings
        /// seen through in front of it (``Map3DSeeThrough``).
        public var cars: [Map3DPoint] = []
    }

    /// Decision 314: a train and the point just over its front car's roof.
    /// Decision 333: and the way its front car faces, level, one metre
    /// long, for the camera that follows it (``Map3DFollow``).
    public struct Head: Equatable, Sendable {
        public let train: TrainID
        public let point: Map3DPoint
        public let forward: Map3DPoint
        /// Decision 337: the front of the train on the rail, where the
        /// cab view looks out from.
        public let nose: Map3DPoint
        /// Decision 359: the drawn ground at ``nose``, which the camera
        /// following the train stays over (in a tunnel, or a cutting the
        /// ground covers); `nil` off the player's track.
        public let ground: Float?
        /// Decision 359 (續): whether ``nose`` is in a tunnel, where the
        /// cab view stays in it.
        public let inTunnel: Bool
        /// Decision 403 (續): the middle of its cars on the rail, and how
        /// long they run front to back in metres, for the view from beside
        /// it (the reference's watch view looks at the cars' average).
        public var middle: Map3DPoint?
        public var length: Float = 0

        public init(train: TrainID, point: Map3DPoint, forward: Map3DPoint = Map3DPoint(0, 0, -1), nose: Map3DPoint? = nil,
                    ground: Float? = nil, inTunnel: Bool = false) {
            self.train = train
            self.point = point
            self.forward = forward
            self.nose = nose ?? point - Map3DPoint(0, Map3DTrains.carHeight + Map3DTrains.headClearance, 0)
            self.ground = ground
            self.inTunnel = inTunnel
        }

        /// The rail under ``point``, where the follow camera looks.
        public var rail: Map3DPoint { point - Map3DPoint(0, Map3DTrains.carHeight + Map3DTrains.headClearance, 0) }
    }

    /// Decision 380: how much track behind a train's head says the way it
    /// faces (``TrainMotion/Run/steadyHead(at:over:)``): five cars' length.
    static let steadySpan = 5 * TrainCars.drawnCarLength

    /// How far over the roof a train's label stands, in metres.
    static let headClearance: Float = 1

    /// How far from the eye a car is drawn with its model, in metres;
    /// farther, it is a box (the art direction's near and far levels).
    public static let modelReach: Float = 900

    /// Every car of every train in `motion` at `progress` (0 where they were
    /// at the last tick, 1 where they are), in `scene`'s space, as boxes.
    public static func mesh(
        _ motion: TrainMotion, progress: Double, heights: Heights, in scene: Map3DScene, palette: LinePalette = .standard
    ) -> Map3DMesh {
        frame(motion, progress: progress, heights: heights, in: scene, models: nil, eye: nil, palette: palette).boxes
    }

    /// Every car of every train in `motion` at `progress`, in `scene`'s
    /// space: within ``modelReach`` of `eye` (``Map3DTrainSet/reach(of:)``), a car of a type `models` has
    /// is an instance of its model (the head car's model at both ends, the
    /// last one turned round; the middle cars' between); the rest, and a
    /// freight train, boxes.
    public static func frame(
        _ motion: TrainMotion, progress: Double, heights: Heights, in scene: Map3DScene,
        models: Map3DModelPack?, eye: Map3DPoint?, palette: LinePalette = .standard, ringed: TrainID? = nil
    ) -> Frame {
        var frame = Frame()
        let gap = Double(carGap) * Double(WorldCoordinate.unitsPerMetre)
        for run in motion.runs {
            guard let head = run.head(at: progress) else { continue }
            let body = run.body(at: progress)
            // Decision 227: as many cars as stand its own car length apart.
            let count = TrainCars.count(length: run.length, carPitch: run.carPitch)
            // Decision 380: facing the way the track runs behind the head,
            // held steady, so the cars and the cab's view do not shake from
            // one sampled point of the track to the next.
            let steady = run.steadyHead(at: progress, over: Self.steadySpan)
            let (side, stripe) = colours(of: run.look, palette: palette)
            // Decision 408: half the high-speed trains the N700S-G.
            let trainType = Map3DTrainSet.variant(of: heights.type(of: run.train), number: run.train.rawValue)
            let hasModels = run.look != .freight && models?.models(forType: trainType) != nil
            // Decision 399: or each car at its model's own length.
            let layout = hasModels ? models?.layout(forType: trainType, count: count) : nil
            let heading = steady?.heading ?? head.heading
            let units = Double(WorldCoordinate.unitsPerMetre)
            let cars = layout.map {
                TrainCars.cars(body: body, heading: heading, lengths: $0.map { Double($0.length) * units }, gaps: $0.map { Double($0.gap) * units })
            } ?? TrainCars.cars(body: body, heading: heading, count: count, gap: gap)
            // Decision 334: the rails under the train, front to back, for
            // its ring.
            var line: [Map3DPoint] = []
            // Decision 403 (續): the cars' middles, for the head's middle.
            var bases: [Map3DPoint] = []
            let headIndex = frame.heads.count
            defer {
                if run.train == ringed { frame.boxes.addRing(round: line) }
                if frame.heads.count > headIndex, !bases.isEmpty {
                    frame.heads[headIndex].middle = bases.reduce(Map3DPoint.zero, +) * (1 / Float(bases.count))
                    frame.heads[headIndex].length = zip(line, line.dropFirst()).reduce(0) { $0 + ($1.0 - $1.1).length }
                }
            }
            for (index, car) in cars.enumerated() {
                guard let front = car.first, let back = car.last else { continue }
                // On the rails, which stand ``Map3DScene/railLift`` over the
                // track's height (decision 231).
                let lift = Map3DPoint(0, Map3DScene.railLift, 0)
                let a = scene.point(worldX: front.x, worldY: front.y, height: heights.height(of: run.train, x: front.x, y: front.y)) + lift
                let b = scene.point(worldX: back.x, worldY: back.y, height: heights.height(of: run.train, x: back.x, y: back.y)) + lift
                let length = (a - b).length
                guard length > 1 else { continue }
                let base = (a + b) * 0.5
                bases.append(base)
                if index == 0 {
                    let cover = scene.trackCover.ground(at: a)
                    // Decision 380: the cab's eye at the steady head's nose,
                    // facing the way it does.
                    var forward = Map3DPoint(a.x - b.x, 0, a.z - b.z).normalized ?? Map3DPoint(0, 0, -1), nose = a
                    if let steady {
                        let half = TrainCars.drawnCarLength / 2
                        let front = TrainMotion.Point(x: steady.point.x + steady.heading.x * half, y: steady.point.y + steady.heading.y * half)
                        forward = Map3DPoint(Float(steady.heading.x), 0, Float(steady.heading.y))
                        nose = scene.point(worldX: front.x, worldY: front.y, height: 0) + Map3DPoint(0, a.y, 0)
                    }
                    frame.heads.append(Head(train: run.train, point: a + (b - a) * (min(4, length / 2) / length)
                                                + Map3DPoint(0, carHeight + headClearance, 0),
                                            forward: forward, nose: nose, ground: cover?.height, inTunnel: cover?.inTunnel ?? false))
                }
                if line.isEmpty { line.append(a) }
                line.append(b)
                // Decision 359 (續): drawn in its tunnel's bore, but no car
                // to see through buildings for: the ground hides it.
                if !scene.trackCover.isInTunnel(base) { frame.cars.append(base) }
                // Decision 232: a soft shadow on the bed under the car.
                let bed = Map3DPoint(0, 0.05 - Map3DScene.Builder.bedDrop, 0)
                frame.shadows.addShadow(
                    inner: Map3DMesh.footprint(centre: base + bed, forward: a - b, length: length, width: carWidth),
                    outer: Map3DMesh.footprint(centre: base + bed, forward: a - b, length: length + 1, width: carWidth + 1), darkness: 0.38)
                if let models, hasModels, let eye,
                   let near = layout?[index].model ?? models.modelIndex(forType: trainType, carIndex: index, count: cars.count),
                   // Decision 408: past its set's reach, its far set's car.
                   let model = models.model(near, forType: trainType, count: count, at: (base - eye).length) {
                    // The last car is the head car's model turned round, or
                    // the set's own tail.
                    let turned = layout == nil && models.isTurned(forType: trainType, carIndex: index, count: cars.count)
                    frame.instances.append(instance(of: models.models[model], index: model, from: turned ? a : b, to: turned ? b : a,
                                                    stripe: stripe ?? band))
                    continue
                }
                frame.boxes.addBox(base: base + Map3DPoint(0, 0.3, 0), forward: a - b, length: length, width: carWidth,
                                   height: carHeight - 0.3, top: roof, side: side)
                if let stripe {
                    // The band under the windows, a hand's breadth proud of the
                    // body so it never flickers into it.
                    frame.boxes.addBox(base: base + Map3DPoint(0, 1.0, 0), forward: a - b, length: length + 0.04,
                                       width: carWidth + 0.04, height: 0.45, top: stripe, side: stripe)
                }
            }
        }
        return frame
    }

    /// Decision 334: the ring round a train asked about on a station's
    /// board: a band ``ringWidth`` wide, ``ringGap`` clear of the cars on
    /// both sides and at both ends, ``ringLift`` over the rails (over a
    /// platform's edge, so the platform does not hide it), in
    /// ``ringColour``, lit from within at night. Solid and flat, as the
    /// art style draws (no glow or gradient).
    public static let ringWidth: Float = 0.7
    public static let ringGap: Float = 0.6
    public static let ringLift: Float = 1.3
    /// The 2D map's ring round a picked train, `trainSelection` (decision
    /// 205, docs/UI_THEME.md): the warm yellow.
    public static let ringColour: UInt32 = 0xFFC86B

    /// Model `model` stood on the rail from `back` to `front` (scene
    /// points at the rail's height), stretched along to fit, its front at
    /// `front`.
    static func instance(of model: Map3DModelPack.Model, index: Int, from back: Map3DPoint, to front: Map3DPoint, stripe: UInt32) -> Map3DInstance {
        let along = front - back
        let forward = along.normalized ?? Map3DPoint(0, 0, -1)
        let left = Map3DPoint(forward.z, 0, -forward.x).normalized ?? Map3DPoint(-1, 0, 0)
        let up = forward.cross(left)
        let stretch = model.length > 0 ? along.length / model.length : 1
        let middle = (model.minimum.x + model.maximum.x) / 2
        let origin = (front + back) * 0.5 - forward * (middle * stretch)
        let x = forward * stretch
        let transform: [Float] = [
            x.x, x.y, x.z, 0,
            left.x, left.y, left.z, 0,
            up.x, up.y, up.z, 0,
            origin.x, origin.y, origin.z, 1,
        ]
        func channel(_ shift: UInt32) -> Float { Float((stripe >> shift) & 0xFF) / 255 }
        return Map3DInstance(model: index, transform: transform, stripe: (channel(0), channel(8), channel(16)))
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
