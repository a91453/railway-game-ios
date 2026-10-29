import GameCore

// Decision 479: a real line bought with its real depot. The Sanying
// Line's trains stood overnight on the main track at stations between its
// ends, and each morning the first trains waited behind them; the real
// line keeps its trains in the Sanxia depot, beside the line between
// Hengxi and Longpu, and at its two ends. The line is bought with the
// depot where the real one is: a wye off the track toward the terminal,
// where the real leads leave it, a lead down to the real yard, and a
// siding with a platform for each train that does not stand at an end
// overnight. The depot is the line's (decision 221): its trains run in
// and out of it empty, so the real timetable's positioning runs to and
// from the stations between go.
//
// The real leads leave the line toward the terminal only, and the real
// trains change ends in the depot; the game's trains do not reverse on
// their way, so the wye's second arm, toward the junction, and the two
// crossovers that bring a train from the other track to the wye and back
// are the game's own.

/// A real depot a line is bought with: where its leads leave the line and
/// where its yard runs, from OpenStreetMap (ODbL).
struct RealLineDepotSite: Sendable {
    let line: String
    let english: String
    let chinese: String
    /// Where the leads leave the line.
    let junction: (latitude: Double, longitude: Double)
    /// The yard's near end and its far end.
    let yard: (start: (latitude: Double, longitude: Double), end: (latitude: Double, longitude: Double))
    let sidings: Int

    /// The Sanxia depot (三峽機廠, way 619043484): the crossover of its
    /// leads (way 1156270818), its sidings' near ends (ways 1136774767 and
    /// 1136774768, the yard tracks 1320105944 and 1320105945) and their far
    /// ends. The real depot holds 33 trains; the game's sidings hold one
    /// each, as many as the trains not standing at an end overnight.
    static let sanxia = RealLineDepotSite(
        line: "sanying:LB", english: "Sanxia Depot", chinese: "三峽機廠",
        junction: (24.937315, 121.388084),
        yard: ((24.936919, 121.385823), (24.934964, 121.383852)),
        sidings: 4
    )

    static func site(of line: String) -> RealLineDepotSite? {
        [sanxia].first { $0.line == line }
    }

    func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }
}

/// How a depot's track lies along a double line's path, `j` along it where
/// the leads leave.
enum RealLineDepotLayout {
    static let metre = RealLineAcquisition.metre
    /// How far along the line each arm of the wye runs, and how far off it
    /// the wye's foot stands.
    static let armReach = 70 * metre
    /// The lead's grade down to the yard: under GameCore's 4 %.
    static let grade = 0.03
    /// Straight between a crossover and a turnout of the wye.
    static let gap = RealWorldDemo.shortestEdge

    /// The main track's nodes: the crossover to the first track before the
    /// wye (two), the wye's arms, the crossover from the first track after
    /// it (two), in order along the path.
    static func marks(at j: Double) -> [Double] {
        let ramp = HighSpeedDemo.rampLength
        return [j - gap - ramp, j - gap, j, j + 2 * armReach, j + 2 * armReach + gap, j + 2 * armReach + gap + ramp]
    }

    /// Siding `k` (from 0) leaves siding `k − 1` this far along the yard,
    /// as the depot tool lays them (``DepotYard``).
    static func turnout(_ k: Int) -> Double {
        let straight = Double(DepotYard.straight), reach = Double(DepotYard.reach)
        return straight + Double(k - 1) * (reach + straight)
    }
}

extension RealLineAcquisition {
    /// Decision 479: a depot bought with the line, its sidings among the
    /// pieces: its name, where it stands, and the start of each siding's
    /// platform, `length` long.
    public struct Depot: Hashable, Sendable, Codable {
        public let name: String
        public let at: PlanPoint
        public let platforms: [PieceAt]
        public let length: Int64
    }
}

extension RealLineDepotLayout {
    /// The depot's pieces, from piece `first` on, and the depot: the wye
    /// off the second track (piece 1) at `marks[2]` and `marks[3]` (see
    /// ``marks(at:)``), its foot the arms' reach off the line between
    /// them, the lead from there down to the real yard, and the sidings
    /// fanning out along it, each with a platform `length` long at the
    /// same place. `nil` where the lead cannot get down at its grade.
    static func lay(
        _ site: RealLineDepotSite, points: [WorldVector], along path: WorldPath, at j: Double, second: RealWorldDemo.TrackPlan,
        marks: [(main: Int, second: Int)], first: Int, length: Int64, ground: (WorldVector) -> Double, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        guard marks.count == 6, points.count == 3, site.sidings > 0 else { return nil }
        func node(_ mark: (main: Int, second: Int)) -> (point: WorldVector, direction: WorldVector, height: Int64) {
            (WorldVector(second.nodes[mark.second].point), second.nodes[mark.second].direction.unit, second.heights[mark.second])
        }
        let up = node(marks[2]), down = node(marks[3])
        let middle = j + armReach
        let foot = path.point(at: middle) + path.tangent(at: middle).normal * (-HighSpeedDemo.trackOffset - armReach)
        let yard = points[1], way = (points[2] - points[1]).unit
        let lead = (yard - foot).unit
        // The heights: the foot within the grade of both turnouts, the
        // yard within it of the foot; each as near the ground as that
        // lets it (the chord, shorter than the track, keeps the grade
        // under).
        func within(_ ranges: [(from: Int64, over: Double)], _ point: WorldVector) -> Int64? {
            let low = ranges.map { Double($0.from) - grade * $0.over }.max()!
            let high = ranges.map { Double($0.from) + grade * $0.over }.min()!
            guard low <= high else { return nil }
            return Int64(max(low, min(high, ground(point))).rounded())
        }
        guard let footHeight = within([(up.height, (foot - up.point).length), (down.height, (foot - down.point).length)], foot),
              let yardHeight = within([(footHeight, (yard - foot).length)], yard)
        else { return nil }

        let count = site.sidings
        let spacing = Double(DepotYard.spacing), reach = Double(DepotYard.reach)
        // The sidings fan out toward the junction.
        let fan = way.normal.dot(path.tangent(at: j)) < 0 ? way.normal : way.normal.reversed
        func at(_ distance: Double, _ siding: Int) -> WorldVector { yard + way * distance + fan * (Double(siding) * spacing) }
        // The platforms past the outer siding's bend, clear of its node.
        let start = (count > 1 ? turnout(count - 1) + reach : Double(DepotYard.straight)) + RealWorldDemo.platformMargin
        let far = start + Double(length) + RealWorldDemo.platformMargin

        func coordinate(_ point: WorldVector, _ height: Int64) -> WorldCoordinate {
            let plan = point.plan
            return WorldCoordinate(x: plan.x, y: plan.y, z: height)
        }
        func cubic(_ a: WorldVector, leaving: WorldVector, _ b: WorldVector, arriving: WorldVector, handle: Double) -> TrackCurve {
            .cubic((a + leaving * handle).plan, (b - arriving * handle).plan)
        }
        func piece(
            _ points: [WorldCoordinate], _ curves: [TrackCurve], start: RealLineAcquisition.NodeAt?, end: RealLineAcquisition.NodeAt? = nil
        ) -> RealLineAcquisition.Piece {
            var distances = [0.0]
            for (a, b) in zip(points, points.dropFirst()) {
                distances.append(distances[distances.count - 1] + (WorldVector(b.plan) - WorldVector(a.plan)).length)
            }
            let ground = curves.indices.flatMap { index -> [PlanPoint] in
                let surveyed = TrackGeometry(from: points[index], to: points[index + 1], curve: curves[index]).map(NetworkBuilding.surveyedPoints(of:)) ?? []
                return [points[index].plan, points[index + 1].plan] + surveyed
            }
            return RealLineAcquisition.Piece(
                nodes: points, start: start, end: end, curves: curves, distances: distances, structure: .automatic, together: true, ground: ground
            )
        }

        // The wye: an arm leaving the second track along the line from
        // each turnout, both reaching the foot along the lead.
        let handle = 0.55 * armReach
        let footNode = RealLineAcquisition.NodeAt(piece: first, node: 1)
        var pieces = [
            piece(
                [coordinate(up.point, up.height), coordinate(foot, footHeight)],
                [cubic(up.point, leaving: up.direction, foot, arriving: lead, handle: handle)],
                start: RealLineAcquisition.NodeAt(piece: 1, node: marks[2].second)
            ),
            piece(
                [coordinate(down.point, down.height), coordinate(foot, footHeight)],
                [cubic(down.point, leaving: down.direction.reversed, foot, arriving: lead, handle: handle)],
                start: RealLineAcquisition.NodeAt(piece: 1, node: marks[3].second), end: footNode
            ),
        ]
        // The lead and the first siding straight on from it; each other
        // siding off the one inside it, as the depot tool lays them.
        let third = (yard - foot).length / 3
        var sidingStarts: [RealLineAcquisition.PieceAt] = []
        for siding in 0..<count {
            var points: [WorldCoordinate], curves: [TrackCurve], from: RealLineAcquisition.NodeAt, before: Double
            if siding == 0 {
                points = [coordinate(foot, footHeight), coordinate(yard, yardHeight)]
                curves = [cubic(foot, leaving: lead, yard, arriving: way, handle: third)]
                from = footNode
                before = (yard - foot).length
            } else {
                let branch = at(turnout(siding), siding - 1), bend = at(turnout(siding) + reach, siding)
                let scale = 4_096.0
                let tangent = PlanVector(dx: Int64((way.x * scale).rounded()), dy: Int64((way.y * scale).rounded()))
                guard let curve = NetworkBuilding.curve(from: branch.plan, leaving: tangent, to: bend.plan, leaving: tangent.reversed) else { return nil }
                points = [coordinate(branch, yardHeight), coordinate(bend, yardHeight)]
                curves = [curve]
                from = RealLineAcquisition.NodeAt(piece: first + 1 + siding, node: 2)
                before = (bend - branch).length - (turnout(siding) + reach)
            }
            if siding < count - 1 {
                points.append(coordinate(at(turnout(siding + 1), siding), yardHeight))
                curves.append(.straight)
            }
            points.append(coordinate(at(far, siding), yardHeight))
            curves.append(.straight)
            pieces.append(piece(points, curves, start: from))
            sidingStarts.append(RealLineAcquisition.PieceAt(piece: first + 2 + siding, distance: before + start))
        }
        let station = at((start + far) / 2, 0) + fan * (Double(count - 1) * spacing / 2)
        return (pieces, RealLineAcquisition.Depot(name: site.name(in: language), at: station.plan, platforms: sidingStarts, length: length))
    }
}
