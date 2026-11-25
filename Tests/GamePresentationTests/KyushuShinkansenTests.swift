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
}
