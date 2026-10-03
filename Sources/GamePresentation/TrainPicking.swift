import GameCore

extension GameWorld {
    /// The train drawn nearest `point` on the map, within `reach` world
    /// units of its head or of its body (``bodyPath(of:)``, the line its
    /// cars stand along), or `nil` when none is that close. Among trains
    /// equally near, the first by ID. Display data, read from
    /// `location(of:)` and `bodyPath(of:)`; never changes the world.
    public func train(near point: PlanPoint, within reach: Int64) -> TrainID? {
        guard reach >= 0 else { return nil }
        let x = Double(point.x), y = Double(point.y)
        var best: (id: TrainID, distance: Double)?
        for train in trains {
            let path = bodyPath(of: train.id).map { (x: Double($0.x), y: Double($0.y)) }
            guard let head = path.first else { continue }
            var distance = ((head.x - x) * (head.x - x) + (head.y - y) * (head.y - y)).squareRoot()
            for (from, to) in zip(path, path.dropFirst()) {
                distance = min(distance, Self.distance(from: (x, y), toSegment: from, to))
            }
            guard distance <= Double(reach), best.map({ distance < $0.distance }) ?? true else { continue }
            best = (train.id, distance)
        }
        return best?.id
    }

    /// How far `point` lies from the segment from `a` to `b`.
    private static func distance(from point: (x: Double, y: Double), toSegment a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> Double {
        let (dx, dy) = (b.x - a.x, b.y - a.y)
        let squared = dx * dx + dy * dy
        var t = squared > 0 ? ((point.x - a.x) * dx + (point.y - a.y) * dy) / squared : 0
        t = min(max(t, 0), 1)
        let (px, py) = (a.x + t * dx - point.x, a.y + t * dy - point.y)
        return (px * px + py * py).squareRoot()
    }

    /// What the select tool shows for train `id`: "Train · Ring
    /// Train 1 · Stopped at South · 30 riding · 5% · Ring Line"; where it
    /// is stopped, how full it is and the service it runs for, when it has
    /// them, or "not on the track" before it is placed. `nil` for an
    /// unknown ID.
    public func trainSummary(of id: TrainID, in language: DisplayLanguage) -> String? {
        guard let train = train(id: id) else { return nil }
        var parts = [language.text("Train", "列車"), train.name]
        if train.position == nil {
            parts.append(language.text("not on the track", "不在軌道上"))
        } else if let stop = stationStopText(of: id, in: language) {
            parts.append(stop)
        } else if train.execution != nil {
            parts.append(language.text("running", "行駛中"))
        }
        if let load = loadText(of: id, in: language) {
            parts.append(load)
        }
        if let service = assignedServiceName(of: id, in: language) {
            parts.append(service)
        }
        return parts.joined(separator: " · ")
    }
}
