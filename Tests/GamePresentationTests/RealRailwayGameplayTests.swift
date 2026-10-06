import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// The app's copy of the real railway data, read the way the app reads it
/// (``RealRailways/load(file:)``), from the repository.
enum BundledRealData {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RailwayGameApp/Resources/RealRailways")

    static func file(_ name: String, _ ext: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("\(name).\(ext)"))
    }

    static let loaded: RealRailways.Loaded = RealRailways.load { name, ext in try file(name, ext) }

    static func railways() throws -> RealRailways {
        try XCTUnwrap(loaded.railways)
    }

    /// The world point of real coordinate `coordinate` in `world`.
    static func point(_ coordinate: RealRailways.Coordinate, in world: GameWorld) throws -> PlanPoint {
        let frame = try XCTUnwrap(RealWorldFrame(world: world))
        let position = frame.worldPosition(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return PlanPoint(x: Int64(position.x.rounded()), y: Int64(position.y.rounded()))
    }

    /// The first station of `system` named `name`.
    static func station(_ name: String, in system: String) throws -> RealRailways.Station {
        try XCTUnwrap(railways().stations.first { $0.system.id == system && $0.chinese == name })
    }
}

@MainActor
final class RealRailwayGameplayTests: XCTestCase {
    func testTheBundledDataLoadsWithoutIssues() throws {
        let loaded = BundledRealData.loaded
        XCTAssertEqual(loaded.issues, [])
        let railways = try BundledRealData.railways()
        XCTAssertNotNil(railways.stationData?.overtakeTracks)
        XCTAssertNotNil(railways.transfers)
        XCTAssertEqual(railways.operations?.systems.count, 10, "TRA, THSR, AFR and the seven metro and light rail systems")
        XCTAssertEqual(railways.operations?.timetableIssues, [])
    }

    /// A real-world game at Taipei Main Station, with the bundled data.
    private func taipeiSession(language: DisplayLanguage = .traditionalChinese) throws -> (GameSession, PlanPoint) {
        let tra = try BundledRealData.station("臺北", in: "tra_sched")
        let anchor = try XCTUnwrap(tra.anchor)
        let world = GameWorld.newGame(anchor: anchor)
        let session = GameSession(world: world, language: language)
        session.railways = try BundledRealData.railways()
        return (session, try BundledRealData.point(tra.coordinate, in: world))
    }

    func testTheStationInspectorShowsTheRealStation() throws {
        let (session, taipei) = try taipeiSession()
        var world = session.world
        let id = try world.buildStation(named: "台北", at: taipei).id
        let other = try world.buildStation(named: "我的車站", at: PlanPoint(x: taipei.x + 64_000, y: taipei.y)).id
        let real = try XCTUnwrap(session.railways)
        let english = GameSession(world: world, language: .english)
        english.railways = real
        let chinese = GameSession(world: world, language: .traditionalChinese)
        chinese.railways = real

        let details = english.realStationDetails(of: id)
        XCTAssertTrue(details.contains("TRA 1000 · Special Class"), "\(details)")
        XCTAssertTrue(details.contains { $0.hasPrefix("Address: ") && $0.contains("北平西路") }, "\(details)")
        XCTAssertTrue(details.contains("Taipei Metro BL12 / R10"), "\(details)")
        XCTAssertTrue(details.contains { $0.hasPrefix("Codes: ") && $0.contains("THSR 1000") && $0.contains("TYMC A1") && !$0.contains("TRA 1000") }, "\(details)")
        // Transfer partners: the other railways' routes, not its own.
        let transfers = try XCTUnwrap(details.first { $0.hasPrefix("Transfers: ") })
        XCTAssertTrue(transfers.contains("高鐵"), transfers)
        XCTAssertTrue(chinese.realStationDetails(of: id).contains("台鐵 1000 · 特等站"))
        XCTAssertEqual(english.realStationDetails(of: other), [], "Not a real station")
    }

    func testTheSameNameFarAwayIsNotTheRealStation() throws {
        let (session, taipei) = try taipeiSession()
        var world = session.world
        // 3 km away: not Taipei Main Station.
        let id = try world.buildStation(named: "台北", at: PlanPoint(x: taipei.x + 3_000 * 64, y: taipei.y)).id
        let far = GameSession(world: world, language: .english)
        far.railways = session.railways
        XCTAssertEqual(far.realStationDetails(of: id), [])
    }

    func testPlatformLengthDefaultsFromTheTRAStationGrade() throws {
        let session = GameSession(world: .newGame(), language: .english)
        session.railways = try BundledRealData.railways()
        // estLenByTier [378, 330, 307, 270, 188] m in 16 m cars, at most 16.
        XCTAssertEqual(session.realPlatformCars(forStationNamed: "台北", at: nil), 16, "特等 378 m")
        XCTAssertEqual(session.realPlatformCars(forStationNamed: "猴硐", at: nil), 16, "三等 270 m")
        XCTAssertEqual(session.realPlatformCars(forStationNamed: "三坑", at: nil), 11, "簡易 188 m: 11 cars")
        XCTAssertNil(session.realPlatformCars(forStationNamed: "Station 1", at: nil))
    }

    func testANewLineOnARealLineStartsWithItsHeadways() throws {
        var world = GameWorld.newGame()
        let tamsui = try world.buildStation(named: "淡水", at: PlanPoint(x: 64_000, y: 64_000)).id
        let hongshulin = try world.buildStation(named: "紅樹林", at: PlanPoint(x: 128_000, y: 64_000)).id
        let elsewhere = try world.buildStation(named: "Nowhere", at: PlanPoint(x: 192_000, y: 64_000)).id
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()

        let match = try XCTUnwrap(session.realLine(calling: [tamsui, hongshulin]))
        XCTAssertEqual(match.system, "trtc")
        XCTAssertEqual(match.line.id, "R")
        // The red line: 360 s at the peak, 540 s off it.
        XCTAssertEqual(session.realTargetHeadways(of: match.line, inSystem: match.system), TargetHeadways(peak: 6, offPeak: 9))
        XCTAssertNil(session.realLine(calling: [tamsui, elsewhere]), "Two real stops at least")

        session.selectStation(tamsui)
        session.addSelectedStationToLineDraft()
        session.selectStation(hongshulin)
        session.addSelectedStationToLineDraft()
        session.createLineFromDraft()
        let line = try XCTUnwrap(session.world.lines.last)
        XCTAssertEqual(line.targetHeadways, TargetHeadways(peak: 6, offPeak: 9))
        XCTAssertEqual(session.message?.kind, .success)
        XCTAssertTrue(session.message?.text.contains("Target headways from") == true, "\(String(describing: session.message))")
    }

    func testANewLineOffTheRealLinesHasNoTargets() throws {
        var world = GameWorld.newGame()
        let a = try world.buildStation(named: "Alpha", at: PlanPoint(x: 64_000, y: 64_000)).id
        let b = try world.buildStation(named: "Beta", at: PlanPoint(x: 128_000, y: 64_000)).id
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        session.selectStation(a)
        session.addSelectedStationToLineDraft()
        session.selectStation(b)
        session.addSelectedStationToLineDraft()
        session.createLineFromDraft()
        XCTAssertEqual(session.world.lines.last?.targetHeadways, TargetHeadways.none)
    }

    func testTheHighSpeedRailTakesItsHeadwaysFromItsTrains() throws {
        let operations = try XCTUnwrap(BundledRealData.railways().operations)
        let thsr = try XCTUnwrap(operations.line(id: "THSR", inSystem: "thsr"))
        XCTAssertEqual(thsr.stations.count, 12)
        XCTAssertNil(thsr.peakHeadwaySec, "thsr_track.json has none")
        let peak = try XCTUnwrap(operations.headway(forLine: "THSR", inSystem: "thsr", peak: true))
        let offPeak = try XCTUnwrap(operations.headway(forLine: "THSR", inSystem: "thsr", peak: false))
        XCTAssertTrue((600 ... 3_600).contains(peak), "\(peak)")
        XCTAssertTrue((600 ... 3_600).contains(offPeak), "\(offPeak)")
    }

    func testTrackSectionsAreShownAsInformation() throws {
        var world = GameWorld.newGame()
        let taipei = try world.buildStation(named: "台北", at: PlanPoint(x: 64_000, y: 64_000)).id
        let wanhua = try world.buildStation(named: "萬華", at: PlanPoint(x: 128_000, y: 64_000)).id
        let sandiaoling = try world.buildStation(named: "三貂嶺", at: PlanPoint(x: 192_000, y: 64_000)).id
        let houtong = try world.buildStation(named: "猴硐", at: PlanPoint(x: 256_000, y: 64_000)).id
        let session = GameSession(world: world, language: .english)
        session.railways = try BundledRealData.railways()
        XCTAssertEqual(session.realTrackSectionText(between: taipei, and: wanhua), "Real: double track (臺北–萬華)")
        XCTAssertNotNil(session.realTrackSectionText(between: sandiaoling, and: houtong))
        XCTAssertNil(session.realTrackSectionText(between: taipei, and: houtong), "No such section")
    }
}
