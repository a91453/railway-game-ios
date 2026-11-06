import Foundation
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
    /// Decision 602: a yard laid as its real one fans out
    /// (``RealLineDepotLayout/Fan``): its lead along the real leads, its
    /// sidings along the real stabling tracks; `nil` for a ladder.
    var fan: Fan? = nil

    /// Decision 602: where a fanned yard's lead runs and how its sidings
    /// split. The lead goes on from the line's end through `leads` (the
    /// real leads' way, in order) to `throat`, where it runs the way the
    /// real stabling tracks do (``yard``'s start to its end, which here
    /// are the middle of their near ends and of their far ends); the
    /// sidings fan out from there, `towardShed` of them to the side the
    /// real stabling tracks lie (from the throat) and the rest, but the
    /// one straight on, to the other.
    ///
    /// `second`: the real second lead, as each of the line's two tracks
    /// runs on past the end station into a lead of its own (the author:
    /// "why is there only one way out?"): a point on it, which tells the
    /// side it lies, and where it joins the first (or, where it reaches
    /// the yard by another way, the point the game's joins the first
    /// short of the throat). It is laid beside the first lead from past
    /// the end station's loops to there, as the line's second track is
    /// (``RealWorldDemo/TrackPlan/init(beside:at:offsets:following:)``).
    struct Fan: Sendable {
        let leads: [(latitude: Double, longitude: Double)]
        let throat: (latitude: Double, longitude: Double)
        let towardShed: Int
        var second: (on: (latitude: Double, longitude: Double), joins: (latitude: Double, longitude: Double))? = nil
        /// Decision 602 (continued): the real platform of the end station
        /// the depot stands beyond, where the line as drawn stops short of
        /// it and the station's point is another line's.
        var platform: (latitude: Double, longitude: Double)? = nil
    }

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

    /// Decision 535 (PR W): the Muzha depot (木柵機廠, landuse way
    /// 71266521) of the Wenhu Line, past Taipei Zoo: where the line's two
    /// tracks end and its leads begin (ways 194634022 and 194633990).
    /// Decision 602: laid as the real yard lies (`tools/rail-depots`): the
    /// lead along the real north lead (ways 307449196 and 194633991)
    /// north-east by the Jingmei River and round into the way of the real
    /// stabling tracks
    /// (the twelve through the shed, ways 1342641748 to 1342641759, some
    /// 195 m long, 4 m apart, running south-east; ``yard`` is the middle
    /// of their north-west ends and of their south-east ends), the
    /// sidings fanning out from where that lead turns, most of them
    /// toward the shed. Its sidings hold the 22 trains the real timetable
    /// leaves at Taipei Zoo overnight, one each, so the yard is wider than
    /// the real shed and its tracks shorter; it stays within the depot's
    /// ground, clear of the river (decisions 549 continued and 552 had laid
    /// a ladder some 380 m east, over the river).
    static let muzha = RealLineDepotSite(
        line: "trtc:BR", english: "Muzha Depot", chinese: "木柵機廠",
        junction: (24.998574, 121.579812),
        yard: ((25.001307, 121.585648), (25.000244, 121.587180)),
        sidings: 22, beyond: "動物園", compact: true,
        fan: Fan(
            leads: [(24.998946, 121.580409), (25.000240, 121.582551), (25.000499, 121.583398), (25.000805, 121.583812)],
            throat: (25.001270, 121.585081), towardShed: 12,
            // The real south lead (way 307449195) reaches the shed's south
            // side on its own; the game's joins the first 85 m short of
            // the throat (on way 194633991).
            second: (on: (24.999391, 121.581198), joins: (25.001141, 121.584254))
        )
    )

    /// Decision 535 (PR W): the Neihu depot (內湖機廠, landuse way
    /// 499801370) of the Wenhu Line, past Taipei Nangang Exhibition
    /// Center: where the line's two tracks end past its platform and its
    /// leads begin (ways 310746644 and 310746645). Decision 602: laid as
    /// the real yard lies (`tools/rail-depots`): the lead along the real
    /// leads (ways 127958010 and 198181448) east, north-east and round
    /// north-west into the way of the real stabling tracks (the sixteen
    /// through the shed, ways 1316259201 to 1316259216, some 148 m long,
    /// 4 m apart; ``yard`` is the middle of their south-east ends and of
    /// their north-west ends), the sidings fanning out where the real ones
    /// do. Its sidings hold the 22 trains the real timetable leaves at
    /// Nangang Exhibition Center overnight, one each (the depot tool's
    /// ladder had run on north-west for over a kilometre).
    static let neihu = RealLineDepotSite(
        line: "trtc:BR", english: "Neihu Depot", chinese: "內湖機廠",
        junction: (25.055245, 121.618427),
        yard: ((25.059395, 121.620393), (25.060406, 121.619446)),
        sidings: 22, beyond: "南港展覽館", compact: false,
        fan: Fan(
            leads: [(25.055384, 121.619030), (25.056119, 121.619469), (25.056682, 121.620048), (25.057162, 121.620983), (25.057809, 121.621873), (25.058070, 121.621785)],
            throat: (25.058581, 121.621212), towardShed: 13,
            // The real second lead (way 499750991) joins the first where
            // way 198181448 begins toward the shed.
            second: (on: (25.056145, 121.619426), joins: (25.057583, 121.621691)),
            // The Wenhu Line's own platform (OSM node 3501186380, between
            // its stop positions 7093644633 and 7093644634), some 90 m
            // east of the point `trtc.json` shares with the Bannan Line;
            // the drawn line (`track_lines.geojson`) ends 86 m short of it.
            platform: (25.055316, 121.617896)
        )
    )

    /// Decision 535 (continued, ANKENGDEPOT): the Ankeng depot (安坑機廠,
    /// landuse way 724086719) of the Ankeng LRT, past Shuangcheng: a strip
    /// some 300 m long west of the line's run on past the station. The real
    /// leads leave the line's end, loop round west and north and come into
    /// the stabling tracks from their north end, the yard lying back beside
    /// the line; the game's lead does not turn back on itself, so it leaves
    /// at the real crossover past the station (ways 1137758430 and
    /// 1137758431, their middle) and curves round into the depot, its yard
    /// running on from the real stabling tracks' north ends (their middle,
    /// ways 1140796066 to 1140796072 and 1140796074 to 1140796078) toward
    /// a point level with the depot's north end, some 60 m east of its
    /// northernmost node, so that the yard as laid lies the way the real
    /// stabling tracks do, in the depot's north-west half
    /// (`tools/rail-depots`). The real timetable stands six of the seven
    /// trains at Shuangcheng overnight and one at Shisizhang; seven
    /// sidings, as the real depot holds them all, one spare.
    static let ankeng = RealLineDepotSite(
        line: "ntalrt:K", english: "Ankeng Depot", chinese: "安坑機廠",
        junction: (24.943964, 121.488158),
        yard: ((24.944371, 121.486844), (24.945657, 121.487100)),
        sidings: 7, beyond: "雙城", compact: true
    )

    /// Decision 556: the Luzhu depot (蘆竹機廠) of the Taoyuan Airport
    /// MRT, beside the line between Shanbi and Kengkou, south of it. Its
    /// real yard (the yard tracks round 25.083, 121.270, ways 497336750 to
    /// 497400702, 499772313 to 499814055, 603083920 and 603083921;
    /// `tools/rail-depots`) lies some 100 to 350 m off the line, its leads
    /// leaving it toward Kengkou; the game's leave at a point on the line
    /// east of the yard (way 111203717), so the wye stands clear of
    /// Shanbi's and Kengkou's platforms, its yard laid westward through
    /// the real one. Its sidings hold the trains the real timetable leaves
    /// overnight at the stations from Sanchong to the airport, one each,
    /// as far as they go; the rest stand in the Qingpu depot.
    static let luzhu = RealLineDepotSite(
        line: "tymc:A", english: "Luzhu Depot", chinese: "蘆竹機廠",
        junction: (25.081437, 121.278549),
        yard: ((25.082700, 121.272200), (25.082200, 121.268600)),
        sidings: 16, beyond: nil, compact: false
    )

    /// Decision 556: the Qingpu depot (青埔機廠, landuse way 461638223),
    /// the Taoyuan Airport MRT's main depot, beside the line east of it
    /// between Hengshan and Linghang. Its stabling tracks (ways 499824857
    /// to 499824866 and 499831993 to 499832001) run south-east beside the
    /// line from round 25.0263, 121.2200 to 25.0243, 121.2215, its leads
    /// leaving the line where it runs past (ways 497402819, 497405855,
    /// 497405856, 542844200); the game's leave it further north (way
    /// 479042997, 25.0278, 121.2171), clear of Linghang's platforms,
    /// the yard laid from the stabling tracks' north-west ends to their
    /// south-east ends. Its sidings either side of the lead on short
    /// turnouts (``compact``), as its real ladders are short: on the
    /// depot tool's one-sided ladder the yard ran some 900 m on and
    /// crossed the line where it bends toward it past Linghang.
    static let qingpu = RealLineDepotSite(
        line: "tymc:A", english: "Qingpu Depot", chinese: "青埔機廠",
        junction: (25.027806, 121.217032),
        yard: ((25.026300, 121.220050), (25.024350, 121.221500)),
        sidings: 12, beyond: nil, compact: true
    )

    /// The real depots line `line` is bought with (decision 535: the
    /// Wenhu Line has one past each end; its continuation, the Ankeng LRT
    /// one past Shuangcheng; decision 556, the Taoyuan Airport MRT two
    /// beside the line).
    static func sites(of line: String) -> [RealLineDepotSite] {
        [sanxia, danhai, muzha, neihu, ankeng, luzhu, qingpu].filter { $0.line == line }
    }

    /// Decision 556: whether its sidings fan out away from the line, not
    /// toward its junction: the Taoyuan Airport MRT's yards run almost
    /// alongside it, and fanned toward the junction the Qingpu yard's
    /// crossed the line's own track.
    var fansAwayFromLine: Bool { line == "tymc:A" }

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
    /// Decision 549 (continued): how much further along its way a yard
    /// may move for its lead to climb clear over water.
    static let furthestYardShift = 240 * metre
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
        marks: [(main: Int, second: Int)], first: Int, length: Int64, ground: (WorldVector) -> Double,
        water: (WorldVector) -> Bool = { _ in false }, in language: DisplayLanguage
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
            site, points: points, foot: foot, height: footHeight, at: footNode, leaving: lead,
            toward: site.fansAwayFromLine ? path.point(at: path.nearest(points[1]).along) - points[1] : path.tangent(at: j),
            first: first + pieces.count, length: length, ground: ground, water: water, in: language
        ) else { return nil }
        return (pieces + laid.pieces, laid.depot)
    }

    /// Where along a yard of `site` its platforms `length` long start and
    /// end: past the outermost siding's bend, clear of its node.
    static func extent(of site: RealLineDepotSite, length: Int64) -> (start: Double, far: Double) {
        let count = site.sidings
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let start = (count > 1 ? (1..<count).map { ladder.turnout($0) + ladder.reach }.max()! : ladder.straight) + RealWorldDemo.platformMargin
        return (start, start + Double(length) + RealWorldDemo.platformMargin)
    }

    /// Decision 549 (continued): the ground a yard of `site` laid past a
    /// line's end (``lay(_:beyond:first:length:ground:water:in:)``) may
    /// stand on, every `step` either side of the real yard's way
    /// (`points`, ``RealLineDepotSite``'s junction and yard) from `back`
    /// short of its near end, as far as it may be moved along it: the
    /// offer reads it in before it lays the yard, which otherwise reads
    /// no ground (and no height over the water) past the real yard.
    /// Decision 602: a fanned yard's, from `throat`, the real stabling
    /// tracks' way, either side as wide as its wider side.
    static func groundSamples(beyond points: [WorldVector], site: RealLineDepotSite, length: Int64, back: Double, step: Double, throat: WorldVector? = nil) -> [PlanPoint] {
        guard site.beyond != nil else { return [] }
        if site.fan != nil, let throat, points.count == 3 {
            let way = (points[2] - points[1]).unit, origin = throat - way * back
            let along = back + Fan.ramp + Fan.extent(of: site, length: length).far
            let sides = Fan.sides(of: site)
            let across = Double(max(sides.toward, sides.away) + 1) * Fan.spacing
            return (0...Int(along / step)).flatMap { a in
                (-Int(across / step) - 1...Int(across / step) + 1).map { c in
                    (origin + way * (Double(a) * step) + way.normal * (Double(c) * step)).plan
                }
            }
        }
        return groundSamples(of: points, site: site, length: length, back: back, step: step)
    }

    /// Decision 556: ``groundSamples(beyond:site:length:back:step:)`` of
    /// a yard beside the line too, its ladder fanning either way.
    static func groundSamples(of points: [WorldVector], site: RealLineDepotSite, length: Int64, back: Double, step: Double) -> [PlanPoint] {
        guard points.count == 3 else { return [] }
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let way = (points[2] - points[1]).unit, origin = points[1] - way * back
        let along = back + ladder.straight + furthestYardShift + extent(of: site, length: length).far
        let widest = (0..<max(1, site.sidings)).map { abs(ladder.offset($0)) }.max() ?? 0
        let across = Double(widest + 1) * Double(DepotYard.spacing)
        return (0...Int(along / step)).flatMap { a in
            (-Int(across / step) - 1...Int(across / step) + 1).map { c in
                (origin + way * (Double(a) * step) + way.normal * (Double(c) * step)).plan
            }
        }
    }

    /// Decision 489: the depot's pieces, from piece `first` on, and the
    /// depot, its yard straight on from the line's end node `end` (its
    /// point, height and the line's way there, out past the end, which
    /// the line has turned into the real yard's).
    /// Decision 602: a site with a ``RealLineDepotSite/fan`` is fanned
    /// out from the end, most of its sidings toward `shed`.
    static func lay(
        _ site: RealLineDepotSite, beyond end: (at: RealLineAcquisition.NodeAt, point: WorldVector, height: Int64, way: WorldVector),
        shed: WorldVector? = nil, first: Int, length: Int64, ground: (WorldVector) -> Double, water: (WorldVector) -> Bool = { _ in false },
        in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        guard site.sidings > 0 else { return nil }
        if site.fan != nil, let shed {
            return fanned(site, from: end, shed: shed, first: first, length: length, ground: ground, water: water, in: language)
        }
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let yard = end.point + end.way * ladder.straight
        return self.yard(
            site, points: [end.point, yard, yard + end.way * ladder.reach], foot: end.point, height: end.height, at: end.at, leaving: end.way,
            toward: end.way, first: first, length: length, ground: ground, water: water, in: language
        )
    }

    /// The lead from `foot` (its height, its node `at`), leaving it along
    /// `leaving`, down to the real yard, and the sidings fanning out along
    /// it toward the side `toward` (the line's way at the junction) points
    /// away from, each with a platform `length` long at the same place:
    /// pieces from `first` on, and the depot.
    private static func yard(
        _ site: RealLineDepotSite, points: [WorldVector], foot: WorldVector, height footHeight: Int64, at footNode: RealLineAcquisition.NodeAt,
        leaving lead: WorldVector, toward: WorldVector, first: Int, length: Int64, ground: (WorldVector) -> Double,
        water: (WorldVector) -> Bool, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        let way = (points[2] - points[1]).unit
        let count = site.sidings
        let ladder = site.compact ? Ladder.lightRail : Ladder.depotTool
        let spacing = Double(DepotYard.spacing), reach = ladder.reach
        // The sidings fan out toward the junction.
        let fan = way.normal.dot(toward) < 0 ? way.normal : way.normal.reversed
        let (start, far) = extent(of: site, length: length)
        // The yard within the grade of the foot, as near the ground as
        // that lets it. Decision 549 (continued): and clear over any water
        // under its lead and sidings, as the line's own track is
        // (``TrackRise/waterClearance``), the yard moved on along its way,
        // a lead's length at a time, until the lead's grade reaches that
        // high; where no place within ``furthestYardShift`` does, where it
        // was (and GameCore refuses the track over the water). The Muzha
        // depot's sidings cross the Jingmei River.
        func placed(_ shift: Double) -> (yard: WorldVector, height: Double, clear: Bool) {
            let yard = points[1] + way * shift
            let climb = grade * (yard - foot).length
            let low = Double(footHeight) - climb, high = Double(footHeight) + climb
            let step = TrackRise.spacing
            let ends = [(foot, yard)] + (0..<count).map { siding in
                (0...1).map { yard + way * (Double($0) * far) + fan * (Double(ladder.offset(siding)) * spacing) }
            }.map { ($0[0], $0[1]) }
            let wet = ends.flatMap { a, b in
                (0...Int((b - a).length / step)).map { a + (b - a).unit * (Double($0) * step) }
            }.filter(water)
            let needed = wet.map { ground($0) + TrackRise.waterClearance }.max() ?? -.infinity
            let height = max(low, min(high, max(ground(yard), needed)))
            return (yard, height, height >= needed)
        }
        var chosen = placed(0)
        for shift in stride(from: TrackRise.spacing, through: Self.furthestYardShift, by: TrackRise.spacing) where !chosen.clear {
            let moved = placed(shift)
            if moved.clear { chosen = moved }
        }
        let yard = chosen.yard, yardHeight = Int64(chosen.height.rounded())
        func at(_ distance: Double, _ siding: Int) -> WorldVector { yard + way * distance + fan * (Double(ladder.offset(siding)) * spacing) }

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

    /// Decision 602: a fanned yard's shape. The lead runs on `ramp` from
    /// the line's end (its grade takes the yard toward the ground), then
    /// sidings leave it: on each side the first by an S-curve `firstReach`
    /// long, `firstAfter` along, and the rest off a ladder track that turns
    /// out `angle` on curves of `radius`, each siding curving back off it
    /// into the yard's way; the second side's turnouts `sideGap` after the
    /// first's. All the sidings' platforms stand side by side past the
    /// last curve, as the real stabling tracks do.
    enum Fan {
        static let ramp = 30 * metre
        static let radius = 30 * metre
        static let angle = Double.pi / 6
        static let firstAfter = 8 * metre
        static let firstReach = 30 * metre
        static let sideGap = 16 * metre
        static let spacing = Double(DepotYard.spacing)

        /// How far a curve off the ladder (or onto it) runs along the
        /// yard, and how far it moves across it.
        static var arcAlong: Double { radius * sin(angle) }
        static var arcAcross: Double { radius * (1 - cos(angle)) }

        /// How many sidings each side, the one straight on not counted:
        /// toward the real stabling tracks and away.
        static func sides(of site: RealLineDepotSite) -> (toward: Int, away: Int) {
            let toward = min(max(site.fan?.towardShed ?? 0, 0), max(site.sidings - 1, 0))
            return (toward, max(site.sidings - 1 - toward, 0))
        }

        /// Where along the yard, from the ramp's end, siding `k` (from 1)
        /// of a side whose turnouts start `g` along leaves its ladder.
        static func ladderTurnout(_ k: Int, from g: Double) -> Double {
            g + arcAlong + (spacing * Double(k) - 2 * arcAcross) / tan(angle)
        }

        /// Where along the yard, from the ramp's end, the curves of a side
        /// with `count` sidings starting `g` along end.
        static func lastCurve(_ count: Int, from g: Double) -> Double {
            switch count {
            case 0: g
            case 1: g + firstAfter + firstReach
            default: ladderTurnout(count, from: g) + arcAlong
            }
        }

        /// The platforms' start and the sidings' far end, along the yard
        /// from the ramp's end.
        static func extent(of site: RealLineDepotSite, length: Int64) -> (start: Double, far: Double) {
            let (toward, away) = sides(of: site)
            let (first, second) = toward >= away ? (toward, away) : (away, toward)
            let start = max(lastCurve(first, from: 0), lastCurve(second, from: sideGap), sideGap + firstAfter) + RealWorldDemo.platformMargin
            return (start, start + Double(length) + RealWorldDemo.platformMargin)
        }

        /// The lead from the line's end at `junction`, leaving it along
        /// `way`, through the real leads (`leads`) to `throat`, arriving
        /// there along the yard's way `yardWay`: a smooth curve through
        /// them, every 4 m or so.
        static func lead(from junction: WorldVector, leaving way: WorldVector, through leads: [WorldVector], to throat: WorldVector, yardWay: WorldVector) -> [WorldVector] {
            let approach = throat - yardWay * (20 * metre)
            let points = [junction] + leads + [approach, throat]
            let tangents = points.indices.map { index -> WorldVector in
                if index == 0 { return way.unit }
                if index >= points.count - 2 { return yardWay.unit }
                return (points[index + 1] - points[index - 1]).unit
            }
            var curve: [WorldVector] = []
            for index in points.indices.dropLast() {
                let a = points[index], b = points[index + 1], chord = (b - a).length
                let steps = max(2, Int((chord / (4 * metre)).rounded(.up)))
                let ta = tangents[index] * chord, tb = tangents[index + 1] * chord
                for step in 1...steps {
                    let t = Double(step) / Double(steps), t2 = t * t, t3 = t2 * t
                    let h00 = 2 * t3 - 3 * t2 + 1, h10 = t3 - 2 * t2 + t, h01 = -2 * t3 + 3 * t2, h11 = t3 - t2
                    curve.append(a * h00 + ta * h10 + b * h01 + tb * h11)
                }
            }
            return [junction] + curve
        }
    }

    /// Decision 602: the depot's pieces, from piece `first` on, and the
    /// depot, its yard fanned out (``Fan``) from the line's end node `end`
    /// along its way there, most of its sidings toward `shed` (the middle
    /// of the real stabling tracks).
    private static func fanned(
        _ site: RealLineDepotSite, from end: (at: RealLineAcquisition.NodeAt, point: WorldVector, height: Int64, way: WorldVector),
        shed: WorldVector, first: Int, length: Int64, ground: (WorldVector) -> Double, water: (WorldVector) -> Bool, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        let way = end.way.unit, start = end.point + way * Fan.ramp
        let toward: Double = (shed - end.point).dot(way.normal) >= 0 ? 1 : -1
        let (towardCount, awayCount) = Fan.sides(of: site)
        let (platformStart, far) = Fan.extent(of: site, length: length)
        let spacing = Fan.spacing, arcAlong = Fan.arcAlong, arcAcross = Fan.arcAcross
        func at(_ along: Double, _ across: Double) -> WorldVector { start + way * along + way.normal * across }

        // The yard level, within the ramp's grade of the line's end, as
        // near the ground as that lets it, and clear over any water under
        // it as the line's own track is (``TrackRise/waterClearance``).
        let widest = Double(max(towardCount, awayCount) + 1) * spacing
        let wet = stride(from: 0, through: far, by: TrackRise.spacing).flatMap { along in
            stride(from: -widest, through: widest, by: TrackRise.spacing).map { at(along, $0) }
        }.filter(water)
        let needed = wet.map { ground($0) + TrackRise.waterClearance }.max() ?? -.infinity
        let climb = RealLineDepotLayout.grade * Fan.ramp
        let height = Int64(max(Double(end.height) - climb, min(Double(end.height) + climb, max(ground(start), needed))).rounded())

        // Each side: its sign across the yard, its sidings, where its
        // turnouts start along the ramp's end; the side with more first.
        let sides: [(sign: Double, count: Int, from: Double)] = {
            let a = (sign: toward, count: towardCount), b = (sign: -toward, count: awayCount)
            let (one, two) = a.count >= b.count ? (a, b) : (b, a)
            return [(one.sign, one.count, 0), (two.sign, two.count, Fan.sideGap)]
        }()
        let handle = 4.0 / 3 * tan(Fan.angle / 4) * Fan.radius

        // The lead and the siding straight on: the ramp, then the
        // turnouts of the sidings off it, then on to the far end.
        var turnouts: [Double] = [0]
        for side in sides where side.count >= 1 {
            turnouts.append(side.from + Fan.firstAfter)
            if side.count >= 2 { turnouts.append(side.from) }
        }
        turnouts = Array(Set(turnouts)).sorted()
        var straightPoints = [coordinate(end.point, end.height)] + turnouts.map { coordinate(at($0, 0), height) }
        straightPoints.append(coordinate(at(far, 0), height))
        var pieces = [piece(straightPoints, Array(repeating: TrackCurve.straight, count: straightPoints.count - 1), start: end.at)]
        var platforms = [RealLineAcquisition.PieceAt(piece: first, distance: Fan.ramp + platformStart)]
        var offsets = [0.0]
        func onStraight(_ along: Double) -> RealLineAcquisition.NodeAt {
            RealLineAcquisition.NodeAt(piece: first, node: 1 + turnouts.firstIndex(of: along)!)
        }
        // A siding from `points` (its last on its curve's end, `along`
        // the yard) on to the far end, its platform with the others.
        func siding(_ points: [WorldVector], _ curves: [TrackCurve], along: Double, across: Double, start: RealLineAcquisition.NodeAt) {
            let all = points + [at(far, across)]
            let laid = piece(all.map { coordinate($0, height) }, curves + [.straight], start: start)
            let before = laid.distances[points.count - 1]
            platforms.append(RealLineAcquisition.PieceAt(piece: first + pieces.count, distance: before + platformStart - along))
            offsets.append(across)
            pieces.append(laid)
        }
        for side in sides {
            let sign = side.sign, g = side.from
            if side.count >= 1 {
                let a = g + Fan.firstAfter, b = a + Fan.firstReach
                siding(
                    [at(a, 0), at(b, sign * spacing)], [cubic(at(a, 0), leaving: way, at(b, sign * spacing), arriving: way, handle: Fan.firstReach / 2)],
                    along: b, across: sign * spacing, start: onStraight(a)
                )
            }
            guard side.count >= 2 else { continue }
            // The ladder: out along `angle`, past each siding's turnout,
            // and back into the yard's way as the outermost siding.
            let out = (way * cos(Fan.angle) + way.normal * (sign * sin(Fan.angle))).unit
            let corner = at(g + arcAlong, sign * arcAcross)
            let ladderPiece = first + pieces.count
            var ladder = [at(g, 0), corner]
            var curves = [cubic(at(g, 0), leaving: way, corner, arriving: out, handle: handle)]
            for k in 2...side.count {
                ladder.append(at(Fan.ladderTurnout(k, from: g), sign * (spacing * Double(k) - arcAcross)))
                curves.append(.straight)
            }
            let outer = Fan.ladderTurnout(side.count, from: g) + arcAlong, outerAcross = sign * spacing * Double(side.count)
            curves.append(cubic(ladder[ladder.count - 1], leaving: out, at(outer, outerAcross), arriving: way, handle: handle))
            ladder.append(at(outer, outerAcross))
            siding(ladder, curves, along: outer, across: outerAcross, start: onStraight(g))
            // The sidings between, each off its turnout on the ladder.
            for k in (2..<side.count).reversed() {
                let turnout = ladder[k], along = Fan.ladderTurnout(k, from: g) + arcAlong, across = sign * spacing * Double(k)
                siding(
                    [turnout, at(along, across)], [cubic(turnout, leaving: out, at(along, across), arriving: way, handle: handle)],
                    along: along, across: across, start: RealLineAcquisition.NodeAt(piece: ladderPiece, node: k)
                )
            }
        }
        let station = at((platformStart + far) / 2, (offsets.max()! + offsets.min()!) / 2)
        return (pieces, RealLineAcquisition.Depot(name: site.name(in: language), at: station.plan, platforms: platforms, length: length))
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
