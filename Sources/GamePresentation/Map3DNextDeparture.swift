import Foundation
import GameCore

/// Decision 334: a train on a station's board (``DepartureBoard``) tapped
/// opens the 3D map over the platform it stops at: the camera flies there
/// (``Map3DFlight``, as the follow view does, decision 333) and the train
/// is ringed (``Map3DTrains/ringColour``). The idea is sporenkijker's (a live 3D
/// board of the Dutch railways: tap a departure and the camera flies to
/// its platform); that repository has no licence, so only the idea is
/// taken, none of its code, models or textures. Presentation only: read
/// from the world when tapped.
public struct Map3DNextDeparture: Hashable, Sendable {
    public let train: TrainID
    public let station: StationID
    /// The platform it stops at, or `nil` when the station has none on
    /// the track.
    public let platform: TrackPlatform?

    public init(train: TrainID, station: StationID, platform: TrackPlatform?) {
        self.train = train
        self.station = station
        self.platform = platform
    }

    /// Train `train` calling next at `station`: which platform, as
    /// ``platform(of:at:in:)`` reads it.
    public init(train: TrainID, station: StationID, in world: GameWorld) {
        self.init(train: train, station: station, platform: Self.platform(of: train, at: station, in: world))
    }

    /// The platform of `station` train `train` stops at: the one it stands
    /// along now; else the first on the track it is routed over from where
    /// it is (its edge, then the edges ahead of it); else, not yet routed
    /// that far, the station's first. A train is given its platform only
    /// as it is routed in (the dispatcher's choice), so until then this is
    /// the station's first, as a board that shows no track yet.
    public static func platform(of train: TrainID, at station: StationID, in world: GameWorld) -> TrackPlatform? {
        let platforms = world.trackPlatforms(of: station)
        guard !platforms.isEmpty else { return nil }
        if let standing = world.trackPlatformsAlongWholeTrain(train).first(where: { $0.station == station }) {
            return standing
        }
        if let moving = world.train(id: train), case .onEdge(let traversal, _)? = moving.position {
            for edge in [traversal.edge] + moving.movement.remainingEdges {
                if let platform = world.network.platforms(on: edge).first(where: { $0.station == station }) {
                    return platform
                }
            }
        }
        return platforms.first
    }

    /// The platform's middle in `scene`'s space and the way it runs
    /// (level, one metre long), and its length in metres.
    public static func middle(of platform: TrackPlatform, in world: GameWorld, scene: Map3DScene)
        -> (point: Map3DPoint, along: Map3DPoint, length: Float)? {
        guard let geometry = world.trackGeometry(of: platform.edge),
              platform.start >= 0, platform.end <= geometry.length, platform.start < platform.end else { return nil }
        let middle = geometry.location(at: (platform.start + platform.end) / 2)
        let along = Map3DPoint(Float(middle.direction.dx), 0, Float(middle.direction.dy)).normalized ?? Map3DPoint(0, 0, -1)
        let metres = Float(platform.length) / Float(WorldCoordinate.unitsPerMetre)
        return (scene.point(middle.position), along, metres)
    }

    /// The nearest and farthest the camera looks at a platform from.
    public static let distances: ClosedRange<Float> = 150...600

    /// The camera looking at a platform whose middle is at `point`, running
    /// `along`, `length` metres long, from `camera`: tilted as the map
    /// tilts at its distance (so the map is the player's own again once
    /// there), as far as shows the platform and a fifth more top to
    /// bottom, within ``distances``; turned the least from where `camera`
    /// faces so the platform runs across a wide view and up a tall one
    /// (a phone held upright sees a long platform end to end).
    public static func camera(platformAt point: Map3DPoint, along: Map3DPoint, length: Float, from camera: Map3DCamera) -> Map3DCamera {
        var goal = camera
        goal.target = point
        goal.pitch = nil
        goal.distance = min(max(length * 1.2 / (2 * tanf(Map3DCamera.fieldOfView / 2)), distances.lowerBound), distances.upperBound)
        let wide = camera.viewport.width >= camera.viewport.height
        let runs = Map3DFollow.heading(of: along)
        // Across: facing at right angles to it; up: facing along it. Either
        // way round, whichever is nearer.
        let base = wide ? runs + .pi / 2 : runs
        let options = [base, base + .pi]
        goal.heading = options.min { abs(Map3DCamera.turnFromNorth($0 - camera.heading)) < abs(Map3DCamera.turnFromNorth($1 - camera.heading)) }
            .map { Map3DCamera.turnFromNorth($0) } ?? camera.heading
        return goal
    }

    /// The camera over this departure's platform in `scene`, from `camera`;
    /// `nil` without a platform.
    public func camera(in world: GameWorld, scene: Map3DScene, from camera: Map3DCamera) -> Map3DCamera? {
        guard let platform, let middle = Self.middle(of: platform, in: world, scene: scene) else { return nil }
        return Self.camera(platformAt: middle.point, along: middle.along, length: middle.length, from: camera)
    }

    /// Where the 3D map opens over the platform (``Map3DHandoff/Plan``, its
    /// scene built round it; the 2D scale is the map's middle one, which
    /// the 3D map does not use as it opens); `nil` without a platform.
    public func opening(in world: GameWorld) -> Map3DHandoff.Plan? {
        guard let platform, let geometry = world.trackGeometry(of: platform.edge),
              platform.start >= 0, platform.end <= geometry.length, platform.start < platform.end else { return nil }
        let middle = geometry.location(at: (platform.start + platform.end) / 2).position
        return Map3DHandoff.Plan(x: Double(middle.x), y: Double(middle.y), referenceSize: MapScale.compactSize)
    }
}
