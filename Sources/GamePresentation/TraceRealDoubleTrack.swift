import Foundation
import GameCore

/// Why a traced stretch's second track cannot be laid (decision 247), as
/// the player reads it.
struct TraceDoubleProblem: Error {
    let text: String
    /// ``text`` in the pill's one short line (decision 803, continued).
    var brief: String? = nil
}

// MARK: - Single or double, as the real line is

// Decision 247, later: traced along the TRA, the stretch is single or
// double as the real line is there, from `tra_track_sections.json` (each
// section between two adjacent stations, `tracks` 1 or 2), unless the
// player chose with the "Double" switch. The whole stretch is one or the
// other (one command, one second track), double where half its length or
// more runs through double sections: the same half the source draws its
// own line between single and double with (`parallelFrac` ≥ 0.5).

extension GameSession {
    /// How near a traced stretch a TRA station stands for its sections to
    /// be looked at: 150 m.
    static let tracedStationReach = 150 * RealRailwayTraces.metre
    /// How far apart the places along a traced stretch lie that each find
    /// the section they are in: 100 m.
    static let tracedSectionStep = 100 * RealRailwayTraces.metre

    /// Whether the traced `built` edges get a second track beside them
    /// (`double`): as the player set the "Double" switch, once they have;
    /// until then as the real line is (``realDoubleTrack(along:)``,
    /// `real` is its answer), or as the switch is where the data says
    /// nothing.
    func tracedDouble(_ built: [PlayerCommand.TrackStretch]) -> (double: Bool, real: Bool?) {
        guard !networkDoubleChosen, !built.isEmpty, let real = realDoubleTrack(along: built) else { return (networkBuildsDouble, nil) }
        return (real, real)
    }

    /// Whether the TRA's real track is double along the traced `built`
    /// edges: each place ``tracedSectionStep`` apart is in the section
    /// whose two stations it lies most nearly between (the least detour
    /// from one station through it to the other); double where half the
    /// places or more are in double sections, single where half or more
    /// are in single ones. `nil` off the TRA, without the data, or where
    /// it knows too little of the stretch.
    func realDoubleTrack(along built: [PlayerCommand.TrackStretch]) -> Bool? {
        guard let railways, let data = railways.stationData, let frame = RealWorldFrame(world: world),
              let traces = realRailwayTraces else { return nil }
        let path = WorldPath(built.flatMap(\.geometryPoints).map { WorldVector($0.plan) })
        guard path.points.count > 1, path.length > 0,
              let snap = traces.snap(path.point(at: path.length / 2), within: RealRailwayTraces.joinReach),
              traces.lines[snap.place.line].system == Self.traSystem else { return nil }

        func key(_ name: String) -> String { name.replacingOccurrences(of: "台", with: "臺") }
        var stations: [String: WorldVector] = [:]
        for station in railways.stations where station.system.id == Self.traSystem {
            let point = WorldVector(frame.worldPosition(latitude: station.coordinate.latitude, longitude: station.coordinate.longitude))
            if stations[key(station.chinese)] == nil { stations[key(station.chinese)] = point }
        }
        var sections: [(a: String, b: String, from: WorldVector, to: WorldVector, double: Bool)] = []
        for (pair, section) in data.trackSections.sorted(by: { $0.key < $1.key }) {
            let names = pair.split(separator: "|").map { key(String($0)) }
            guard names.count == 2, let from = stations[names[0]], let to = stations[names[1]] else { continue }
            sections.append((names[0], names[1], from, to, section.isDoubleTrack))
        }
        // The sections of the stations the stretch passes, or every
        // section for a stretch between two stations.
        let reach = Self.tracedStationReach
        let xs = path.points.map(\.x), ys = path.points.map(\.y)
        let near = Set(stations.compactMap { name, point -> String? in
            guard point.x >= (xs.min() ?? 0) - reach, point.x <= (xs.max() ?? 0) + reach,
                  point.y >= (ys.min() ?? 0) - reach, point.y <= (ys.max() ?? 0) + reach,
                  path.nearest(point).away <= reach else { return nil }
            return name
        })
        let candidates = near.isEmpty ? sections : sections.filter { near.contains($0.a) || near.contains($0.b) }

        let count = max(1, Int((path.length / Self.tracedSectionStep).rounded()))
        var double = 0, single = 0
        for index in 0..<count {
            let point = path.point(at: path.length * (Double(index) + 0.5) / Double(count))
            var best: (detour: Double, double: Bool)?
            for section in candidates {
                let span = (section.to - section.from).length
                let detour = (point - section.from).length + (point - section.to).length - span
                // Not beyond either station by more than the span itself.
                guard detour <= span, best == nil || detour < best!.detour else { continue }
                best = (detour, section.double)
            }
            switch best?.double {
            case true?: double += 1
            case false?: single += 1
            case nil: break
            }
        }
        if double * 2 >= count { return true }
        if single * 2 >= count { return false }
        return nil
    }

    /// The TRA's system in the bundled lines and stations.
    static let traSystem = "tra_sched"

    /// What the preview and the message say when the real line decided:
    /// "Double track, as the real railway is here."
    static func realTrackCountText(double: Bool, in language: DisplayLanguage) -> String {
        double
            ? language.text("Double track, as the real railway is here.", "照真實鐵路鋪成複線。")
            : language.text("Single track, as the real railway is here.", "照真實鐵路鋪成單線。")
    }
}
