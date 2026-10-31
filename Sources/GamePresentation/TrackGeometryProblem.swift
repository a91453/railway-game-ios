import GameCore

// Decision 513: GameCore refuses a stretch of track with one error,
// `GameError.invalidTrackGeometry`, for several different things (an end
// off the map, an end too high above or too deep below the ground, the
// same point twice, a curve that doubles back). The network tool asks
// GameCore's own checks again, in GameCore's order, to say which one it
// was; the edge's own reasons are BUILDMSG's (`NetworkBuilding
// .geometryProblem`). Presentation only: GameCore still decides.

/// Which of GameCore's checks refuses a stretch of track with
/// `GameError.invalidTrackGeometry`: one of its new ends, or the edge
/// itself (``NetworkBuilding/GeometryProblem``, BUILDMSG's).
public enum TrackGeometryProblem: Hashable, Sendable {
    /// A new end would stand this far above the ground (world units),
    /// past `RailwayNetwork.heightRange`.
    case tooHigh(Int64)
    /// A new end would stand this far below the ground (world units),
    /// past `RailwayNetwork.heightRange`.
    case tooDeep(Int64)
    /// Track already ends at that very point.
    case pointTaken
    /// The edge between the ends: off the map, the same spot, too great a
    /// rise, or a curve that doubles back.
    case geometry(NetworkBuilding.GeometryProblem)

    /// Which check refuses `stretch` in `world`, with the ground under it
    /// read from `heights` as building it would; `nil` when none of these
    /// does (GameCore refused it for something else, or not at all).
    static func of(_ stretch: PlayerCommand.TrackStretch, in world: GameWorld, heights: HeightGrid?) -> TrackGeometryProblem? {
        var world = world
        try? world.readGround(under: stretch.ground, from: heights)
        // GameWorld.buildTrackNode(at:), for each new end, start first.
        for (anchor, position) in [(stretch.start, stretch.from), (stretch.end, stretch.to)] {
            guard case .point = anchor else { continue }
            guard world.bounds.contains(position.plan) else { return .geometry(.outsideMap) }
            guard let ground = world.groundHeight(at: position.plan) else { continue }
            let above = position.z - ground
            if above > RailwayNetwork.heightRange.upperBound { return .tooHigh(above) }
            if above < RailwayNetwork.heightRange.lowerBound { return .tooDeep(-above) }
            if world.network.nodes.contains(where: { $0.position == position }) { return .pointTaken }
        }
        // GameWorld.buildTrackEdge: the ends, the handles, then the curve.
        var handles: [PlanPoint] = []
        if case .cubic(let first, let second) = stretch.curve { handles = [first, second] }
        guard stretch.from.plan == stretch.to.plan || !handles.allSatisfy(world.bounds.contains)
                || TrackGeometry(from: stretch.from, to: stretch.to, curve: stretch.curve, profile: stretch.profile) == nil
        else { return nil }
        return .geometry(NetworkBuilding.geometryProblem(from: stretch.from, to: stretch.to, curve: stretch.curve, bounds: world.bounds))
    }

    public func text(in language: DisplayLanguage) -> String {
        switch self {
        case .tooHigh(let above):
            let limit = NetworkBuilding.lengthText(RailwayNetwork.heightRange.upperBound, in: language)
            let height = NetworkBuilding.lengthText(above, in: language)
            return language.text(
                "One end would stand \(height) above the ground; track stands at most \(limit) above it.",
                "有一端會離地面 \(height)，軌道最高只能離地 \(limit)。"
            )
        case .tooDeep(let below):
            let limit = NetworkBuilding.lengthText(-RailwayNetwork.heightRange.lowerBound, in: language)
            let depth = NetworkBuilding.lengthText(below, in: language)
            return language.text(
                "One end would be \(depth) underground; track goes at most \(limit) deep.",
                "有一端會在地面下 \(depth)，軌道最深只能到地下 \(limit)。"
            )
        case .pointTaken:
            return language.text(
                "Track already ends at that point. Tap the end of that track instead.",
                "那一點已經有軌道的端點，請改點那個端點。"
            )
        case .geometry(let problem):
            return problem.text(in: language)
        }
    }
}

extension GameError {
    /// What the player reads when `stretch` is refused with this error:
    /// for ``GameError/invalidTrackGeometry``, which check refused it
    /// (decision 513); otherwise ``playerMessage(in:)``.
    func playerMessage(building stretch: PlayerCommand.TrackStretch, in world: GameWorld, heights: HeightGrid?, language: DisplayLanguage) -> String {
        guard self == .invalidTrackGeometry, let problem = TrackGeometryProblem.of(stretch, in: world, heights: heights) else {
            return playerMessage(in: language)
        }
        return problem.text(in: language)
    }
}
