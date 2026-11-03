import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 556: the Taoyuan Airport MRT on sale, bought with its two real
/// depots beside the line, Luzhu between Shanbi and Kengkou and Qingpu
/// between Hengshan and Linghang, the trains its timetable leaves overnight
/// at stations between its ends standing in them, and a crossover either
/// side of each station between its ends that a run starts or ends at
/// (its expresses turn at Airport Terminal 2, its shuttles at Terminal 1
/// and Huanbei).
@MainActor
final class TaoyuanAirportLineTests: XCTestCase {
    static let id = "tymc:A"

    func testTheLineIsBoughtWithItsTwoRealDepots() throws {
        let session = try RealLineAcquisitionTests.game(round: Self.id, side: 1 << 22, heights: true)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "on sale")
        XCTAssertEqual(line.cars, 4)
        let offer = session.realLineOffer(for: line)
        let acquisition = try XCTUnwrap(offer.acquisition, offer.problem ?? "")
        let depots = [acquisition.depot].compactMap(\.self) + (acquisition.moreDepots ?? [])
        XCTAssertEqual(depots.map(\.name), ["蘆竹機廠", "青埔機廠"])
        XCTAssertEqual(depots.map(\.platforms.count), [RealLineDepotSite.luzhu.sidings, RealLineDepotSite.qingpu.sidings])
        let runs = try XCTUnwrap(session.railways?.metroRuns[Self.id])
        XCTAssertEqual(acquisition.trains.count, runs.overnight.values.reduce(0, +))
        XCTAssertEqual(acquisition.trainType, .b)
        XCTAssertTrue(session.acquireRealLine(offer), session.message?.text ?? "")

        let world = session.world
        let bought = try XCTUnwrap(world.lines.first)
        let stations = world.stations.filter(\.isDepot)
        XCTAssertEqual(Set(stations.map(\.name)), ["蘆竹機廠", "青埔機廠"])
        XCTAssertEqual(Set(bought.depots), Set(stations.map(\.id)))
        // Overnight: those the real timetable leaves between the ends
        // stand in the depots, those at the ends at their platforms.
        let between = runs.overnight.filter { $0.key != runs.stops.first && $0.key != runs.stops.last }.values.reduce(0, +)
        let inDepots = world.trains.count { train in stations.contains { world.stationsStoppedAt(by: train.id).contains($0.id) } }
        XCTAssertEqual(inDepots, between)
    }

    /// The real Taoyuan opening, its water read in: the line is offered.
    func testItIsOfferedOnTheTaoyuanOpening() throws {
        let session = try Self.opening("Taoyuan")
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == Self.id }, "on sale")
        let laid = session.realLineLaying.offer(for: line, raising: .viaducts)
        if let problem = laid.offer.problem, let acquisition = laid.laid, ProcessInfo.processInfo.environment["TYMC_DIAG"] != nil {
            for depot in [acquisition.depot].compactMap(\.self) + (acquisition.moreDepots ?? []) {
                print("TYMC_DIAG depot \(depot.name) pieces \(depot.platforms.map(\.piece))")
            }
            var probe = session.world.pricingCopy()
            let before = probe.network.edges.count
            do { _ = try session.buildStepByStep(acquisition, in: &probe, recording: false) } catch {
                var built = probe.network.edges.count - before
                for (index, piece) in acquisition.pieces.enumerated() {
                    if built < piece.curves.count {
                        let a = piece.nodes[built], b = piece.nodes[min(built + 1, piece.nodes.count - 1)]
                        print("TYMC_DIAG \(problem) \(error): piece \(index) of \(acquisition.pieces.count), edge \(built) of \(piece.curves.count), from \(a) to \(b), distances \(piece.distances[built])")
                        if case .trackConflict(let other) = error {
                            let mine = session.world.network.edge(other) == nil
                            let ends = probe.network.edge(other).flatMap { e in [e.from, e.to].compactMap { probe.network.node($0)?.position } }
                            print("TYMC_DIAG conflicting edge \(other): new with the line \(mine), ends \(ends ?? []), edges before \(before)")
                        }
                        break
                    }
                    built -= piece.curves.count
                }
            }
        }
        XCTAssertNil(session.realLineOffer(for: line).problem)
    }

    /// A new game on the real opening `name`, with the land, water and
    /// heights it reads, as ``WenhuLineTests`` opens Taipei.
    static func opening(_ name: String) throws -> GameSession {
        let data = RealWorldData.load(file: RealWorldDataLoadTests.file)
        let city = try XCTUnwrap(AcquisitionReportTests.cities.first { $0.name == name })
        let anchor = try XCTUnwrap(GeoAnchor(latitudeDegrees: city.latitude, longitudeDegrees: city.longitude))
        let world = GameLauncher.newWorld(at: anchor, options: NewGameOptions(), data: GameLauncher.NewWorldData(
            population: data.population, places: data.places, water: data.water, coverage: data.coverage, heights: data.heights
        ))
        let session = GameSession(world: world, language: .english)
        session.population = data.population
        session.places = data.places
        session.water = data.water
        session.heights = data.heights
        session.coverage = data.coverage
        session.railways = data.railways
        return session
    }

    /// Where each train of a deadlock stands and what it is doing, the
    /// first time one forms, played minute by minute (`TYMC_DIAG=1`;
    /// `DEPOT_RETURN_SIMPLE` and `DEPOT_RETURN_CONTROLLED` as the depot
    /// report reads them). Only when asked. Decision 556 (continued):
    /// `TYMC_DIAG_SAVE=<file>` saves the world at minute
    /// `TYMC_DIAG_SAVE_AT` (360) and `TYMC_DIAG_LOAD=<file>` with
    /// `TYMC_DIAG_FROM=<minute>` plays on from it, in seconds rather than
    /// minutes; `TYMC_DIAG_UNTIL=<minute>` stops; `TYMC_DIAG_TRACK=2,11`
    /// prints those trains every minute with who holds their way;
    /// `TYMC_DIAG_SUMMARY=1` prints every 15 minutes how many trains the
    /// deadlock search finds and which have stood 20 minutes or more;
    /// `TYMC_DIAG_OUT=<file>` writes it all there. A train the search
    /// finds for a minute is not one that stands: under the realistic
    /// rules it flags one now and then that is on its way again the next.
    func testWhereADeadlockForms() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TYMC_DIAG"] != nil else { throw XCTSkip("Set TYMC_DIAG=1.") }
        var world: GameWorld
        var start = 0
        if let load = environment["TYMC_DIAG_LOAD"] {
            world = try JSONDecoder().decode(GameWorld.self, from: Data(contentsOf: URL(fileURLWithPath: load)))
            start = Int(environment["TYMC_DIAG_FROM"] ?? "") ?? 0
        } else {
            world = try DepotReturnReportTests.bought(Self.id, side: 1 << 22)
            if environment["DEPOT_RETURN_SIMPLE"] != nil, environment["DEPOT_RETURN_CONTROLLED"] == nil { try world.setTrafficControl(false) }
        }
        let hours = Int(environment["TYMC_DIAG_HOURS"] ?? "") ?? 30
        var seen: Set<TrainID> = []
        var still: [TrainID: (place: String, since: Int)] = [:]
        func name(_ id: StationID?) -> String { id.flatMap { world.station(id: $0)?.name } ?? "?" }
        func clock(_ t: GameTime) -> String { String(format: "%02d:%02d", t.seconds % 86_400 / 3_600, t.seconds % 3_600 / 60) }
        let until = Int(environment["TYMC_DIAG_UNTIL"] ?? "") ?? hours * 60
        var out = ""
        defer {
            if let path = environment["TYMC_DIAG_OUT"] { try? Data(out.utf8).write(to: URL(fileURLWithPath: path)) }
        }
        for minute in start..<until {
            if let save = environment["TYMC_DIAG_SAVE"], minute == Int(environment["TYMC_DIAG_SAVE_AT"] ?? "") ?? 360 {
                try JSONEncoder().encode(world).write(to: URL(fileURLWithPath: save))
            }
            try world.advance(ticks: 1)
            if let track = environment["TYMC_DIAG_TRACK"] {
                let names = Set(track.split(separator: ",").map { "桃園機場捷運列車 \($0)" })
                for train in world.trains where names.contains(train.name) {
                    var memo = GameWorld.DirectionMemo()
                    let holder = world.holder(of: world.envelopeCover(of: train), except: train.id, holders: world.trackHolders(memo: &memo))
                    out += "TRACK \(clock(world.clock.now)) \(train.name) \(String(describing: train.position)) rate \(train.movement.rate) following \(world.isFollowing(train)) exec \(String(describing: train.execution).prefix(70)) envelope held by \(holder.flatMap { world.train(id: $0)?.name } ?? "-") reservation \(train.reservation.count)\n"
                }
            }
            if environment["TYMC_DIAG_SUMMARY"] != nil {
                for train in world.trains {
                    let place = String(describing: train.position)
                    if still[train.id]?.place != place { still[train.id] = (place, minute) }
                }
                if minute % 15 == 0 {
                    let flagged = world.deadlockedTrains()
                    let standing = world.trains.filter { $0.execution != nil && minute - (still[$0.id]?.since ?? minute) >= 20 }
                    out += "SUMMARY \(clock(world.clock.now)) flagged \(flagged.count) standing20 \(standing.map { "\($0.name.replacingOccurrences(of: "桃園機場捷運列車 ", with: ""))@\(world.stationsStoppedAt(by: $0.id).map(name))" })\n"
                    try? Data(out.utf8).write(to: URL(fileURLWithPath: environment["TYMC_DIAG_OUT"] ?? "/dev/null"))
                }
                continue
            }
            var stuck = world.deadlockedTrains().filter { !seen.contains($0) }
            for train in world.trains {
                let place = String(describing: train.position)
                if still[train.id]?.place != place { still[train.id] = (place, minute) }
                if case .travellingToStop? = train.execution, let since = still[train.id]?.since, minute - since == 20 { stuck.append(train.id) }
            }
            if let at = Int(environment["TYMC_DIAG_AT"] ?? ""), minute == at { stuck = world.trains.map(\.id) }
            guard !stuck.isEmpty else { continue }
            seen.formUnion(stuck)
            var lines = ["TYMC_DIAG minute \(minute) (\(clock(world.clock.now))): \(stuck.count) newly deadlocked or still for 20 minutes"]
            for id in stuck {
                guard let train = world.train(id: id) else { continue }
                var near = "?"
                if case .onEdge(let traversal, _) = train.position, let edge = world.network.edge(traversal.edge),
                   let node = world.network.node(edge.from) {
                    let point = node.position.plan
                    func away(_ station: Station) -> Double { (WorldVector(station.location) - WorldVector(point)).length }
                    near = world.stations.min { away($0) < away($1) }.map { "\($0.name) \(Int(away($0)) / 64) m" } ?? "?"
                }
                let plan = train.timetable.map { "\(name($0.station)) \(clock($0.departure))" }.joined(separator: " > ")
                var edgeText = "?"
                if case .onEdge(let traversal, let offset) = train.position { edgeText = "edge \(traversal.edge) \(traversal.direction) @\(offset)" }
                var routable = "-"
                if let position = train.position, let execution = train.execution {
                    let stop: Int? = switch execution { case .travellingToStop(let s, _): s; case .waitingAtStop(let s, _): s + 1 < train.timetable.count ? s + 1 : nil }
                    if let stop { routable = world.path(from: position, toStation: train.timetable[stop].station) == nil ? "NO ROUTE" : "route" }
                }
                var memo = GameWorld.DirectionMemo()
                var waits = "-"
                if let wait = world.waitingRoute(of: train, memo: &memo) {
                    if case .held(let by) = world.reservingDeparture(wait.candidate, memo: &memo) {
                        waits = "held by \(world.train(id: by)?.name ?? "?") (departs \(wait.departs))"
                    } else { waits = "waiting, granted?" }
                } else if let request = world.departureRequest(of: train, memo: &memo) {
                    waits = "request \(String(describing: world.reserving(request, memo: &memo)).prefix(60))"
                } else { waits = "no request, traffic wait \(String(describing: world.currentTrafficWait(train, plan: world.trafficPlan(memo: &memo), memo: &memo)).prefix(160))" }
                lines.append("  WAITS \(waits)")
                lines.append("  \(train.name): near \(near), \(edgeText), \(routable), exec \(String(describing: train.execution).prefix(120)), held \(String(describing: world.heldDeparture(of: id))), path \(train.movement.hasRemainingPath) to \(train.movement.edges.last.map { "\($0)" } ?? "-") end \(String(describing: train.movement.end)) following \(world.isFollowing(train)) reserved \(train.reservation.count), deadheading \(train.isDeadheading), at \(world.stationsStoppedAt(by: id).map(name)); plan \(plan.prefix(300))")
            }
            if environment["TYMC_DIAG_OUT"] != nil { out += lines.joined(separator: "\n") + "\n" } else {
                FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
            }
        }
    }
}
