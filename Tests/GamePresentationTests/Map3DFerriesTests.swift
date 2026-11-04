@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 585 PR-3 (FERRY3): the ferries and pier of decision 579 in the
/// 3D map: the models as Codex's producer made them, the boats' places on
/// the timetable, their turns, and which are drawn whole and which far.
final class Map3DFerriesTests: XCTestCase {
    static var pack: Map3DModelPack { Map3DModelPack.standard }

    // MARK: - The models

    /// The producer's triangle counts (decision 579's README: near 2,368,
    /// 6,304 and 1,284; far 1,504, 2,344 and 684), every part a closed
    /// solid, the far model lighter, the lamps lit.
    func testTheModelsAreTheStudies() {
        let counts: [(CableSolids, Int)] = [
            (Map3DFerry.solids(.tamsui, far: false), 2_368), (Map3DFerry.solids(.cijin, far: false), 6_304),
            (Map3DFerry.pierSolids(far: false), 1_284), (Map3DFerry.solids(.tamsui, far: true), 1_504),
            (Map3DFerry.solids(.cijin, far: true), 2_344), (Map3DFerry.pierSolids(far: true), 684),
        ]
        for (index, (solids, triangles)) in counts.enumerated() {
            XCTAssertEqual(solids.triangles.count, triangles, "model \(index)")
            XCTAssertEqual(solids.openSolids(), [], "model \(index)")
        }
        for boat in Map3DFerry.Boat.allCases {
            let near = Map3DFerry.model(boat), far = Map3DFerry.model(boat, far: true)
            XCTAssertLessThan(far.triangleCount, near.triangleCount)
            // Port red, starboard green and the masthead white glow at night.
            for model in [near, far] {
                let lit = Set(model.vertices.filter(\.glows).map(\.color))
                XCTAssertTrue(lit.contains(CableParts.Paint.red), model.name)
                XCTAssertTrue(lit.contains(CableParts.Paint.green), model.name)
                XCTAssertTrue(lit.contains(CableParts.Paint.white), model.name)
            }
            // As long as the real boat, give or take the bulwark's beam.
            XCTAssertEqual(near.maximum.x - near.minimum.x, boat.length, accuracy: 0.3, boat.rawValue)
            // The hull reaches below the waterline, the masthead light high.
            XCTAssertLessThan(near.minimum.z, -0.8)
            XCTAssertGreaterThan(near.maximum.z, boat == .tamsui ? 6 : 9)
        }
        XCTAssertEqual(Map3DFerry.Boat.drawn(forMetres: 715), .cijin)
        XCTAssertEqual(Map3DFerry.Boat.drawn(forMetres: 1_260), .tamsui)
    }

    func testTheDrawnModelsAreInTheGamesPack() {
        for model in Map3DFerry.drawn {
            XCTAssertNotNil(Self.pack.index(of: model.name), model.name)
            XCTAssertNil(Map3DModelPack.studies.index(of: model.name), model.name)
            // Shaded as a whole vessel, not a car between two others.
            XCTAssertFalse(Map3DTrainOcclusion.isMiddle(model.name), model.name)
        }
        XCTAssertNotNil(Map3DFerries.Models(Self.pack))
    }

    // MARK: - The timetable

    /// Tamsui–Bali's 1,260 m: 6.3 minutes across, two at each end, 16.6
    /// minutes a sailing (GameCore's round trip rounds up to 17).
    func testOneSailingCrossesLiesTurnsAndComesBack() {
        let legs: [Int64] = [1_260]
        XCTAssertEqual(Map3DFerries.sailingMinutes(legMetres: legs), 16.6, accuracy: 1e-9)
        XCTAssertEqual(Map3DFerries.stage(atMinute: 0, legMetres: legs), .sailing(leg: 0, share: 0, outbound: true))
        guard case .sailing(0, let half, true) = Map3DFerries.stage(atMinute: 3.15, legMetres: legs) else { return XCTFail() }
        XCTAssertEqual(half, 0.5, accuracy: 1e-9)
        guard case .docked(1, let lying, true) = Map3DFerries.stage(atMinute: 7.3, legMetres: legs) else { return XCTFail() }
        XCTAssertEqual(lying, 0.5, accuracy: 1e-9)
        guard case .sailing(0, let back, false) = Map3DFerries.stage(atMinute: 8.3 + 3.15, legMetres: legs) else { return XCTFail() }
        XCTAssertEqual(back, 0.5, accuracy: 1e-9)
        guard case .docked(0, _, false) = Map3DFerries.stage(atMinute: 16, legMetres: legs) else { return XCTFail() }
        XCTAssertNil(Map3DFerries.stage(atMinute: 16.6, legMetres: legs))
        XCTAssertNil(Map3DFerries.stage(atMinute: -0.1, legMetres: legs))
        // Three piers: the middle one twice.
        let three: [Int64] = [600, 600]
        guard case .docked(1, _, true) = Map3DFerries.stage(atMinute: 3.5, legMetres: three),
              case .sailing(1, _, true) = Map3DFerries.stage(atMinute: 5, legMetres: three),
              case .docked(1, _, false) = Map3DFerries.stage(atMinute: 3 + 2 + 3 + 2 + 3 + 1, legMetres: three) else { return XCTFail() }
    }

    /// Two boats every 15 minutes from 07:00: the first sails at 07:00,
    /// one is under way at 07:05, none before seven or on a closed day.
    func testTheSailingsFollowTheHeadway() throws {
        let (world, id) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30))
        let route = try XCTUnwrap(world.ferryRoute(id: id))
        let departures = Map3DFerries.departures(of: route, onDay: 0)
        XCTAssertEqual(departures.first, 7 * 60)
        XCTAssertEqual(departures.dropFirst().first, 7 * 60 + 15)
        XCTAssertEqual(Int64(departures.count), route.dailyDepartures(onDay: 0))
        func sailings(_ minute: Double, open: Bool = true) -> [Map3DFerries.Stage] {
            Map3DFerries.sailings(of: route, atSecond: minute * 60, open: { _ in open })
        }
        XCTAssertEqual(sailings(6 * 60 + 59), [])
        XCTAssertEqual(sailings(7 * 60 + 5).count, 1)
        XCTAssertEqual(sailings(7 * 60 + 5, open: false), [])
        // A sailing from the evening before runs on past midnight.
        let late = BusService.runs([23 * 60 + 55])
        let night = FerryRoute(id: id, piers: route.piers, legMetres: route.legMetres, service: late, boats: 1)
        XCTAssertEqual(Map3DFerries.sailings(of: night, atSecond: Double(GameTime.secondsPerDay) + 120, open: { _ in true }).count, 1)
    }

    // MARK: - In the scene

    /// Each pier stands out over the water on its side of the river, the
    /// boats' berths off it, and the boat drawn fits the crossing.
    func testThePiersStandOutOverTheWater() throws {
        let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30))
        let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
        let line = try XCTUnwrap(laid.lines.first)
        XCTAssertEqual(line.boat, .tamsui)
        XCTAssertEqual(line.piers.count, 2)
        // Row 3 looks south over rows 4 and 5, row 6 north: the plan's
        // rows run with the scene's z.
        XCTAssertGreaterThan(line.piers[0].out.z, 0.99)
        XCTAssertLessThan(line.piers[1].out.z, -0.99)
        for pier in line.piers {
            let gap = (pier.berth - pier.origin).length
            XCTAssertEqual(gap, Map3DFerry.pontoonReach + Map3DFerries.berthGap + Map3DFerry.Boat.tamsui.length / 2, accuracy: 0.01)
        }
        let short = try makeFerryWorld(from: CellPosition(row: 3, column: 20), to: CellPosition(row: 6, column: 22)).world
        XCTAssertEqual(Map3DFerries(world: short, scene: Map3DScene(world: short)).lines.first?.boat, .cijin)
    }

    /// A passenger boat sails bow first both ways and turns round while
    /// it lies at an end; the double-ended ferry keeps its heading and
    /// sails back the other end first.
    func testTheBoatsTurnRoundOrSailBackEndFirst() throws {
        for (to, kind) in [(CellPosition(row: 6, column: 30), Map3DFerry.Boat.tamsui), (CellPosition(row: 6, column: 12), .cijin)] {
            let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: to)
            let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
            let line = try XCTUnwrap(laid.lines.first)
            XCTAssertEqual(line.boat, kind)
            let way = Map3DFerries.way(line, leg: 0)
            func forward(_ stage: Map3DFerries.Stage) -> Map3DPoint { Map3DFerries.place(stage, on: line).forward }
            func near(_ a: Map3DPoint, _ b: Map3DPoint) -> Bool { (a - b).length < 1e-3 }
            XCTAssertTrue(near(forward(.sailing(leg: 0, share: 0.5, outbound: true)), way))
            XCTAssertTrue(near(forward(.docked(pier: 1, share: 0, outbound: true)), way))
            if kind == .tamsui {
                XCTAssertTrue(near(forward(.docked(pier: 1, share: 1, outbound: true)), -way))
                // Halfway round it is broadside.
                XCTAssertEqual(forward(.docked(pier: 1, share: 0.5, outbound: true)).dot(way), 0, accuracy: 1e-3)
                XCTAssertTrue(near(forward(.sailing(leg: 0, share: 0.5, outbound: false)), -way))
                XCTAssertTrue(near(forward(.docked(pier: 0, share: 1, outbound: false)), way))
            } else {
                XCTAssertTrue(near(forward(.docked(pier: 1, share: 1, outbound: true)), way))
                XCTAssertTrue(near(forward(.sailing(leg: 0, share: 0.5, outbound: false)), way))
            }
            // Out from the first berth and back to it, eased at the ends.
            XCTAssertTrue(near(Map3DFerries.place(.sailing(leg: 0, share: 0, outbound: true), on: line).point, line.piers[0].berth))
            XCTAssertTrue(near(Map3DFerries.place(.sailing(leg: 0, share: 1, outbound: true), on: line).point, line.piers[1].berth))
            XCTAssertTrue(near(Map3DFerries.place(.sailing(leg: 0, share: 1, outbound: false), on: line).point, line.piers[0].berth))
            let middle = (line.piers[0].berth + line.piers[1].berth) * 0.5
            XCTAssertTrue(near(Map3DFerries.place(.sailing(leg: 0, share: 0.5, outbound: false), on: line).point, middle))
        }
    }

    /// Close to a pier the boats and the pier are drawn whole; a kilometre
    /// off, far; farther than ``Map3DFerries/farReach``, not at all. Idle
    /// boats lie beside the first pier before the first sailing.
    func testNearFarAndNothing() throws {
        let (world, _) = try makeFerryWorld(from: CellPosition(row: 3, column: 10), to: CellPosition(row: 6, column: 30), boats: 3)
        let laid = Map3DFerries(world: world, scene: Map3DScene(world: world))
        let line = try XCTUnwrap(laid.lines.first)
        let pack = Self.pack
        let models = try XCTUnwrap(Map3DFerries.Models(pack))
        let pier = line.piers[0].origin
        let eye = pier + Map3DPoint(0, 60, -60)
        // 06:00: no sailing, three boats beside the pier.
        let dawn = laid.frame(second: 6 * 3_600, eye: eye, target: pier, pack: pack)
        XCTAssertEqual(dawn.nearBoats, 3)
        XCTAssertTrue(dawn.instances.contains { $0.model == models.pier.near })
        XCTAssertEqual(dawn.instances.filter { $0.model == models.boat[.tamsui]!.near }.count, 3)
        // 07:01: one sailing, two idle.
        let morning = laid.frame(second: 7 * 3_600 + 60, eye: eye, target: pier, pack: pack)
        XCTAssertEqual(morning.nearBoats + morning.farBoats, 3)
        let far = laid.frame(second: 6 * 3_600, eye: pier + Map3DPoint(0, 600, -1_000), target: pier, pack: pack)
        XCTAssertEqual(far.nearBoats, 0)
        XCTAssertEqual(far.farBoats, 3)
        XCTAssertTrue(far.instances.contains { $0.model == models.pier.far })
        let gone = laid.frame(second: 6 * 3_600, eye: pier + Map3DPoint(0, 600, -5_000), target: pier, pack: pack)
        XCTAssertTrue(gone.instances.isEmpty)
        // The idle boats side by side, not on one another.
        let idle = (1...3).map { Map3DFerries.idle($0, on: line).point }
        XCTAssertGreaterThan((idle[1] - idle[0]).length, Map3DFerry.Boat.tamsui.beam)
        // Worst case, every boat whole and far: within the frame's budget.
        let triangles = Map3DFerries.mostNearBoats * Map3DFerry.model(.cijin).triangleCount
            + Map3DFerries.mostFarBoats * Map3DFerry.model(.cijin, far: true).triangleCount
        XCTAssertLessThan(triangles, 180_000)
    }

    // MARK: - Helpers

    /// 64 × 16 cells with water across rows 4 and 5, and one ferry route
    /// between two piers, a boat every 15 minutes.
    private func makeFerryWorld(from a: CellPosition, to b: CellPosition, boats: Int = 2) throws -> (world: GameWorld, id: FerryRouteID) {
        var world = try makeWorld(width: 64 * Land.cellLength, height: 16 * Land.cellLength, balance: Money(10_000_000_000))
        try world.setWater((4...5).flatMap { row in (0..<64).map { CellPosition(row: row, column: $0) } })
        let route = try world.createFerryRoute(piers: [a, b], service: .every(minutes: 15), boats: boats)
        return (world, route.id)
    }
}
