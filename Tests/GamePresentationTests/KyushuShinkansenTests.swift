import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// SHINKANSEN-SALE (decision 975): probe.
@MainActor
final class KyushuShinkansenProbeTests: XCTestCase {
    static let id = "kyushushinkansen:KS"
    static let metre = Double(WorldCoordinate.unitsPerMetre)

    func out(_ items: Any...) {
        FileHandle.standardError.write(Data((items.map { "\($0)" }.joined(separator: " ") + "\n").utf8))
    }

    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["KS_PROBE"] != nil else { throw XCTSkip("KS_PROBE=1") }
        let orders = ProcessInfo.processInfo.environment["KS_ORDERS"] == "1" ? [[Self.id]] : [[Self.id], ["fksubway:K", "fksubway:H", "fksubway:N", Self.id], [Self.id, "fksubway:N", "fksubway:H", "fksubway:K"]]
        for order in orders {
            let session = try FukuokaRailwaysTests.fukuoka()
            out("KS order", order)
            out("KS buyable", session.buyableRealLines.map(\.id))
            out("KS bundles", session.realLineBundles.map { $0.lines.map(\.id) })
            for listing in session.realLineListings {
                out("KS listing", listing.bundle.lines.map(\.id), listing.metres, listing.note as Any)
            }
            let ownedBefore = session.world.mapExpansion?.owned.count ?? -1
            var laidBy: [TrackPlatform: String] = [:]
            for id in order {
                let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
                let start = Date()
                let offer = session.realLineOffer(for: real)
                out("KS offer", id, "problem", offer.problem as Any, "price", offer.price as Any, "seconds", Date().timeIntervalSince(start))
                guard let acquisition = offer.acquisition else { continue }
                out("KS   trains", acquisition.trains.count, "cars", acquisition.cars, "type", acquisition.trainType as Any,
                      "tiles", acquisition.tiles?.count as Any, "depot", acquisition.depot?.name as Any, acquisition.depot?.platforms.count as Any)
                let ok = session.acquireRealLine(offer)
                out("KS   acquired", ok, session.message?.text ?? "")
                for platform in session.world.network.platforms where laidBy[platform] == nil { laidBy[platform] = id }
            }
            let world = session.world
            out("KS owned tiles", ownedBefore, "->", world.mapExpansion?.owned.count ?? -1)
            guard let bought = world.acquisition(of: Self.id), let lineID = bought.line, let line = world.line(id: lineID) else { continue }
            out("KS line trains", line.trains.count, "runs", line.runs.count, "depots", line.depots.compactMap { world.station(id: $0)?.name }, "highSpeed", line.isHighSpeed)
            for stop in line.stops {
                guard let station = world.station(id: stop) else { continue }
                var row = "KS   \(station.name):"
                for p in world.network.platforms(of: stop) {
                    guard let g = world.trackGeometry(of: p.edge) else { continue }
                    let mid = g.location(at: (p.start + p.end) / 2).position
                    let ground = Double(world.groundHeight(at: mid.plan) ?? 0)
                    row += String(format: " [%@ z %.1f over %.1f len %.0f]", laidBy[p] ?? "?", Double(mid.z) / Self.metre, (Double(mid.z) - ground) / Self.metre, Double(p.end - p.start) / Self.metre)
                }
                out(row)
            }
            let laid = SharedStationLayoutTests.platforms(of: world, laidBy: laidBy)
            out("KS stacked", SharedStationLayoutTests.stacked(laid, in: world))
            out("KS uneven", SharedStationLayoutTests.uneven(laid, in: world))
            for row in SharedStationLayoutTests.report("fukuoka \(order)", of: world, laidBy: laidBy) { out("KS", row) }
            let gauges = Set(world.network.edges.filter { edge in bought.track?.contains(edge.id) ?? false }.map(\.gauge))
            out("KS gauges", gauges)
            if order.count == 1 {
                var played = world
                var stuck = 0
                var shown = 0
                for _ in 0..<(24 * 60) {
                    try played.advance(ticks: 1)
                    if !played.deadlockedTrains().isEmpty { stuck += 1 }
                    if shown < 2, let now = played.line(id: lineID) {
                        for (run, day) in now.dueRuns(at: played.clock.now).prefix(1) {
                            shown += 1
                            let r = now.runs[run]
                            out("KS due run", run, "day", day, "at", played.clock.now.seconds, "from stop", r.from, played.station(id: now.stops[r.from])?.name ?? "?", "perf", now.performance)
                            for id in now.trains {
                                guard let train = played.train(id: id) else { continue }
                                out("KS   train", train.name, "exec", train.execution as Any, "placed", train.placement != nil, "rate", train.movement.rate,
                                      "stoppedAtFirst", played.isStopped(train, at: now.stops[r.from]), "trip", played.runTrip(of: now, r, for: train) != nil,
                                      "at", played.stationsStoppedAt(by: id).compactMap { played.station(id: $0)?.name })
                            }
                        }
                    }
                }
                let after = try XCTUnwrap(played.line(id: lineID))
                out("KS day: stuck minutes", stuck, "runs run", zip(after.runs, after.runDays).filter { $0.1 != nil }.count, "of", after.runs.count)
            }
        }
    }

    /// Temporary: the morning's runs as they are sent.
    func testDay() throws {
        guard ProcessInfo.processInfo.environment["KS_DAY"] != nil else { throw XCTSkip("KS_DAY=1") }
        let realistic = ProcessInfo.processInfo.environment["KS_DAY"] == "realistic"
        let session = try TimetableCheckupAllBoughtTests.fukuoka(rules: realistic ? .realistic : .simple)
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        let offer = session.realLineOffer(for: real)
        XCTAssertTrue(session.acquireRealLine(offer))
        var world = session.world
        let lineID = try XCTUnwrap(world.acquisition(of: Self.id)?.line)
        func name(_ s: StationID) -> String { world.station(id: s)?.name ?? "?" }
        func hm(_ t: Int64) -> String { String(format: "%02d:%02d:%02d", t / 3600 % 24, t / 60 % 60, t % 60) }
        let until = Int64(ProcessInfo.processInfo.environment["KS_UNTIL"].flatMap(Int64.init) ?? 39600)
        var lastAt: [TrainID: [String]] = [:]
        let watchFrom = Int64(ProcessInfo.processInfo.environment["KS_WATCH"].flatMap(Int64.init) ?? 0)
        while world.clock.now.seconds < until {
            let before = world.clock.now.seconds
            if watchFrom > 0, before >= watchFrom, before < watchFrom + 15 * 60 {
                var m = world.questionMemo()
                var row = "KS watch \(hm(before)):"
                for train in world.trains where train.execution != nil {
                    if let wait = world.awaitedRoute(of: train.id, memo: &m) {
                        row += " [\(train.name) waits for \(world.train(id: wait.holder)?.name ?? "?") needs \(wait.needs?.count ?? -1)]"
                    }
                }
                row += " inTheWay \(world.trainsInTheWay(memo: &m).compactMap { world.train(id: $0)?.name })"
                row += " held \(world.heldRunDepartures(memo: &m).compactMap { world.train(id: $0.train)?.name })"
                var dm = GameWorld.DispatchMemo()
                if let line = world.line(id: lineID) {
                    row += " candidates \(world.runDepotEntryCandidates(of: line, memo: &dm).map { world.trains[$0].name })"
                    if let leaving = world.runTrainLeavingDepot(of: line, memo: &dm) { row += " leaving \(world.trains[leaving.index].name) to \(leaving.trip.deadhead.map { name($0.to) } ?? "?")" }
                }
                out(row)
            }
            let old = try XCTUnwrap(world.line(id: lineID)).runDays
            try world.advance(ticks: 1)
            let line = try XCTUnwrap(world.line(id: lineID))
            for index in line.runs.indices where line.runDays[index] != old[index] {
                let run = line.runs[index]
                let first = line.stops[run.calls(stopCount: line.stops.count)[0]]
                var row = "KS sent run \(index) due \(hm(run.start(onDay: 0))) from \(name(first)) at \(hm(world.clock.now.seconds))"
                for candidate in line.assignedTrains {
                    guard let found = world.train(id: candidate), let stop = found.timetable.first, stop.station == first, stop.arrival.seconds >= before else { continue }
                    row += " train \(found.name):"
                    for stop in found.timetable { row += " \(name(stop.station)) \(hm(stop.arrival.seconds))/\(hm(stop.departure.seconds))" }
                    break
                }
                out(row)
            }
            for id in line.trains {
                guard let train = world.train(id: id) else { continue }
                let at = world.stationsStoppedAt(by: id).map(name)
                if at != lastAt[id] ?? [] {
                    out("KS \(hm(world.clock.now.seconds)) \(train.name) at \(at) exec \(String(describing: train.execution))")
                    lastAt[id] = at
                }
            }
        }
    }

    /// Where GameCore refuses the line bought after the subway's three.
    func testWhere() throws {
        guard ProcessInfo.processInfo.environment["KS_WHERE"] != nil else { throw XCTSkip("KS_WHERE=1") }
        let session = try FukuokaRailwaysTests.fukuoka()
        let before = (ProcessInfo.processInfo.environment["KS_BEFORE"] ?? "fksubway:K,fksubway:H,fksubway:N").split(separator: ",").map(String.init)
        for id in before {
            let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == id }, id)
            let offer = session.realLineOffer(for: real)
            out("KS bought", id, session.acquireRealLine(offer), offer.problem as Any)
        }
        let real = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id })
        let laying = session.realLineLaying
        let m = Self.metre
        func show(_ c: WorldCoordinate, in world: GameWorld) -> String {
            let ground = Double(world.groundHeight(at: c.plan) ?? 0)
            return String(format: "(%.0f, %.0f, z %.1f, over %.1f)", Double(c.x) / m, Double(c.y) / m, Double(c.z) / m, (Double(c.z) - ground) / m)
        }
        for station in session.world.stations where station.name.contains("博多") {
            out("KS station", station.name, station.id, String(format: "(%.0f, %.0f)", Double(station.location.x) / m, Double(station.location.y) / m))
            for p in session.world.network.platforms(of: station.id) {
                guard let g = session.world.trackGeometry(of: p.edge) else { continue }
                out("KS   platform", show(g.location(at: (p.start + p.end) / 2).position, in: session.world), session.world.network.edge(p.edge)?.structure as Any)
            }
        }
        let tries: [(String, RealLineLaying.StationRaising, Bool, Bool)] = [
            ("viaducts", .viaducts, false, false), ("through", .viaducts, false, true), ("shared", .viaductsAndShared, false, false),
            ("clear", .viaducts, true, false), ("clear+shared", .viaductsAndShared, true, false),
        ]
        for (name, raising, clear, through) in tries {
            let start = Date()
            let tried = laying.offer(for: real, raising: raising, depot: true, clearingTrack: clear, besideThrough: through)
            out("KS try", name, "problem", tried.offer.problem as Any, "crosses", tried.crossesTrack, "seconds", Date().timeIntervalSince(start))
            guard let acquisition = tried.laid else { continue }
            var world = session.world.pricingCopy()
            for tile in acquisition.tiles ?? [] { try world.buyMapTile(tile, passingMilestone: true) }
            GameSession.readLand(roundStationsOf: &world, population: session.population, places: session.places, water: session.water, coverage: session.coverage)
            var nodes: [[TrackNodeID]] = []
            laying: for (number, piece) in acquisition.pieces.enumerated() {
                try world.readGround(under: piece.ground, from: session.heights)
                var ids: [TrackNodeID] = []
                for (index, position) in piece.nodes.enumerated() {
                    if index == 0, let start = piece.start {
                        ids.append(nodes[start.piece][start.node])
                    } else if index == piece.nodes.count - 1, let end = piece.end {
                        ids.append(nodes[end.piece][end.node])
                    } else {
                        do {
                            ids.append(try world.buildTrackNode(at: position))
                        } catch {
                            out("KS   piece", number, "node", index, show(position, in: world), "error", error)
                            break laying
                        }
                    }
                }
                for (index, curve) in piece.curves.enumerated() {
                    do {
                        _ = try world.buildTrackEdge(from: ids[index], to: ids[index + 1], curve: curve, structure: piece.structure(ofEdge: index),
                                                     gauge: TrackGauge.ofRealLine(acquisition.realLine))
                    } catch {
                        out("KS   piece", number, "of", acquisition.pieces.count, "edge", index, "of", piece.curves.count, "together", piece.together,
                            "structure", piece.structure(ofEdge: index), "distance", piece.distances[index] / m, piece.distances[index + 1] / m, "error", error)
                        out("KS     from", show(piece.nodes[index], in: world), "to", show(piece.nodes[index + 1], in: world))
                        let other: TrackEdgeID? = switch error {
                        case .trackConflict(let edge), .trackTooClose(let edge): edge
                        default: nil
                        }
                        if let other, let edge = world.network.edge(other), let a = world.network.node(edge.from), let b = world.network.node(edge.to) {
                            out("KS     other edge", other, "structure", edge.structure, "from", show(a.position, in: world), "to", show(b.position, in: world),
                                "gauge", edge.gauge, "new", !session.world.network.edges.contains { $0.id == other })
                        }
                        break laying
                    }
                }
                nodes.append(ids)
            }
        }
    }
}
