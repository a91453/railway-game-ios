import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// Decision 970: the network tool's gauge, what the menus say about it,
/// and a chain of stretches laid towards track taking that track's gauge.
final class TrackGaugeUITests: XCTestCase {
    private func world() throws -> GameWorld {
        try makeWorld(width: 32_768, height: 16_384, balance: 100_000_000, speed: .paused)
    }

    @MainActor
    func testTheToolsGaugeIsAutomaticUntilChosen() throws {
        let session = GameSession(world: try world())
        XCTAssertNil(session.networkGauge)
        session.chooseNetworkGauge(.shinkansen)
        XCTAssertEqual(session.networkGauge, .shinkansen)
        session.chooseNetworkGauge(nil)
        XCTAssertNil(session.networkGauge)
    }

    func testEachGaugeHasANameInBothLanguages() {
        var names: Set<String> = []
        for gauge in TrackGauge.offered {
            for language in [DisplayLanguage.english, .traditionalChinese] {
                let name = gauge.name(in: language)
                XCTAssertFalse(name.isEmpty)
                names.insert(name)
            }
        }
        XCTAssertEqual(names.count, TrackGauge.offered.count * 2)
        XCTAssertEqual(TrackGauge.forest.name(in: .english), "762 mm (forest railway)")
        XCTAssertEqual(TrackGauge(rails: [.forest, .cape]).name(in: .english), "762 + 1,067 mm")
        XCTAssertEqual(TrackGauge(rails: [.cape, .standard], loading: .shinkansen).name(in: .traditionalChinese), "1,067 + 1,435 mm 高鐵")
    }

    /// NETWORK-PANEL-SIMPLE: the gauge button says the millimetres alone,
    /// short enough for one line, and no two gauges alike.
    func testEachGaugesButtonIsShortAndItsOwn() {
        for language in [DisplayLanguage.english, .traditionalChinese] {
            let names = TrackGauge.offered.map { $0.shortName(in: language) } + [TrackGauge.automaticShortName(in: language)]
            XCTAssertEqual(Set(names).count, names.count, "\(names)")
            for name in names {
                XCTAssertLessThanOrEqual(name.count, 20, name)
                XCTAssertFalse(name.contains("（") || name.contains("("), name)
            }
        }
        XCTAssertEqual(TrackGauge.standard.shortName(in: .traditionalChinese), "1,435 mm")
        XCTAssertEqual(TrackGauge.shinkansen.shortName(in: .traditionalChinese), "1,435 mm 高鐵")
        XCTAssertEqual(TrackGauge.automaticShortName(in: .traditionalChinese), "自動軌距")
    }

    func testARealTrainWithNoTrackOfItsGaugeIsToldToLaySome() throws {
        var world = try world()
        XCTAssertEqual(
            world.gaugeFirstHint(for: .highSpeed, in: .english),
            " It needs track of its own gauge: lay some first, choosing 1,435 mm high-speed (wide trains) in the track tool."
        )
        XCTAssertNil(world.gaugeFirstHint(for: nil, in: .english), "the standard car runs on any track")
        XCTAssertNil(world.gaugeFirstHint(for: .a, in: .english))
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        _ = try world.buildTrackEdge(from: a, to: b)
        XCTAssertNil(world.gaugeFirstHint(for: .puyuma, in: .english), "1,067 mm track carries it")
        XCTAssertNotNil(world.gaugeFirstHint(for: .alishan, in: .english))
    }

    func testAChainLaidTowardsTrackTakesItsGauge() throws {
        var world = try world()
        let a = try world.buildTrackNode(at: WorldCoordinate(x: 2_048, y: 2_048))
        let b = try world.buildTrackNode(at: WorldCoordinate(x: 6_144, y: 2_048))
        _ = try world.buildTrackEdge(from: a, to: b, gauge: .shinkansen)
        let points = [WorldCoordinate(x: 14_336, y: 2_048), WorldCoordinate(x: 10_240, y: 2_048), WorldCoordinate(x: 6_144, y: 2_048)]
        let stretches = [
            PlayerCommand.TrackStretch(start: .point(points[0].plan), end: .point(points[1].plan), from: points[0], to: points[1],
                                       curve: .straight, profile: .uniform, structure: .surface, ground: [points[0].plan, points[1].plan]),
            PlayerCommand.TrackStretch(start: .point(points[1].plan), end: .node(b), from: points[1], to: points[2],
                                       curve: .straight, profile: .uniform, structure: .surface, ground: [points[1].plan, points[2].plan]),
        ]
        XCTAssertEqual(stretches.joiningGauge(in: world).map(\.gauge), [.shinkansen, .shinkansen])
        let asked = stretches.map {
            PlayerCommand.TrackStretch(start: $0.start, end: $0.end, from: $0.from, to: $0.to, curve: $0.curve, profile: $0.profile,
                                       structure: $0.structure, ground: $0.ground, gauge: .cape)
        }
        XCTAssertEqual(asked.joiningGauge(in: world).map(\.gauge), [.cape, .cape], "a chain of a chosen gauge keeps it")
    }
}
