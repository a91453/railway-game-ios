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
//
// Decision 489: the Danhai Light Rail's Green Mountain Line ends its day
// with all thirteen trains at Kanding, where the line runs on past the
// station into the Danhai depot; the game's ends lay at most seven
// tracks, so it was not on sale. It is bought with that depot: a lead on
// from the line's end past Kanding, turning into the real yard, and a
// siding for each train the real depot stables overnight.

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
    /// Decision 489: the end station the leads go on from, past the
    /// line's end, as the real line runs on into its depot; `nil` for
    /// leads leaving the line between its ends. A line with such a depot
    /// is not bought without it: its end has no room for its trains.
    let beyond: String?
    /// Decision 489: a light rail's yard, its sidings either side of the
    /// lead on short turnouts (``RealLineDepotLayout/Ladder/lightRail``),
    /// as tight as its real one; otherwise the depot tool's ladder.
    let compact: Bool

    /// The Sanxia depot (三峽機廠, way 619043484): the crossover of its
    /// leads (way 1156270818), its sidings' near ends (ways 1136774767 and
    /// 1136774768, the yard tracks 1320105944 and 1320105945) and their far
    /// ends. The real depot holds 33 trains; the game's sidings hold one
    /// each, as many as the trains not standing at an end overnight.
    static let sanxia = RealLineDepotSite(
        line: "sanying:LB", english: "Sanxia Depot", chinese: "三峽機廠",
        junction: (24.937315, 121.388084),
        yard: ((24.936919, 121.385823), (24.934964, 121.383852)),
        sidings: 4, beyond: nil, compact: false
    )

    /// The Danhai depot (淡海機廠, way 651032395) of the Danhai Light
    /// Rail, past Kanding: where the line's two tracks end and its leads
    /// begin (ways 605463606 and 658195694), and the middle of its yard
    /// tracks' near ends and of their far ends (the eleven through its
    /// shed, ways 690355135 to 690377825; `tools/rail-depots`). The real
    /// depot stables nine of the Green Mountain Line's thirteen trains
    /// overnight (the rest at Hongshulin); the game's sidings hold one
    /// each.
    static let danhai = RealLineDepotSite(
        line: "ntdlrt:V", english: "Danhai Depot", chinese: "淡海機廠",
        junction: (25.202117, 121.435233),
        yard: ((25.202594, 121.434160), (25.203085, 121.432866)),
        sidings: 9, beyond: "崁頂", compact: true
    )

    /// Decision 535 (PR W): the Muzha depot (木柵機廠, way 71266521) of
    /// the Wenhu Line, past Taipei Zoo: where the line's two tracks end and
    /// its leads begin (ways 194634022 and 194633990, the leads 307449195
    /// and 307449196), and the middle of its stabling tracks' near ends and
    /// of their far ends (ways 71380030, 71380035 and 71380037;
    /// `tools/rail-depots`). Its sidings hold the trains the real timetable
    /// leaves at Taipei Zoo overnight, one each, either side in turn as the
    /// Danhai depot's (22 to one side would reach some 1.5 km past the
    /// real yard).
    static let muzha = RealLineDepotSite(
        line: "trtc:BR", english: "Muzha Depot", chinese: "木柵機廠",
        junction: (24.998574, 121.579812),
        yard: ((25.001219, 121.584390), (25.001219, 121.585408)),
        sidings: 22, beyond: "動物園", compact: true
    )

    /// Decision 535 (PR W): the Neihu depot (內湖機廠, way 499801370) of
    /// the Wenhu Line, past Taipei Nangang Exhibition Center: where the
    /// line's two tracks end past its platform and its leads begin (ways
    /// 310746644 and 310746645, the leads 499750991 and 127958010), and the
    /// middle of its stabling tracks' near ends and of their far ends (ways
    /// 499756245 to 499756259). Its sidings hold the trains the real
    /// timetable leaves at Nangang Exhibition Center overnight, one each.
    static let neihu = RealLineDepotSite(
        line: "trtc:BR", english: "Neihu Depot", chinese: "內湖機廠",
        junction: (25.055245, 121.618427),
        yard: ((25.058961, 121.620931), (25.059392, 121.620496)),
        sidings: 22, beyond: "南港展覽館", compact: true
    )

    /// The real depots line `line` is bought with (decision 535: the
    /// Wenhu Line has one past each end).
    static func sites(of line: String) -> [RealLineDepotSite] {
        [sanxia, danhai, muzha, neihu].filter { $0.line == line }
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

    /// How a yard's sidings leave the lead: siding 0 is the lead straight
    /// on, and each other siding leaves the one inside it on its side
    /// (`parent`) `turnout` along the yard, `reach` before it is
    /// `offset` sidings' spacing off the lead.
    struct Ladder {
        let reach: Double
        let straight: Double
        let bothSides: Bool

        /// As the depot tool lays them (``DepotYard``): all to one side.
        static let depotTool = Ladder(reach: Double(DepotYard.reach), straight: Double(DepotYard.straight), bothSides: false)
        /// Decision 489: a light rail's, either side in turn, on turnouts
        /// 25 m long (a curve of some 30 m radius) 15 m apart.
        static let lightRail = Ladder(reach: 25 * metre, straight: 15 * metre, bothSides: true)

        func offset(_ k: Int) -> Int {
            guard bothSides else { return k }
            return k % 2 == 1 ? (k + 1) / 2 : -(k / 2)
        }

        func parent(_ k: Int) -> Int {
            guard bothSides else { return k - 1 }
            return k <= 2 ? 0 : k - 2
        }

        func turnout(_ k: Int) -> Double {
            let level = Double(abs(offset(k)))
            // The second side's turnouts a straight after the first's.
            let first = offset(k) < 0 ? 2 * straight : straight
            return first + (level - 1) * (reach + straight)
        }
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
        let lead = (points[1] - foot).unit
        // The foot's height within the grade of both turnouts, as near
        // the ground as that lets it (the chord, shorter than the track,
        // keeps the grade under); the yard's as ``yard`` sets it.
        func within(_ ranges: [(from: Int64, over: Double)], _ point: WorldVector) -> Int64? {
            let low = ranges.map { Double($0.from) - grade * $0.over }.max()!
            let high = ranges.map { Double($0.from) + grade * $0.over }.min()!
            guard low <= high else { return nil }
            return Int64(max(low, min(high, ground(point))).rounded())
        }
        guard let footHeight = within([(up.height, (foot - up.point).length), (down.height, (foot - down.point).length)], foot) else { return nil }

        // The wye: an arm leaving the second track along the line from
        // each turnout, both reaching the foot along the lead.
        let handle = 0.55 * armReach
        let footNode = RealLineAcquisition.NodeAt(piece: first, node: 1)
        let pieces = [
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
        guard let laid = yard(
            site, points: points, foot: foot, height: footHeight, at: footNode, leaving: lead, toward: path.tangent(at: j),
            first: first + pieces.count, length: length, ground: ground, in: language
        ) else { return nil }
        return (pieces + laid.pieces, laid.depot)
    }

    /// Decision 489: the depot's pieces, from piece `first` on, and the
    /// depot, its yard straight on from the line's end node `end` (its
    /// point, height and the line's way there, out past the end, which
    /// the line has turned into the real yard's).
    static func lay(
        _ site: RealLineDepotSite, beyond end: (at: RealLineAcquisition.NodeAt, point: WorldVector, height: Int64, way: WorldVector),
        first: Int, length: Int64, ground: (WorldVector) -> Double, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        guard site.sidings > 0 else { return nil }
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let yard = end.point + end.way * ladder.straight
        return self.yard(
            site, points: [end.point, yard, yard + end.way * ladder.reach], foot: end.point, height: end.height, at: end.at, leaving: end.way,
            toward: end.way, first: first, length: length, ground: ground, in: language
        )
    }

    /// The lead from `foot` (its height, its node `at`), leaving it along
    /// `leaving`, down to the real yard, and the sidings fanning out along
    /// it toward the side `toward` (the line's way at the junction) points
    /// away from, each with a platform `length` long at the same place:
    /// pieces from `first` on, and the depot.
    private static func yard(
        _ site: RealLineDepotSite, points: [WorldVector], foot: WorldVector, height footHeight: Int64, at footNode: RealLineAcquisition.NodeAt,
        leaving lead: WorldVector, toward: WorldVector, first: Int, length: Int64, ground: (WorldVector) -> Double, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        let yard = points[1], way = (points[2] - points[1]).unit
        // The yard within the grade of the foot, as near the ground as
        // that lets it.
        let low = Double(footHeight) - grade * (yard - foot).length, high = Double(footHeight) + grade * (yard - foot).length
        let yardHeight = Int64(max(low, min(high, ground(yard))).rounded())

        let count = site.sidings
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let spacing = Double(DepotYard.spacing), reach = ladder.reach
        // The sidings fan out toward the junction.
        let fan = way.normal.dot(toward) < 0 ? way.normal : way.normal.reversed
        func at(_ distance: Double, _ siding: Int) -> WorldVector { yard + way * distance + fan * (Double(ladder.offset(siding)) * spacing) }
        // The platforms past the outermost siding's bend, clear of its node.
        let start = (count > 1 ? (1..<count).map { ladder.turnout($0) + reach }.max()! : ladder.straight) + RealWorldDemo.platformMargin
        let far = start + Double(length) + RealWorldDemo.platformMargin
        // The sidings leaving each one, in order along it.
        let children = (0..<count).map { k in (1..<max(1, count)).filter { ladder.parent($0) == k } }

        // The lead and the first siding straight on from it; each other
        // siding off the one inside it, as `ladder` lays them.
        let third = (yard - foot).length / 3
        var pieces: [RealLineAcquisition.Piece] = []
        var sidingStarts: [RealLineAcquisition.PieceAt] = []
        // Where each siding's turnout stands on the siding it leaves.
        var branches: [Int: RealLineAcquisition.NodeAt] = [:]
        for siding in 0..<count {
            var points: [WorldCoordinate], curves: [TrackCurve], from: RealLineAcquisition.NodeAt, before: Double
            if siding == 0 {
                points = [coordinate(foot, footHeight), coordinate(yard, yardHeight)]
                curves = [cubic(foot, leaving: lead, yard, arriving: way, handle: third)]
                from = footNode
                before = (yard - foot).length
            } else {
                let turnout = ladder.turnout(siding)
                let branch = at(turnout, ladder.parent(siding)), bend = at(turnout + reach, siding)
                let scale = 4_096.0
                let tangent = PlanVector(dx: Int64((way.x * scale).rounded()), dy: Int64((way.y * scale).rounded()))
                guard let curve = NetworkBuilding.curve(from: branch.plan, leaving: tangent, to: bend.plan, leaving: tangent.reversed),
                      let node = branches[siding] else { return nil }
                points = [coordinate(branch, yardHeight), coordinate(bend, yardHeight)]
                curves = [curve]
                from = node
                before = (bend - branch).length - (turnout + reach)
            }
            for child in children[siding] {
                branches[child] = RealLineAcquisition.NodeAt(piece: first + siding, node: points.count)
                points.append(coordinate(at(ladder.turnout(child), siding), yardHeight))
                curves.append(.straight)
            }
            points.append(coordinate(at(far, siding), yardHeight))
            curves.append(.straight)
            pieces.append(piece(points, curves, start: from))
            sidingStarts.append(RealLineAcquisition.PieceAt(piece: first + siding, distance: before + start))
        }
        let offsets = (0..<count).map(ladder.offset)
        let station = at((start + far) / 2, 0) + fan * (Double(offsets.max()! + offsets.min()!) * spacing / 2)
        return (pieces, RealLineAcquisition.Depot(name: site.name(in: language), at: station.plan, platforms: sidingStarts, length: length))
    }

    private static func coordinate(_ point: WorldVector, _ height: Int64) -> WorldCoordinate {
        let plan = point.plan
        return WorldCoordinate(x: plan.x, y: plan.y, z: height)
    }

    private static func cubic(_ a: WorldVector, leaving: WorldVector, _ b: WorldVector, arriving: WorldVector, handle: Double) -> TrackCurve {
        .cubic((a + leaving * handle).plan, (b - arriving * handle).plan)
    }

    private static func piece(
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
}
