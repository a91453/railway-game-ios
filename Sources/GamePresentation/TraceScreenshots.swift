import Foundation
import GameCore

// Traces the website screenshot tests take (decisions 513, 521).

extension GameSession {
    /// For the website screenshot test (decision 513): the network tool
    /// tracing single track along the North-Link Line from 3,500 m to
    /// 3,400 m south of Nan'ao, which no grade reaches on the map a game
    /// started there has, and the map looking over it; whether the trace
    /// was refused. Through the tool's own taps.
    @discardableResult
    public func traceWhereNoGradeReaches() -> Bool {
        guard canTraceRealRailway, let railways, let frame = RealWorldFrame(world: world),
              let nanao = RealLineLaying.realPoint(of: "南澳", system: "tra_sched", railways: railways, frame: frame) else { return false }
        let paths = railways.lines.filter { $0.system.id == "tra_sched" && $0.points.count > 20 }.map { line in
            WorldPath(line.points.map { WorldVector(frame.worldPosition(latitude: $0.latitude, longitude: $0.longitude)) })
        }
        guard let path = paths.min(by: {
            ($0.point(at: $0.project(nanao)) - nanao).length < ($1.point(at: $1.project(nanao)) - nanao).length
        }) else { return false }
        let metre = Double(WorldCoordinate.unitsPerMetre), station = path.project(nanao)
        let a = path.point(at: station - 3_500 * metre).plan, b = path.point(at: station - 3_400 * metre).plan
        selectTool(.network)
        setNetworkMode(.build)
        networkTracesRealRailway = true
        networkBuildsDouble = false
        let reach = 24 * WorldCoordinate.unitsPerMetre
        tapNetwork(at: a, reach: reach)
        tapNetwork(at: b, reach: reach)
        lookOver(WorldRegion(
            minX: Double(min(a.x, b.x)), minY: Double(min(a.y, b.y)),
            maxX: Double(max(a.x, b.x)), maxY: Double(max(a.y, b.y))
        ))
        return networkPreview(now: true)?.traced == 0
    }
}

extension GameSession {
    /// For the website screenshot test (decision 521's third sequel): the
    /// network tool tracing from `from` to `to`, the map looking close over
    /// the stretch a third of the way along (or, with `joining`, first
    /// laying the middle third and looking where the trace joins it);
    /// where it looks when the preview can be built, `nil` when it cannot.
    /// Through the tool's own taps.
    @discardableResult
    public func traceForPreviewScreenshot(from: String, to: String, joining: Bool) -> WorldRegion? {
        guard canTraceRealRailway, let railways, let frame = RealWorldFrame(world: world),
              let start = RealLineLaying.realPoint(of: from, system: "tra_sched", railways: railways, frame: frame),
              let end = RealLineLaying.realPoint(of: to, system: "tra_sched", railways: railways, frame: frame),
              let traces = realRailwayTraces else { return nil }
        let metre = Double(WorldCoordinate.unitsPerMetre)
        guard let a = traces.snap(start, within: 50 * metre), let b = traces.snap(end, within: 50 * metre),
              let points = traces.path(from: a.place, to: b.place) else { return nil }
        let way = WorldPath(points)
        selectTool(.network)
        setNetworkMode(.build)
        networkTracesRealRailway = true
        let reach = 24 * WorldCoordinate.unitsPerMetre
        if joining {
            networkBuildsDouble = false
            networkDoubleChosen = true
            tapNetwork(at: way.point(at: way.length / 3).plan, reach: reach)
            tapNetwork(at: way.point(at: way.length * 2 / 3).plan, reach: reach)
            buildNetworkTrack()
            clearNetworkDraft()
        }
        tapNetwork(at: start.plan, reach: reach)
        tapNetwork(at: end.plan, reach: reach)
        let centre = way.point(at: way.length / 3), half = (joining ? 500 : 250) * metre
        let region = WorldRegion(minX: centre.x - half, minY: centre.y - half, maxX: centre.x + half, maxY: centre.y + half)
        lookOver(region)
        return networkPreview(now: true)?.problem == nil ? region : nil
    }
}
