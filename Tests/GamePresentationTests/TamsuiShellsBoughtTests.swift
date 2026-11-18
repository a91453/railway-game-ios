import Foundation
@testable import GameCore
@testable import GamePresentation
import XCTest

/// Decision 856: the Tamsui-Xinyi line's station shells (decision 827) on
/// stations the player buys. A real station bought where the real one
/// stands on a long viaduct is laid up on it, not on the ground, so its
/// shell stands over it (before, Jiantan bought stood 1 m over the ground
/// and had none, and Xinbeitou could not be bought); the Xinbeitou Branch
/// Line bought draws the island platforms at Beitou and Xinbeitou, and
/// their shells, which it picked and then left out as too narrow.
@MainActor
final class TamsuiShellsBoughtTests: XCTestCase {
    /// The shell the 3D map puts over `station`'s platforms in `world`.
    private func shell(over station: Station, in world: GameWorld, heights: HeightGrid?) throws -> Map3DTaipeiMRTStation? {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let scene = Map3DScene.frame(world: world, focus: (x: Double(station.location.x), y: Double(station.location.y)))
        var builder = Map3DScene.Builder(originX: scene.originX, originY: scene.originY, region: scene.region, world: world, heights: heights)
        let snapshot = world.railwaySnapshot()
        _ = builder.addTrack(snapshot)
        builder.addPlatforms(snapshot)
        XCTAssertFalse(builder.laidPlatforms.filter { $0.station == station.id }.isEmpty, "\(station.name): its platforms drawn")
        let network = snapshot.platforms.map { (station: $0.platform.station, structure: $0.structure, points: $0.points) }
        let lines = Map3DScene.Builder.shellLines(laid: builder.laidPlatforms, network: network) { builder.point($0) + Map3DScene.Builder.lifted }
        return lines[station.id].flatMap { builder.taipeiMRTShell(platforms: $0, frame: frame)?.station }
    }

    func testEachElevatedTamsuiStationBoughtStandsOnTheViaductUnderItsShell() throws {
        let names: [(String, Map3DTaipeiMRTStation)] = [
            ("圓山", .yuanshan), ("劍潭", .jiantan), ("士林", .shilin), ("芝山", .zhishan), ("明德", .mingde),
            ("石牌", .shipai), ("唭哩岸", .qilian), ("奇岩", .qiyan), ("北投", .beitou), ("新北投", .xinbeitou),
        ]
        XCTAssertEqual(Set(names.map(\.1)), Set(Map3DTaipeiMRTStation.allCases))
        for (name, expected) in names {
            let real = try BundledRealData.station(name, in: "mrt")
            var world = GameWorld.newGame(anchor: try XCTUnwrap(real.anchor))
            try world.mapGround()
            world.setUnlimitedFunds(true)
            let session = GameSession(world: world, language: .traditionalChinese)
            session.railways = try BundledRealData.railways()
            session.heights = try HeightGrid(data: RealWorldDataLoadTests.file("taiwan_heights", "dat"))
            session.selectTool(.network)
            session.setNetworkMode(.platform)
            let pin = try XCTUnwrap(session.nearestRealStation(to: try BundledRealData.point(real.coordinate, in: session.world)))
            let offer = session.realStationOffer(for: pin, system: "mrt")
            XCTAssertNil(offer.problem, "\(name): \(offer.problem ?? "")")
            XCTAssertTrue(session.buyRealStation(offer), "\(name): \(session.message?.text ?? "")")
            let bought = session.world
            let station = try XCTUnwrap(bought.stations.first { $0.name == name }, name)
            let snapshot = bought.railwaySnapshot()
            for platform in snapshot.platforms where platform.platform.station == station.id {
                XCTAssertTrue(platform.structure == .elevated || platform.structure == .bridge, "\(name): \(platform.structure)")
            }
            // The shell stands only where the rails are 5 m or more over
            // the ground (decision 827).
            XCTAssertEqual(try shell(over: station, in: bought, heights: session.heights), expected, name)
        }
    }

    func testTheXinbeitouBranchLineBoughtHasItsIslandsAndShells() throws {
        let (session, _) = try DemoRealLinesTrackReportTests.game(at: "北投", in: "mrt", half: 4_000)
        let line = try XCTUnwrap(session.buyableRealLines.first { $0.id == "trtc:R_XBT" })
        XCTAssertTrue(session.acquireRealLine(session.realLineOffer(for: line)), session.message?.text ?? "")
        let world = session.world
        for (name, expected) in [("北投", Map3DTaipeiMRTStation.beitou), ("新北投", .xinbeitou)] {
            let station = try XCTUnwrap(world.stations.first { $0.name == name && !$0.isDepot }, name)
            XCTAssertEqual(try shell(over: station, in: world, heights: session.heights), expected, name)
        }
    }
}
