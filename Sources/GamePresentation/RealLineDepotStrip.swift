import Foundation
import GameCore

// Decision 621: a depot laid as a strip beside the line, as the
// Kaohsiung Light Rail's real one lies. The wye (decision 479) stood its
// foot some 75 m off the line and the yard round it, some 100 m wide; the
// real yard is a strip some 60 m wide along the line's west track, its
// leads leaving that track straight off the line at both ends.
//
// So: a running track some 9 m beside the line's second track, leaving
// it at the south end and joining it again at the north (each by an
// S-curve, ``RealLineDepotLayout/Strip/leadReach`` long), and its
// sidings in banks one after the other along it, each siding open at both
// ends: a ladder off the running track at each end of a bank, the first
// siding by an S-curve of its own, as decision 602's fanned yards lay
// theirs (``RealLineDepotLayout/Fan``). A train goes into a siding from
// either end and leaves it either way, as from the wye's foot: round the
// ring the way it came, or on, onto the line's first track by the
// crossover past the north lead.

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
        /// How far the running track lies off the line's second track at
        /// least: the real south lead runs 6 to 12 m off the west track.
        static let running = 9 * metre
        /// How long each lead's S-curve from the second track runs along
        /// the line.
        static let leadReach = 45 * metre
        /// The ladders' curves: a light rail's 25 m, turning out 35°.
        static let radius = 25 * metre
        static let angle = 35 * Double.pi / 180
        static let firstAfter = Fan.firstAfter
        static let firstReach = Fan.firstReach
        /// The running track between two banks, where it bends from one's
        /// way to the next's.
        static let bankGap = 30 * metre
        /// Where along the first bank, from its start, the middle lead
        /// leaves the running track for the second track, going up the
        /// line.
        static let middleAlong = 40 * metre
        /// How far along the line the middle lead joins the second track
        /// past the south lead.
        static var middle: Double { 2 * leadReach + middleAlong }
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

        /// How far along the line the north lead leaves the second track
        /// past the south lead.
        static func span(of site: RealLineDepotSite, length: Int64) -> Double {
            let banks = counts(of: site)
            return 2 * leadReach + banks.map { bankLength($0, length: length) }.reduce(0, +) + Double(banks.count - 1) * bankGap
        }

        /// The ground a strip yard stands on, every `step` along `path`
        /// from `back` short of `j` to as far past the north lead, and
        /// across it to the yard's side, `side` (+1 or -1) of its normal.
        static func groundSamples(along path: WorldPath, at j: Double, side: Double, site: RealLineDepotSite, length: Int64, back: Double, step: Double) -> [PlanPoint] {
            let along = span(of: site, length: length) + 2 * back
            let across = HighSpeedDemo.trackOffset + running + 2 * TrackRise.spacing + spacing * Double(counts(of: site).max() ?? 0) + back
            return (0...Int(along / step)).flatMap { a in
                let at = j - back + Double(a) * step
                let point = path.point(at: at), normal = path.tangent(at: at).normal * side
                return (0...Int(across / step) + 1).map { c in (point + normal * (Double(c) * step)).plan }
            }
        }
    }

    /// Decision 621: the depot's pieces, from piece `first` on, and the
    /// depot, laid as a strip (``Strip``) beside the second track (piece
    /// 1) of `path`, its leads leaving it at `marks[2]`, `marks[3]` and
    /// `marks[6]` (``RealLineLaying/ringStripMarks(at:site:length:)``), `j` along the path
    /// at the first; each siding with a platform `length` long. `nil`
    /// where the yard cannot stand level within the leads' grade.
    static func strip(
        _ site: RealLineDepotSite, along path: WorldPath, at j: Double, second: RealWorldDemo.TrackPlan,
        marks: [(main: Int, second: Int)], first: Int, length: Int64, ground: (WorldVector) -> Double, in language: DisplayLanguage
    ) -> (pieces: [RealLineAcquisition.Piece], depot: RealLineAcquisition.Depot)? {
        guard marks.count == 9, site.sidings > 0 else { return nil }
        func node(_ mark: (main: Int, second: Int)) -> (point: WorldVector, direction: WorldVector, height: Int64) {
            (WorldVector(second.nodes[mark.second].point), second.nodes[mark.second].direction.unit, second.heights[mark.second])
        }
        let south = node(marks[2]), middle = node(marks[3]), north = node(marks[6])
        // The yard's side of the line: the second track's.
        let side: Double = (south.point - path.point(at: j)).dot(path.tangent(at: j).normal) >= 0 ? 1 : -1
        let counts = Strip.counts(of: site)
        let spacing = Strip.spacing

        // Each bank straight along the line's chord over it, its running
        // track as near the line as keeps it `running` off the second
        // track all along (``Strip/running``).
        struct Bank {
            let count: Int
            let length: Double
            let origin: WorldVector
            let way: WorldVector
            let across: WorldVector
            func at(_ along: Double, _ off: Double) -> WorldVector { origin + way * along + across * off }
        }
        let trackOffset = HighSpeedDemo.trackOffset
        var banks: [Bank] = []
        var from = Strip.leadReach
        for count in counts {
            let length = Strip.bankLength(count, length: length)
            let a = path.point(at: j + from), b = path.point(at: j + from + length)
            let way = (b - a).unit, across = way.normal * (way.normal.dot(path.tangent(at: j + from).normal * side) >= 0 ? 1 : -1)
            let nearest = stride(from: 0, through: length, by: TrackRise.spacing).map { (path.point(at: j + from + $0) - a).dot(across) }.max() ?? 0
            banks.append(Bank(count: count, length: length, origin: a + across * (nearest + trackOffset + Strip.running), way: way, across: across))
            from += length + Strip.bankGap
        }

        // The yard level, within the leads' grade of the second track at
        // both ends, as near the ground as that lets it.
        let climb = grade * Strip.leadReach
        let ends = [south.height, middle.height, north.height]
        let low = Double(ends.max()!) - climb, high = Double(ends.min()!) + climb
        guard low <= high else { return nil }
        let centre = banks[banks.count / 2].at(banks[banks.count / 2].length / 2, spacing * Double(counts.max()! + 1) / 2)
        let height = Int64(max(low, min(high, ground(centre))).rounded())
        func coordinate(_ point: WorldVector, _ z: Int64 = height) -> WorldCoordinate { Self.coordinate(point, z) }

        // The running track: off the second track, along each bank (a
        // node where each of its sidings leaves and joins it), bending
        // from one bank's way to the next's, and back onto the second
        // track.
        var runningPoints = [coordinate(south.point, south.height)]
        var runningCurves: [TrackCurve] = []
        var runningNodes: [[Double: Int]] = []
        for (index, bank) in banks.enumerated() {
            let start = bank.at(0, 0)
            if index == 0 {
                runningCurves.append(cubic(south.point, leaving: south.direction, start, arriving: bank.way, handle: Strip.leadReach / 2))
            } else {
                let before = banks[index - 1]
                runningCurves.append(cubic(before.at(before.length, 0), leaving: before.way, start, arriving: bank.way, handle: Strip.bankGap / 3))
            }
            var alongs: [Double] = [0, bank.length]
            if bank.count >= 1 { alongs += [Strip.firstAfter, bank.length - Strip.firstAfter] }
            if index == 0 { alongs.append(Strip.middleAlong) }
            alongs = Array(Set(alongs)).sorted()
            var nodes: [Double: Int] = [:]
            for (number, along) in alongs.enumerated() {
                if number > 0 { runningCurves.append(.straight) }
                nodes[along] = runningPoints.count
                runningPoints.append(coordinate(bank.at(along, 0)))
            }
            runningNodes.append(nodes)
        }
        let last = banks[banks.count - 1]
        runningCurves.append(cubic(last.at(last.length, 0), leaving: last.way, north.point, arriving: north.direction, handle: Strip.leadReach / 2))
        runningPoints.append(coordinate(north.point, north.height))
        var pieces = [piece(
            runningPoints, runningCurves, start: RealLineAcquisition.NodeAt(piece: 1, node: marks[2].second),
            end: RealLineAcquisition.NodeAt(piece: 1, node: marks[6].second)
        )]
        // The middle lead: off the running track along the first bank,
        // onto the second track going up the line, so a train leaves the
        // yard that way short of a station beside it.
        do {
            let bank = banks[0], start = bank.at(Strip.middleAlong, 0)
            pieces.append(piece(
                [coordinate(start), coordinate(middle.point, middle.height)],
                [cubic(start, leaving: bank.way, middle.point, arriving: middle.direction, handle: Strip.leadReach / 2)],
                start: RealLineAcquisition.NodeAt(piece: first, node: runningNodes[0][Strip.middleAlong]!),
                end: RealLineAcquisition.NodeAt(piece: 1, node: marks[3].second)
            ))
        }

        // Each bank's sidings, open at both ends, their platforms side by
        // side along the bank.
        var platforms: [RealLineAcquisition.PieceAt] = []
        var middles: [WorldVector] = []
        let handle = Strip.handle
        for (index, bank) in banks.enumerated() where bank.count > 0 {
            let platformStart = Strip.platformStart(bank.count)
            func onRunning(_ along: Double) -> RealLineAcquisition.NodeAt {
                RealLineAcquisition.NodeAt(piece: first, node: runningNodes[index][along]!)
            }
            // A siding's piece, its platform on its straight from node
            // `straight` on.
            var laid: [(piece: RealLineAcquisition.Piece, straight: Int, off: Double)] = []
            func add(_ points: [WorldVector], _ curves: [TrackCurve], straight: Int, off: Double, start: RealLineAcquisition.NodeAt, end: RealLineAcquisition.NodeAt) {
                laid.append((piece(points.map { coordinate($0) }, curves, start: start, end: end), straight, off))
            }
            let w = bank.way
            let out = (w * cos(Strip.angle) + bank.across * sin(Strip.angle)).unit
            let back = (w * cos(Strip.angle) - bank.across * sin(Strip.angle)).unit
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
            // The platforms, inner siding first.
            var bankPlatforms: [(off: Double, at: RealLineAcquisition.PieceAt)] = []
            for entry in laid {
                let a = WorldVector(entry.piece.nodes[entry.straight].plan), b = WorldVector(entry.piece.nodes[entry.straight + 1].plan)
                let at = bank.at(platformStart, entry.off)
                let distance = entry.piece.distances[entry.straight] + (at - a).dot((b - a).unit)
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
