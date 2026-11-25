import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 981: Victoria Harbour's two ferry crossings, Central–Tsim Sha
/// Tsui and Wan Chai–Tsim Sha Tsui, are real ferries the transit tool lays
/// on Hong Kong's map (``RealFerry/centralTsimShaTsui``,
/// ``RealFerry/wanChaiTsimShaTsui``), as Tamsui–Bali and Gushan–Cijin on
/// Taiwan's.
@MainActor
final class HongKongHarbourFerryTests: XCTestCase {
    private static let crossings = [RealFerry.centralTsimShaTsui, .wanChaiTsimShaTsui]

    /// A game on Hong Kong's map, as the launcher starts it, in the
    /// transit tool's ferry mode.
    private func ferryMode() throws -> (session: GameSession, frame: RealWorldFrame) {
        let session = try HongKongMapTests.hongKong()
        session.selectTool(.bus)
        session.setBusMode(.ferries)
        return (session, try XCTUnwrap(RealWorldFrame(world: session.world)))
    }

    /// How far `point` on `frame`'s map is from the real pier: its
    /// terminal where the pier's own point was moved off it.
    private func metres(from point: PlanPoint, to pier: RealFerry.Pier, _ frame: RealWorldFrame) -> Double {
        let (x, y) = frame.worldPosition(latitude: pier.terminalLatitude ?? pier.latitude, longitude: pier.terminalLongitude ?? pier.longitude)
        let dx = Double(point.x) - x, dy = Double(point.y) - y
        return (dx * dx + dy * dy).squareRoot() / Double(WorldCoordinate.unitsPerMetre)
    }

    /// On a new game there, before any land is read in, the mode offers
    /// both, and only them: Taiwan's two are off this map.
    func testTheModeOffersBothCrossingsOnHongKongsMap() throws {
        let (session, _) = try ferryMode()
        XCTAssertEqual(session.realFerryOffers, Self.crossings)
        XCTAssertEqual(session.realFerryOffers.map(\.name), ["中環—尖沙咀", "灣仔—尖沙咀"])
        XCTAssertEqual(session.realFerryOffers.map(\.englishName), ["Central–Tsim Sha Tsui", "Wan Chai–Tsim Sha Tsui"])
        // And on Taiwan's maps neither.
        let taiwan = GameWorld.newWholeTaiwanGame()
        for real in Self.crossings { XCTAssertNil(real.piers(in: taiwan), real.englishName) }
    }

    /// Each lays its piers by the real ones, Hong Kong Island's south of
    /// Tsim Sha Tsui's, with its real crossing; the four piers stand on
    /// four cells, so the two berths at Tsim Sha Tsui are drawn apart.
    func testEachLaysItsPiersByTheRealOnes() throws {
        let (session, frame) = try ferryMode()
        var cells: [CellPosition] = []
        for real in Self.crossings {
            session.traceRealFerry(real)
            let piers = session.ferryDraft
            XCTAssertEqual(piers.count, 2, real.englishName)
            for (cell, pier) in zip(piers, real.piers) {
                let off = metres(from: cell.middle, to: pier, frame)
                print("HK-STAR-FERRY \(real.englishName): \(pier.englishName) pier's cell \(cell) is \(Int(off)) m from the real pier")
                XCTAssertLessThanOrEqual(off, 120, "\(real.englishName) \(pier.englishName)")
            }
            XCTAssertGreaterThan(piers[0].row, piers[1].row, "\(real.englishName): Hong Kong Island lies south of Tsim Sha Tsui")
            let preview = try XCTUnwrap(session.ferryPreview)
            XCTAssertNil(preview.problem, real.englishName)
            XCTAssertEqual(preview.metres, real.legMetres[0])
            cells += piers
            session.undoFerryPier()
            session.undoFerryPier()
        }
        XCTAssertEqual(Set(cells).count, 4, "\(cells)")
    }

    /// Both open, one after the other: opening the first leaves the second
    /// on offer (they start from different piers), each is known as the
    /// real crossing it was laid as, and their boats' piers take the real
    /// names.
    func testBothOpenAndKeepTheirNames() throws {
        let (session, _) = try ferryMode()
        for (index, real) in Self.crossings.enumerated() {
            XCTAssertEqual(session.realFerryOffers, Array(Self.crossings[index...]))
            session.traceRealFerry(real)
            XCTAssertTrue(session.buildFerryRoute(), "\(real.englishName): \(session.message?.text ?? "") \(String(describing: session.ferryPreview?.problem))")
            let route = try XCTUnwrap(session.world.ferryRoutes.last)
            XCTAssertEqual(route.metres, real.legMetres[0])
            XCTAssertEqual(RealFerry.matching(route, in: session.world), real)
            for pier in route.piers { XCTAssertTrue(session.world.isPierCell(row: pier.row, column: pier.column)) }
            let boat = try XCTUnwrap(session.world.ferryBoatToFollow(on: route.id))
            let facts = try XCTUnwrap(session.world.ferryFollowFacts(of: boat, in: .traditionalChinese))
            XCTAssertTrue(facts.directionText.contains("尖沙咀碼頭"), facts.directionText)
        }
        XCTAssertEqual(session.world.ferryRoutes.count, 2)
        XCTAssertTrue(session.realFerryOffers.isEmpty)
        // Under 4 km, so the harbour ferry, not the outlying islands'
        // catamaran; the island's pier the hall, Tsim Sha Tsui's the finger.
        for route in session.world.ferryRoutes {
            XCTAssertEqual(Map3DFerry.Boat.drawn(forMetres: route.metres, in: .hongKong), .hongKong)
            XCTAssertEqual(Map3DFerries.pierKinds(of: route, in: .hongKong), [.hall, .finger])
        }
    }

    /// A tap on either real pier with no tool, where the game's pier
    /// stands or on the real berth it was moved from, opens the ferry mode
    /// with that pier's crossing laid: at Tsim Sha Tsui, the nearer
    /// berth's.
    func testATapOnAPierLaysItsCrossing() throws {
        for real in Self.crossings {
            for pier in real.piers {
                var spots = [(pier.latitude, pier.longitude)]
                if let latitude = pier.terminalLatitude, let longitude = pier.terminalLongitude { spots.append((latitude, longitude)) }
                for (latitude, longitude) in spots {
                    let session = try HongKongMapTests.hongKong()
                    let frame = try XCTUnwrap(RealWorldFrame(world: session.world))
                    let (x, y) = frame.worldPosition(latitude: latitude, longitude: longitude)
                    XCTAssertTrue(session.openRealFerryStation(at: PlanPoint(x: Int64(x.rounded()), y: Int64(y.rounded()))))
                    XCTAssertEqual(session.busMode, .ferries)
                    XCTAssertEqual(session.ferryDraftLegs, real.legMetres, "\(real.englishName) from \(pier.englishName)")
                    XCTAssertEqual(session.message?.kind, .success)
                }
            }
        }
    }

    /// On the 3D map the piers stand out from the shore the map draws,
    /// the boats' berths on open water clear of the city's buildings, and
    /// each crossing runs over water from berth to berth.
    func testThePiersStandAtTheDrawnShore() throws {
        let (session, frame) = try ferryMode()
        for real in Self.crossings {
            session.traceRealFerry(real)
            XCTAssertTrue(session.buildFerryRoute(), real.englishName)
        }
        let world = session.world
        let tiles = try HongKongBaseMapTests.tiles(), footprints = try HongKongBuildingsTests.tiles()
        for (number, route) in world.ferryRoutes.enumerated() {
            let name = Self.crossings[number].englishName
            let middle = (x: Double(route.piers[0].middle.x + route.piers[1].middle.x) / 2, y: Double(route.piers[0].middle.y + route.piers[1].middle.y) / 2)
            let scene = Map3DScene(world: world, focus: middle, baseMap: tiles, footprints: footprints)
            XCTAssertEqual(Map3DStreetRegion(world: world), .hongKong)
            let line = try XCTUnwrap(Map3DFerries(world: world, scene: scene).lines.first { $0.id == route.id })
            XCTAssertEqual(line.boat, .hongKong)
            XCTAssertEqual(line.piers.map(\.kind), [.hall, .finger])
            let swing = (line.boat.length * line.boat.length + line.boat.beam * line.boat.beam).squareRoot() / 2
            for (index, pier) in line.piers.enumerated() {
                let drawn = scene.drawnWater(round: pier.origin, radius: 200)
                let cell = scene.point(worldX: Double(route.piers[index].middle.x), worldY: Double(route.piers[index].middle.y), height: 0)
                print("HK-STAR-FERRY \(name) pier \(index) (\(pier.kind)): its bank edge \(Int((pier.origin - cell).length)) m from its cell's middle, "
                    + "berth \(Int((pier.berth - pier.origin).length)) m out")
                XCTAssertTrue(drawn.isOpenWater(x: pier.berth.x, z: pier.berth.z), "\(name) pier \(index): the berth on the water")
                let at = scene.worldPosition(of: pier.origin)
                let off = metres(from: PlanPoint(x: Int64(at.x.rounded()), y: Int64(at.y.rounded())), to: Self.crossings[number].piers[index], frame)
                print("HK-STAR-FERRY \(name) pier \(index): drawn \(Int(off)) m from the real pier")
                XCTAssertLessThanOrEqual(off, 120, "\(name) pier \(index): drawn by the real pier")
                for turn in 0..<16 {
                    let angle = Float(turn) * .pi / 8
                    let p = pier.berth + Map3DPoint(cos(angle), 0, sin(angle)) * swing
                    XCTAssertTrue(drawn.isOpenWater(x: p.x, z: p.z), "\(name) pier \(index): the boat clear of land and buildings, \(turn)")
                }
            }
            let (a, b) = (line.piers[0].berth, line.piers[1].berth)
            let drawn = scene.drawnWater(round: (a + b) * 0.5, radius: (b - a).length * 0.7 + 20)
            for s in stride(from: Float(0), through: 1, by: 4 / (b - a).length) {
                let p = Map3DFerries.point(line, leg: 0, at: s)
                XCTAssertTrue(drawn.isOpenWater(x: p.x, z: p.z), "\(name): the crossing over water \(s)")
            }
        }
    }
}
