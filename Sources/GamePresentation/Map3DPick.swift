import Foundation
import GameCore

/// Decision 517 續 (BUILD3D-2, first step): a tap on the native 3D map
/// finds what it lands on, the first thing the 3D map can be tapped for
/// (until now it had only drags, pinches and turns). The finger's point is
/// turned into a ray from the eye (``Map3DCamera/ray(throughX:y:)``); a
/// track node within ``NetworkBuilding/touchRadius`` points of the finger
/// on the screen is taken first, as the 2D map's network tool does; else
/// the ray is walked to the first point under the ground and that is the
/// place, with its land cell.
///
/// Ported from the owner's simulator (`Simulator/reference_snapshot/_next/static/chunks/5758-*.js`,
/// its 3D view's `et`): the finger as −1…1 across the view (`x/w·2−1`,
/// `−(y/h)·2+1`), `Raycaster.setFromCamera`, the hillside meshes first and
/// the level plane (`ray.intersectPlane`) only where the ray meets none,
/// then the cell under the point (`floor(x / cellMm)`), nothing outside the
/// map. Here the ground is a height for each point (the meshes are on the
/// GPU), so the ray is walked in steps and the crossing halved down;
/// buildings are looked through (the player taps the ground behind them,
/// decision 517's "first way").
///
/// Presentation only: it reads the world and the camera and changes
/// neither. What a tap then does goes through the same `NetworkSession`
/// and GameWorld commands as on the 2D map.
public enum Map3DPick {
    /// What a tap landed on.
    public enum Target: Hashable, Sendable {
        /// A track node, within ``NetworkBuilding/touchRadius`` points of
        /// the finger where it is drawn.
        case node(TrackNodeID)
        /// A place along a track edge (its middle, between its nodes),
        /// within ``NetworkBuilding/touchRadius`` points of the finger
        /// where it is drawn, when no node is (decision 517 續, PR 3).
        case edge(NetworkEdgePoint)
        /// The ground (or the sea, where no ground is under the ray).
        case ground
    }

    /// What a tap landed on, and where.
    public struct Hit: Hashable, Sendable {
        public let target: Target
        /// Where, in the scene's metres: the node where its rails are
        /// drawn, or the point on the ground.
        public let point: Map3DPoint
        /// Where, in world units seen from above, rounded; inside the map.
        public let plan: PlanPoint
        /// The land cell (``Land/cellLength``) holding ``plan``.
        public let row: Int
        public let column: Int

        public init(target: Target, point: Map3DPoint, plan: PlanPoint) {
            self.target = target
            self.point = point
            self.plan = plan
            row = Int(plan.y / Land.cellLength)
            column = Int(plan.x / Land.cellLength)
        }
    }

    /// Where the scene's metres are in the world: its origin, in world
    /// units (``Map3DScene/originX``, ``Map3DScene/originY``), and the
    /// same sums as ``Map3DScene/point(worldX:worldY:height:)`` and
    /// ``Map3DScene/worldPosition(of:)``, so a pick needs no scene built.
    public struct Space: Hashable, Sendable {
        public let originX: Double
        public let originY: Double

        public init(originX: Double, originY: Double) {
            self.originX = originX
            self.originY = originY
        }

        public init(scene: Map3DScene) {
            self.init(originX: scene.originX, originY: scene.originY)
        }

        static let metre = Double(WorldCoordinate.unitsPerMetre)

        public func point(_ coordinate: WorldCoordinate) -> Map3DPoint {
            Map3DPoint(Float((Double(coordinate.x) - originX) / Self.metre), Float(Double(coordinate.z) / Self.metre),
                       Float((Double(coordinate.y) - originY) / Self.metre))
        }

        public func worldPosition(of point: Map3DPoint) -> (x: Double, y: Double) {
            (originX + Double(point.x) * Self.metre, originY + Double(point.z) * Self.metre)
        }
    }

    /// The ground's height, in metres, at scene point (`x`, `z`).
    public typealias Ground = @Sendable (_ x: Float, _ z: Float) -> Float

    /// The ground as `scene` draws it (``Map3DScene/drawnGround``): its
    /// 64 m grid's corners where it drew them, the heights file's on a
    /// real-world map's blocks the world has not read; past the scene,
    /// the same rule on `world`.
    public static func ground(of scene: Map3DScene, world: GameWorld) -> Ground {
        let grid = scene.drawnGround
        return { x, z in grid.height(x: x, z: z, world: world) }
    }

    /// The world's own ground (``GameWorld/groundHeight(at:)``) in `space`,
    /// with no scene: sea level (0 m) outside the map and where the world
    /// has not read its ground. Taps read the scene's
    /// (``ground(of:world:)``); this is for a world with no scene.
    public static func ground(of world: GameWorld, in space: Space) -> Ground {
        let bounds = world.bounds
        let ground = world
        return { x, z in
            let at = space.worldPosition(of: Map3DPoint(x, 0, z))
            let plan = PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))
            guard bounds.contains(plan), let height = ground.groundHeight(at: plan) else { return 0 }
            return Float(Double(height) / Space.metre)
        }
    }

    /// The longest step along a ray, in metres, near the eye: the ground's
    /// heights are 64 m apart (``Land/cellLength``), so a step of a few
    /// metres crosses no slope unseen (decision 517: 2–4 m).
    public static let nearStep: Float = 3
    /// Farther along, the step grows with the distance, this share of it,
    /// so a ray from 12 km away takes some 700 steps, not 4,000.
    public static let stepShare: Float = 0.004
    /// How many times the step over the ground is halved: 3 m to under a
    /// millimetre.
    public static let halvings = 12

    /// The first point along `ray` under `ground`, within `reach` metres
    /// of its start; else where it meets sea level (0 m) within `reach`;
    /// `nil` if it meets neither (it points up, or too far).
    public static func ground(along ray: Map3DRay, ground: Ground, within reach: Float) -> Map3DPoint? {
        if let t = under(along: ray, ground: ground, within: reach) { return ray.point(at: t) }
        // The simulator's level plane: the sea, where no ground is.
        guard ray.direction.y < 0 else { return nil }
        let t = -ray.origin.y / ray.direction.y
        return t >= 0 && t <= reach ? ray.point(at: t) : nil
    }

    /// How far along `ray` it first goes under `ground`, in metres, within
    /// `reach`; `nil` if it does not.
    static func under(along ray: Map3DRay, ground: Ground, within reach: Float) -> Float? {
        func above(_ t: Float) -> Float {
            let p = ray.point(at: t)
            return p.y - ground(p.x, p.z)
        }
        var low: Float = 0
        if above(low) <= 0 { return 0 }
        while low < reach {
            let high = min(low + max(nearStep, low * stepShare), reach)
            if above(high) <= 0 {
                var a = low, b = high
                for _ in 0..<halvings {
                    let middle = (a + b) / 2
                    if above(middle) <= 0 { b = middle } else { a = middle }
                }
                return b
            }
            low = high
        }
        return nil
    }

    /// How much of the way to a node or a place on track the ground may
    /// cross and still leave it seen, in metres: the bank of the cutting
    /// it runs in, the slope a tunnel's mouth opens into, the 64 m grid's
    /// straight squares over a curved hillside. At least this much,
    /// ``sightShare`` of the way farther off.
    public static let sightClearance: Float = 8
    public static let sightShare: Float = 0.01

    /// Whether `point` is seen from `eye` over `ground`: the straight way
    /// from the eye goes under no ground short of the last
    /// ``sightClearance`` metres before it. A node behind a hill is not
    /// seen; so is one deep in a tunnel.
    public static func isSeen(_ point: Map3DPoint, from eye: Map3DPoint, ground: Ground) -> Bool {
        let span = point - eye
        let length = span.length
        let clear = length - max(sightClearance, length * sightShare)
        guard clear > 0 else { return true }
        return under(along: Map3DRay(origin: eye, direction: span), ground: ground, within: clear) == nil
    }

    /// How finely an edge is cut to be found on the screen, in metres:
    /// the scene lays its track every 16 m (``Map3DScene``'s
    /// `trackStep`), and over 16 m the screen's straight line and the
    /// perspective's differ by little.
    public static let edgeStep: Float = 16
    /// How many of the nearest things within reach are looked at for
    /// being seen, of each kind, before the ground is taken instead.
    static let sightTries = 24

    /// What a tap at (`x`, `y`) points from the view's top left lands on,
    /// seen by `camera`: the track node of `nodes` drawn nearest the finger
    /// within ``NetworkBuilding/touchRadius`` points (by its number when
    /// two are as near); else the place on an edge of `edges` drawn
    /// nearest within as many points (the lower numbered edge when two are
    /// as near), as the 2D map's network tool takes a node first, then the
    /// track; else the ground under the finger. A node or place the ground
    /// hides from the eye (``isSeen(_:from:ground:)``) is passed over.
    /// `nil` when the ray meets no ground or sea within the camera's far
    /// plane, or lands outside `bounds`.
    ///
    /// A node is where its rails are drawn (its height, up by
    /// ``Map3DScene/railLift``), so a viaduct's or a tunnel's is found
    /// where it is seen, not at the ground under it. Nodes are found on
    /// the screen, as the 2D map finds them: farther away, the same
    /// 24 points reach more metres, as a finger is less sure there too.
    public static func pick(
        atX x: Float, y: Float, camera: Map3DCamera, space: Space, bounds: WorldBounds,
        nodes: some Sequence<TrackNode>, edges: some Sequence<(id: TrackEdgeID, geometry: TrackGeometry)> = EmptyCollection(),
        ground: Ground
    ) -> Hit? {
        let reachSquared = Float(NetworkBuilding.touchRadius * NetworkBuilding.touchRadius)
        let matrix = camera.viewProjection
        let lift = Map3DPoint(0, Map3DScene.railLift, 0)
        let eye = camera.eye
        func hit(_ target: Target, at point: Map3DPoint) -> Hit {
            let at = space.worldPosition(of: point)
            return Hit(target: target, point: point, plan: PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded())))
        }
        var nearNodes: [(distance: Float, id: TrackNodeID, point: Map3DPoint)] = []
        for node in nodes {
            let point = space.point(node.position) + lift
            guard let seen = camera.screenPoint(of: point, through: matrix) else { continue }
            let dx = seen.x - x, dy = seen.y - y
            let squared = dx * dx + dy * dy
            if squared <= reachSquared { nearNodes.append((squared, node.id, point)) }
        }
        nearNodes.sort { ($0.distance, $0.id) < ($1.distance, $1.id) }
        for near in nearNodes.prefix(sightTries) where isSeen(near.point, from: eye, ground: ground) {
            return hit(.node(near.id), at: near.point)
        }
        // The track between the nodes, cut every ``edgeStep`` metres; on
        // each piece the point nearest the finger on the screen.
        var nearEdges: [(distance: Float, id: TrackEdgeID, along: Int64, point: Map3DPoint)] = []
        for (id, geometry) in edges {
            let points = geometry.points.map { space.point($0) + lift }
            for index in points.indices.dropLast() {
                let a = points[index], b = points[index + 1]
                let pieces = max(1, Int(((b - a).length / edgeStep).rounded(.up)))
                let start = Double(geometry.distances[index]), span = Double(geometry.distances[index + 1]) - start
                var from = camera.screenPoint(of: a, through: matrix)
                for piece in 0..<pieces {
                    let share0 = Float(piece) / Float(pieces), share1 = Float(piece + 1) / Float(pieces)
                    let to = camera.screenPoint(of: a + (b - a) * share1, through: matrix)
                    defer { from = to }
                    guard let p = from, let q = to else { continue }
                    let dx = q.x - p.x, dy = q.y - p.y
                    let length = dx * dx + dy * dy
                    let t = length > 0 ? min(1, max(0, ((x - p.x) * dx + (y - p.y) * dy) / length)) : 0
                    let ex = p.x + t * dx - x, ey = p.y + t * dy - y
                    let squared = ex * ex + ey * ey
                    guard squared <= reachSquared else { continue }
                    let share = share0 + (share1 - share0) * t
                    nearEdges.append((squared, id, Int64((start + span * Double(share)).rounded()), a + (b - a) * share))
                }
            }
        }
        nearEdges.sort { ($0.distance, $0.id, $0.along) < ($1.distance, $1.id, $1.along) }
        for near in nearEdges.prefix(sightTries) where isSeen(near.point, from: eye, ground: ground) {
            return hit(.edge(NetworkEdgePoint(edge: near.id, distance: near.along)), at: near.point)
        }
        let ray = camera.ray(throughX: x, y: y)
        guard let point = Self.ground(along: ray, ground: ground, within: camera.depthRange.far) else { return nil }
        let at = space.worldPosition(of: point)
        let plan = PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded()))
        guard bounds.contains(plan) else { return nil }
        return Hit(target: .ground, point: point, plan: plan)
    }

    /// ``pick(atX:y:camera:space:bounds:nodes:edges:ground:)`` on
    /// `world`'s track, and the ground as `scene` draws it
    /// (``ground(of:world:)``).
    public static func pick(atX x: Float, y: Float, camera: Map3DCamera, scene: Map3DScene, world: GameWorld) -> Hit? {
        let edges = world.network.edges.lazy.compactMap { edge in world.trackGeometry(of: edge.id).map { (id: edge.id, geometry: $0) } }
        return pick(atX: x, y: y, camera: camera, space: Space(scene: scene), bounds: world.bounds,
                    nodes: world.network.nodes, edges: edges, ground: ground(of: scene, world: world))
    }
}

/// A half-line in the scene: from `origin`, along `direction` (one metre
/// long).
public struct Map3DRay: Hashable, Sendable {
    public let origin: Map3DPoint
    public let direction: Map3DPoint

    public init(origin: Map3DPoint, direction: Map3DPoint) {
        self.origin = origin
        self.direction = direction.normalized ?? Map3DPoint(0, -1, 0)
    }

    /// The point `t` metres along.
    public func point(at t: Float) -> Map3DPoint { origin + direction * t }
}

extension Map3DCamera {
    /// The ray from the eye through the view's point (`x`, `y`), in points
    /// from its top left: the inverse of ``projection`` and ``view``, from
    /// the same axes (``view``'s side, up and back) and lens, so a point
    /// along it lands back on (`x`, `y`) (``screenPoint(of:)``).
    public func ray(throughX x: Float, y: Float) -> Map3DRay {
        let width = max(viewport.width, 1), height = max(viewport.height, 1)
        // The simulator's −1…1: right and up.
        let across = x / width * 2 - 1, up = 1 - y / height * 2
        let eye = eye
        let look = (target - eye).normalized ?? Map3DPoint(0, -1, 0)
        let side = right
        let upward = (-look).cross(side).normalized ?? forward
        let tall = tanf(fieldOfViewTall / 2)
        let direction = look + side * (across * tall * width / height) + upward * (up * tall)
        return Map3DRay(origin: eye, direction: direction)
    }

    /// Where scene point `point` is drawn, in points from the view's top
    /// left; `nil` behind the eye or outside the drawn depth.
    public func screenPoint(of point: Map3DPoint) -> (x: Float, y: Float)? {
        screenPoint(of: point, through: viewProjection)
    }

    func screenPoint(of point: Map3DPoint, through matrix: Map3DMatrix) -> (x: Float, y: Float)? {
        guard let clip = matrix.project(point), clip.z >= 0, clip.z <= 1 else { return nil }
        return ((clip.x + 1) / 2 * viewport.width, (1 - clip.y) / 2 * viewport.height)
    }
}
