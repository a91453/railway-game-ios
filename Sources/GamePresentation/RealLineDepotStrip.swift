import Foundation
import GameCore

// Decision 621: a depot laid as a strip along the line, as the Kaohsiung
// Light Rail's real one lies. The wye's yard (decision 479) fanned its
// sidings either side of a lead some 75 m off the line, some 100 m wide;
// the real yard is a strip some 60 m wide along the line's west track.
//
// So: the wye stays (its arms where decision 479 lays them, so a train
// leaves the yard either way round the ring short of a station beside
// it; trains turn round only at a berth or a stop), its foot nearer the
// line (``RealLineDepotLayout/Strip/foot``), and from it a running track
// turns along the line ``RealLineDepotLayout/Strip/running`` off the
// second track, its sidings in banks one after the other along it,
// between it and the line. Each siding is open at both ends: a ladder
// off the running track at each end of a bank, the first siding by an
// S-curve of its own, as decision 602's fanned yards lay theirs
// (``RealLineDepotLayout/Fan``). The real yard's leads leave the west
// track straight off the line at its two ends instead; a train turning
// round at the station there (輕軌機廠站, between them) is a rule
// GameCore does not have (decision 621's next step).

extension RealLineDepotSite {
    /// Decision 621: a strip yard's shape: how many banks its sidings
    /// stand in, one after the other along the line.
    struct Strip: Sendable {
        let banks: Int
    }
}

extension RealLineDepotLayout {
    /// Decision 621: a strip yard's measures.
    enum Strip {
        /// How far the wye's foot stands off the line's second track, and
        /// how far along the line past the first arm's turnout: the first
        /// arm a quarter circle 40 m round, the second (from 140 m on,
        /// ``RealLineDepotLayout/armReach`` twice) some 25 m round at the
        /// foot at its tightest.
        static let foot = 40 * metre
        static let footAlong = 40 * metre
        /// The second arm's cubic handles, along the line and across it.
        static let secondArmHandles = (along: 55 * metre, across: 32 * metre)
        /// The north lead: an S-curve from the last bank's innermost
        /// siding onto the second track, its bends some 25 m round.
        static let leadReach = 42 * metre
        /// The running track's turn from the foot along the line, a light
        /// rail's 25 m round.
        static let turn = 25 * metre
        /// How far the running track lies off the line's second track at
        /// least: past the foot by its turn.
        static var running: Double { foot + turn }
        /// The ladders' curves: a light rail's 25 m, turning out 35°.
        static let radius = 25 * metre
        static let angle = 35 * Double.pi / 180
        static let firstAfter = Fan.firstAfter
        static let firstReach = Fan.firstReach
        /// The running track between two banks, where it bends from one's
        /// way to the next's.
        static let bankGap = 30 * metre
        static let spacing = Double(DepotYard.spacing)

        static var arcAlong: Double { radius * sin(angle) }
        static var arcAcross: Double { radius * (1 - cos(angle)) }
        /// A circular arc's cubic handle.
        static var handle: Double { 4.0 / 3 * tan(angle / 4) * radius }

        /// How many sidings each bank holds, the first bank the most.
        static func counts(of site: RealLineDepotSite) -> [Int] {
            let banks = max(site.strip?.banks ?? 1, 1)
            return (0..<banks).map { site.sidings / banks + ($0 < site.sidings % banks ? 1 : 0) }
        }

        /// Where along a bank, from its end on the running track, siding
        /// `k` (from 2) leaves the ladder.
        static func ladderTurnout(_ k: Int) -> Double {
            arcAlong + (spacing * Double(k) - 2 * arcAcross) / tan(angle)
        }

        /// How far along a bank of `count` sidings, from either end, its
        /// curves end.
        static func throat(_ count: Int) -> Double {
            switch count {
            case 0: 0
            case 1: firstAfter + firstReach
            default: max(ladderTurnout(count) + arcAlong, firstAfter + firstReach)
            }
        }

        /// Where the platforms of a bank start along it.
        static func platformStart(_ count: Int) -> Double { throat(count) + RealWorldDemo.platformMargin }

        /// How long a bank of `count` sidings for platforms `length` long is.
        static func bankLength(_ count: Int, length: Int64) -> Double {
            2 * platformStart(count) + Double(length)
        }

        /// How far along the line, past the wye's first arm, the north
        /// lead joins the second track.
        static func span(of site: RealLineDepotSite, length: Int64) -> Double {
            let banks = counts(of: site)
            return footAlong + turn + banks.map { bankLength($0, length: length) }.reduce(0, +) + Double(banks.count - 1) * bankGap + leadReach
        }

        /// The ground a strip yard stands on, every `step` along `path`
        /// from `back` short of `j` to as far past the north lead, and
        /// across it to the yard's side, `side` (+1 or -1) of its normal.
        static func groundSamples(along path: WorldPath, at j: Double, side: Double, site: RealLineDepotSite, length: Int64, back: Double, step: Double) -> [PlanPoint] {
            let along = span(of: site, length: length) + 2 * back
            let across = HighSpeedDemo.trackOffset + running + 2 * TrackRise.spacing + back
            return (0...Int(along / step)).flatMap { a in
                let at = j - back + Double(a) * step
                let point = path.point(at: at), normal = path.tangent(at: at).normal * side
                return (0...Int(across / step) + 1).map { c in (point + normal * (Double(c) * step)).plan }
            }
        }
    }

    /// Decision 621: the depot's pieces, from piece `first` on, and the
    /// depot, laid as a strip (``Strip``) beside the second track (piece
    /// 1) of `path`: the wye off it at `marks[2]` and `marks[3]`, the
    /// north lead at `marks[6]` (see
    /// ``RealLineLaying/ringStripMarks(at:site:length:)``), `j` along the
    /// path at the first, and the yard along the line from the wye's foot;
    /// each siding with a platform `length` long. `nil` where the yard
    /// cannot stand level within the arms' and the lead's grade.
    static func strip(
        _ site: RealLineDepotSite, along path: WorldPath, at j: Double, second: RealWorldDemo.TrackPlan,
        marks: [(main: Int, second: Int)], first: Int, length: Int64, ground: (WorldVector) -> Double, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        guard marks.count == 9, site.sidings > 0, Strip.counts(of: site).last! >= 3 else { return nil }
        func node(_ mark: (main: Int, second: Int)) -> (point: WorldVector, direction: WorldVector, height: Int64) {
            (WorldVector(second.nodes[mark.second].point), second.nodes[mark.second].direction.unit, second.heights[mark.second])
        }
        let up = node(marks[2]), down = node(marks[3]), north = node(marks[6])
        // The yard's side of the line: the second track's.
        let side: Double = (up.point - path.point(at: j)).dot(path.tangent(at: j).normal) >= 0 ? 1 : -1
        let counts = Strip.counts(of: site)
        let spacing = Strip.spacing
        let trackOffset = HighSpeedDemo.trackOffset

        // The wye's foot, `foot` off the second track and `footAlong`
        // past the first arm's turnout, its lead straight off the line.
        let middle = j + Strip.footAlong
        let away = path.tangent(at: middle).normal * side
        let foot = path.point(at: middle) + away * (trackOffset + Strip.foot)

        // Each bank straight along the line's chord over it, its running
        // track as near the line as keeps it `running` off the second
        // track all along (``Strip/running``), its sidings between.
        struct Bank {
            let count: Int
            let length: Double
            let origin: WorldVector
            let way: WorldVector
            let across: WorldVector
            func at(_ along: Double, _ off: Double) -> WorldVector { origin + way * along + across * off }
        }
        var banks: [Bank] = []
        var from = Strip.footAlong + Strip.turn
        for count in counts {
            let length = Strip.bankLength(count, length: length)
            let a = path.point(at: j + from), b = path.point(at: j + from + length)
            let way = (b - a).unit, outward = way.normal * (way.normal.dot(path.tangent(at: j + from).normal * side) >= 0 ? 1 : -1)
            let nearest = stride(from: 0, through: length, by: TrackRise.spacing).map { (path.point(at: j + from + $0) - a).dot(outward) }.max() ?? 0
            banks.append(Bank(count: count, length: length, origin: a + outward * (nearest + trackOffset + Strip.running), way: way, across: outward.reversed))
            from += length + Strip.bankGap
        }

        // The yard level, the foot's: within the arms' and the north lead's
        // grade of the second track at their turnouts, as near the ground
        // as that lets it.
        let rises = [(up.height, (foot - up.point).length), (down.height, (foot - down.point).length), (north.height, Strip.leadReach)]
        let low = rises.map { Double($0.0) - grade * $0.1 }.max()!, high = rises.map { Double($0.0) + grade * $0.1 }.min()!
        guard low <= high else { return nil }
        let centre = banks[banks.count / 2].at(banks[banks.count / 2].length / 2, spacing * Double(counts.max()! + 1) / 2)
        let height = Int64(max(low, min(high, ground(centre))).rounded())
        func coordinate(_ point: WorldVector, _ z: Int64 = height) -> WorldCoordinate { Self.coordinate(point, z) }

        // The running track: from the foot, turning along the line, along
        // each bank (a node where each of its sidings leaves and joins
        // it), bending from one bank's way to the next's, ending where the
        // last bank's north ladder reaches it (``Strip/throat(_:)`` short
        // of its end).
        var runningPoints = [coordinate(foot)]
        var runningCurves: [TrackCurve] = []
        var runningNodes: [[Double: Int]] = []
        for (index, bank) in banks.enumerated() {
            let start = bank.at(0, 0)
            if index == 0 {
                runningCurves.append(cubic(foot, leaving: away, start, arriving: bank.way, handle: 0.55 * Strip.turn))
            } else {
                let before = banks[index - 1]
                runningCurves.append(cubic(before.at(before.length, 0), leaving: before.way, start, arriving: bank.way, handle: Strip.bankGap / 3))
            }
            let last = index == banks.count - 1
            var alongs: [Double] = [0, last ? bank.length - Strip.throat(bank.count) : bank.length]
            if bank.count >= 1 { alongs += last ? [Strip.firstAfter] : [Strip.firstAfter, bank.length - Strip.firstAfter] }
            alongs = Array(Set(alongs)).sorted()
            var nodes: [Double: Int] = [:]
            for (number, along) in alongs.enumerated() {
                if number > 0 { runningCurves.append(.straight) }
                nodes[along] = runningPoints.count
                runningPoints.append(coordinate(bank.at(along, 0)))
            }
            runningNodes.append(nodes)
        }
        let footNode = RealLineAcquisition.NodeAt(piece: first, node: 0)
        // Each arm's handles, along the line and across it.
        func arm(_ turnout: WorldVector, leaving way: WorldVector, handles: (along: Double, across: Double)) -> TrackCurve {
            .cubic((turnout + way * handles.along).plan, (foot - away * handles.across).plan)
        }
        var pieces = [
            piece(runningPoints, runningCurves, start: nil),
            // The wye: an arm leaving the second track along the line
            // from each turnout, both reaching the foot off the line.
            piece(
                [coordinate(up.point, up.height), coordinate(foot)],
                [arm(up.point, leaving: up.direction, handles: (0.55 * Strip.footAlong, 0.55 * Strip.foot))],
                start: RealLineAcquisition.NodeAt(piece: 1, node: marks[2].second), end: footNode
            ),
            piece(
                [coordinate(down.point, down.height), coordinate(foot)],
                [arm(down.point, leaving: down.direction.reversed, handles: Strip.secondArmHandles)],
                start: RealLineAcquisition.NodeAt(piece: 1, node: marks[3].second), end: footNode
            ),
        ]

        // Each bank's sidings, open at both ends, their platforms side by
        // side along the bank.
        var platforms: [RealLineAcquisition.PieceAt] = []
        var middles: [WorldVector] = []
        for (index, bank) in banks.enumerated() where bank.count > 0 {
            let handle = Strip.handle
            let platformStart = Strip.platformStart(bank.count)
            func onRunning(_ along: Double) -> RealLineAcquisition.NodeAt {
                RealLineAcquisition.NodeAt(piece: first, node: runningNodes[index][along]!)
            }
            // A siding's piece, its platform on its straight from node
            // `straight` on.
            // (`straight` nil: no siding, no platform.)
            var laid: [(piece: RealLineAcquisition.Piece, straight: Int?, off: Double)] = []
            func add(_ points: [WorldVector], _ curves: [TrackCurve], straight: Int?, off: Double, start: RealLineAcquisition.NodeAt, end: RealLineAcquisition.NodeAt) {
                laid.append((piece(points.map { coordinate($0) }, curves, start: start, end: end), straight, off))
            }
            let w = bank.way
            let out = (w * cos(Strip.angle) + bank.across * sin(Strip.angle)).unit
            let back = (w * cos(Strip.angle) - bank.across * sin(Strip.angle)).unit
            if index == banks.count - 1 {
                // The last bank's north end mirrored: its ladder in from the
                // running track to the innermost siding, which goes on as
                // the north lead onto the second track.
                let n = bank.count, l = bank.length, inner = spacing * Double(n)
                let bend = Strip.ladderTurnout(n) + Strip.arcAlong
                let lead = first + pieces.count + laid.count, mirror = lead + 1
                // The south ladder into the innermost siding, its base past
                // the platform, and the lead.
                var points = [bank.at(0, 0), bank.at(Strip.arcAlong, Strip.arcAcross)]
                var curves = [cubic(points[0], leaving: w, points[1], arriving: out, handle: handle)]
                for k in 2...n {
                    points.append(bank.at(Strip.ladderTurnout(k), spacing * Double(k) - Strip.arcAcross))
                    curves.append(.straight)
                }
                points.append(bank.at(bend, inner))
                curves.append(cubic(points[points.count - 2], leaving: out, points[points.count - 1], arriving: w, handle: handle))
                let straight = points.count - 1
                points += [bank.at(l - Strip.firstAfter, inner), bank.at(l, inner)]
                curves += [.straight, .straight]
                let base = points.count - 1
                curves.append(cubic(points[base], leaving: w, north.point, arriving: north.direction, handle: Strip.leadReach / 2))
                laid.append((
                    piece(points.map { coordinate($0) } + [coordinate(north.point, north.height)], curves, start: onRunning(0),
                          end: RealLineAcquisition.NodeAt(piece: 1, node: marks[6].second)),
                    straight, inner
                ))
                // The north ladder: from the base out across the sidings,
                // past each one's turnout, back onto the running track.
                let reversed = w.reversed, outward = out.reversed
                var ladder = [bank.at(l, inner), bank.at(l - Strip.arcAlong, inner - Strip.arcAcross)]
                var ladderCurves = [cubic(ladder[0], leaving: reversed, ladder[1], arriving: outward, handle: handle)]
                for k in 2...n {
                    ladder.append(bank.at(l - Strip.ladderTurnout(k), inner - spacing * Double(k) + Strip.arcAcross))
                    ladderCurves.append(.straight)
                }
                ladder.append(bank.at(l - bend, 0))
                ladderCurves.append(cubic(ladder[ladder.count - 2], leaving: outward, ladder[ladder.count - 1], arriving: reversed, handle: handle))
                add(ladder, ladderCurves, straight: nil, off: 0,
                    start: RealLineAcquisition.NodeAt(piece: lead, node: base), end: onRunning(l - bend))
                // Siding k's north end: onto the north ladder's turnout
                // n - k (from 2), or the next-to-innermost by an S-curve
                // onto the base.
                func northEnd(_ k: Int) -> (points: [WorldVector], curves: [TrackCurve], end: RealLineAcquisition.NodeAt) {
                    let off = spacing * Double(k)
                    if k == n - 1 {
                        let a = l - Strip.firstAfter - Strip.firstReach, b = bank.at(l - Strip.firstAfter, inner)
                        return ([bank.at(a, off), b], [cubic(bank.at(a, off), leaving: w, b, arriving: w, handle: Strip.firstReach / 2)],
                                RealLineAcquisition.NodeAt(piece: lead, node: straight + 1))
                    }
                    let turnout = n - k, end = ladder[turnout], along = Strip.ladderTurnout(turnout) + Strip.arcAlong
                    return ([bank.at(l - along, off), end], [cubic(bank.at(l - along, off), leaving: w, end, arriving: out, handle: handle)],
                            RealLineAcquisition.NodeAt(piece: mirror, node: turnout))
                }
                // The first siding, by an S-curve off the running track.
                do {
                    let a = Strip.firstAfter, b = a + Strip.firstReach
                    let north = northEnd(1)
                    add(
                        [bank.at(a, 0), bank.at(b, spacing)] + north.points,
                        [cubic(bank.at(a, 0), leaving: w, bank.at(b, spacing), arriving: w, handle: Strip.firstReach / 2), .straight] + north.curves,
                        straight: 1, off: spacing, start: onRunning(a), end: north.end
                    )
                }
                // The sidings between, each off the south ladder's turnout k.
                for k in (2..<n).reversed() {
                    let north = northEnd(k), off = spacing * Double(k)
                    let along = Strip.ladderTurnout(k) + Strip.arcAlong
                    add(
                        [points[k], bank.at(along, off)] + north.points,
                        [cubic(points[k], leaving: out, bank.at(along, off), arriving: w, handle: handle), .straight] + north.curves,
                        straight: 1, off: off, start: RealLineAcquisition.NodeAt(piece: lead, node: k), end: north.end
                    )
                }
            } else {
            // The first siding, by an S-curve off the running track at
            // each end.
            do {
                let a = Strip.firstAfter, b = a + Strip.firstReach, l = bank.length
                let points = [bank.at(a, 0), bank.at(b, spacing), bank.at(l - b, spacing), bank.at(l - a, 0)]
                add(
                    points,
                    [cubic(points[0], leaving: w, points[1], arriving: w, handle: Strip.firstReach / 2), .straight,
                     cubic(points[2], leaving: w, points[3], arriving: w, handle: Strip.firstReach / 2)],
                    straight: 1, off: spacing, start: onRunning(a), end: onRunning(l - a)
                )
            }
            if bank.count >= 2 {
                // The ladders: out from the running track at each end,
                // past each siding's turnout, into the outermost siding.
                let n = bank.count, l = bank.length
                let ladderPiece = first + pieces.count + laid.count
                var points = [bank.at(0, 0), bank.at(Strip.arcAlong, Strip.arcAcross)]
                var curves = [cubic(points[0], leaving: w, points[1], arriving: out, handle: handle)]
                for k in 2...n {
                    points.append(bank.at(Strip.ladderTurnout(k), spacing * Double(k) - Strip.arcAcross))
                    curves.append(.straight)
                }
                let bend = Strip.ladderTurnout(n) + Strip.arcAlong, outer = spacing * Double(n)
                points.append(bank.at(bend, outer))
                curves.append(cubic(points[points.count - 2], leaving: out, points[points.count - 1], arriving: w, handle: handle))
                let straight = points.count - 1
                points.append(bank.at(l - bend, outer))
                curves.append(.straight)
                points.append(bank.at(l - Strip.ladderTurnout(n), outer - Strip.arcAcross))
                curves.append(cubic(points[points.count - 2], leaving: w, points[points.count - 1], arriving: back, handle: handle))
                for k in (2..<n).reversed() {
                    points.append(bank.at(l - Strip.ladderTurnout(k), spacing * Double(k) - Strip.arcAcross))
                    curves.append(.straight)
                }
                points.append(bank.at(l - Strip.arcAlong, Strip.arcAcross))
                curves.append(.straight)
                points.append(bank.at(l, 0))
                curves.append(cubic(points[points.count - 2], leaving: back, points[points.count - 1], arriving: w, handle: handle))
                add(points, curves, straight: straight, off: outer, start: onRunning(0), end: onRunning(l))
                // The sidings between, each off its turnouts on the two
                // ladders: node k at the south end, 2n + 3 - k at the north.
                for k in (2..<n).reversed() {
                    let near = points[k], far = points[2 * n + 3 - k], off = spacing * Double(k)
                    let along = Strip.ladderTurnout(k) + Strip.arcAlong
                    let siding = [near, bank.at(along, off), bank.at(l - along, off), far]
                    add(
                        siding,
                        [cubic(near, leaving: out, siding[1], arriving: w, handle: handle), .straight,
                         cubic(siding[2], leaving: w, far, arriving: back, handle: handle)],
                        straight: 1, off: off,
                        start: RealLineAcquisition.NodeAt(piece: ladderPiece, node: k),
                        end: RealLineAcquisition.NodeAt(piece: ladderPiece, node: 2 * n + 3 - k)
                    )
                }
            }
            }
            // The platforms, inner siding first.
            var bankPlatforms: [(off: Double, at: RealLineAcquisition.PieceAt)] = []
            for entry in laid {
                guard let straight = entry.straight else {
                    pieces.append(entry.piece)
                    continue
                }
                let a = WorldVector(entry.piece.nodes[straight].plan), b = WorldVector(entry.piece.nodes[straight + 1].plan)
                let at = bank.at(platformStart, entry.off)
                let distance = entry.piece.distances[straight] + (at - a).dot((b - a).unit)
                bankPlatforms.append((entry.off, RealLineAcquisition.PieceAt(piece: first + pieces.count, distance: distance)))
                middles.append(bank.at(platformStart + Double(length) / 2, entry.off))
                pieces.append(entry.piece)
            }
            platforms += bankPlatforms.sorted { $0.off < $1.off }.map(\.at)
        }
        let station = middles.reduce(WorldVector(x: 0, y: 0), +) * (1 / Double(max(middles.count, 1)))
        return (pieces, RealLineAcquisition.Depot(name: site.name(in: language), at: station.plan, platforms: platforms, length: length))
    }
}
