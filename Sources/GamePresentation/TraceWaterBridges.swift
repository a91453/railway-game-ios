import Foundation
import GameCore

// Bridges over flat water on a traced stretch (decision 974).

extension GameSession {
    /// Decision 974: the stretches of `path`, by distance along it, that
    /// cross water on flat ground with `rise` over it: each run of samples
    /// over `water` (as ``TrackRise`` groups them) and the sample beyond
    /// it at either end, where the track is at least
    /// ``TrackRise/waterClearance`` over the ground all the way (where no
    /// grade reached a bridge, the track is level over the water and none
    /// is laid). An end within ``RealWorldDemo/shortestEdge`` of one in
    /// `forced` moves to it, as do two stretches that near each other;
    /// none reaches into `keepOut` (the platforms) and its margin, and
    /// each end is where `rise` allows a node.
    static func flatWaterBridges(
        _ rise: TrackRise, along path: WorldPath, water: (WorldVector) -> Bool, forced: [Double], keepOut: [ClosedRange<Double>]
    ) -> [ClosedRange<Double>] {
        let distances = rise.distances
        var runs: [ClosedRange<Int>] = []
        for index in distances.indices where water(path.point(at: distances[index])) {
            if let last = runs.last, last.upperBound >= index - 2 {
                runs[runs.count - 1] = last.lowerBound...index
            } else {
                runs.append(index...index)
            }
        }
        let clearance = TrackRise.waterClearance - 0.5
        let shortest = RealWorldDemo.shortestEdge
        func snapped(_ distance: Double) -> Double {
            forced.first { abs($0 - distance) < shortest } ?? distance
        }
        var found: [ClosedRange<Double>] = []
        for run in runs {
            let low = max(0, run.lowerBound - 1), high = min(distances.count - 1, run.upperBound + 1)
            guard (low...high).allSatisfy({ rise.heights[$0] - rise.ground[$0] >= clearance }) else { continue }
            let range = snapped(distances[low])...snapped(distances[high])
            if let last = found.last, range.lowerBound - last.upperBound < 2 * shortest {
                found[found.count - 1] = last.lowerBound...range.upperBound
            } else {
                found.append(range)
            }
        }
        let margin = RealWorldDemo.platformMargin
        let zones = keepOut.map { ($0.lowerBound - margin)...($0.upperBound + margin) }
        return found.filter { range in
            range.upperBound - range.lowerBound >= shortest && !zones.contains { $0.overlaps(range) }
                && [range.lowerBound, range.upperBound].allSatisfy { end in forced.contains(end) || rise.allowsNode(at: end) }
        }
    }

    /// Decision 974: whether the edge from `start` to `end` along the
    /// path, its ends at `heights`, lies within one of `bridges` and is
    /// over the ground of `world` at both ends, by
    /// ``RealLineAcquisition/shortBridgeLift`` to
    /// ``TrackSectionRules/highestDeck``.
    static func bridgesFlatWater(
        from start: Double, to end: Double, heights: (WorldCoordinate, WorldCoordinate), bridges: [ClosedRange<Double>], in world: GameWorld
    ) -> Bool {
        func over(_ point: WorldCoordinate) -> Bool {
            let z = point.z - (world.groundHeight(at: point.plan) ?? 0)
            return z >= RealLineAcquisition.shortBridgeLift && z <= TrackSectionRules.highestDeck
        }
        return bridges.contains { $0.lowerBound - 1 <= start && end <= $0.upperBound + 1 } && over(heights.0) && over(heights.1)
    }
}
