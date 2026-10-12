import GameCore
@testable import GamePresentation
import XCTest

/// Decision 178: the section flow ("載客量") layer reads the world's kept
/// passenger plan and shades each stop-to-stop section by its load against
/// what its trains carry.
final class SectionFlowTests: XCTestCase {
    private func playedDemo() throws -> GameWorld {
        var world = DemoWorld.make(in: .english)
        try world.advance(ticks: 60)
        return world
    }

    func testAWorldWithoutAKeptPlanShowsNothing() {
        let world = GameWorld.newGame()
        let flow = SectionFlow(world: world)
        XCTAssertFalse(flow.hasPlan)
        XCTAssertTrue(flow.sections.isEmpty)
        XCTAssertTrue(flow.strokes(at: 8).isEmpty)
        XCTAssertNil(world.plannedPassengerLegFlows())
    }

    func testThePlannedLegFlowsAreReadFromTheKeptPlanAndLeaveTheWorldAlone() throws {
        let world = try playedDemo()
        let before = world
        let flows = try XCTUnwrap(world.plannedPassengerLegFlows())
        XCTAssertEqual(world, before)
        XCTAssertFalse(flows.isEmpty)
        XCTAssertTrue(flows.allSatisfy { $0.hourly.count == 24 && $0.hourly.allSatisfy { $0 >= 0 } && $0.from != $0.to })
        XCTAssertGreaterThan(flows.flatMap(\.hourly).reduce(0, +), 0)
        XCTAssertEqual(flows, world.plannedPassengerLegFlows(), "the same plan gives the same flows")
    }

    func testSectionsCarryEachHoursLoadAgainstTheirTrainsCapacity() throws {
        let world = try playedDemo()
        let flow = SectionFlow(world: world)
        XCTAssertTrue(flow.hasPlan)
        XCTAssertFalse(flow.sections.isEmpty)
        for section in flow.sections {
            XCTAssertEqual(section.loads.count, 24)
            XCTAssertEqual(section.capacities.count, 24)
            XCTAssertFalse(section.pieces.isEmpty)
            XCTAssertFalse(section.lines.isEmpty)
            XCTAssertTrue(section.pieces.allSatisfy { world.network.edge($0.edge) != nil && $0.start < $0.end })
        }
        XCTAssertEqual(flow.busiest, flow.sections.flatMap(\.loads).max())
        XCTAssertGreaterThan(flow.busiest, 0)
        XCTAssertTrue(flow.sections.contains { $0.capacities.contains { $0 > 0 } }, "the demo's trains give capacity")
        let rush = (0..<24).first { flow.strokes(at: $0).contains { $0.width > 2 } }
        XCTAssertNotNil(rush)
        // Both ways of a double-track line are separate sections.
        XCTAssertTrue(flow.sections.contains { section in
            flow.sections.contains { $0.from == section.to && $0.to == section.from }
        })
    }

    func testStrokesAreOrderedLightestFirstAndOverloadIsRed() throws {
        let edge = try XCTUnwrap(DemoWorld.make(in: .english).network.edges.first).id
        let piece = SectionFlow.Piece(edge: edge, start: 0, end: 10, forward: true)
        func section(_ load: Int64, _ capacity: Int64, from: Int) -> SectionFlow.Section {
            SectionFlow.Section(
                pieces: [piece], from: StationID(rawValue: from), to: StationID(rawValue: from + 1), lines: [LineID(rawValue: 1)],
                loads: Array(repeating: load, count: 24), capacities: Array(repeating: capacity, count: 24))
        }
        let flow = SectionFlow(sections: [section(300, 100, from: 1), section(50, 100, from: 3), section(0, 0, from: 5)], hasPlan: true)
        let strokes = flow.strokes(at: 8)
        XCTAssertEqual(strokes.map(\.section), [1, 0], "an empty section with no trains is left out; the heaviest is on top")
        XCTAssertEqual(strokes.last?.color, SectionFlow.overloadedColor)
        XCTAssertEqual(strokes.last?.width, 10)
        XCTAssertTrue(strokes.last?.isOverloaded == true)
        XCTAssertFalse(strokes.first?.isOverloaded == true)
        XCTAssertEqual(flow.reading(of: 0, at: 8)?.percent, 300)
        XCTAssertNil(flow.reading(of: 2, at: 8)?.percent)
        XCTAssertNil(flow.reading(of: 9, at: 8))
    }

    func testTheColourRunsFromPaleToDeepBlueByTheReferencesCurve() {
        XCTAssertEqual(SectionFlow.color(ratio: 0), PopTravel.RGB(red: 227, green: 242, blue: 253))
        XCTAssertEqual(SectionFlow.color(ratio: 1), PopTravel.RGB(red: 13, green: 71, blue: 161))
        XCTAssertEqual(SectionFlow.color(ratio: 1.0001), SectionFlow.overloadedColor)
        XCTAssertEqual(SectionFlow.color(ratio: -3), SectionFlow.color(ratio: 0))
        // pow(.5, .72) = 0.6071, so each channel is round(from + (to - from) * .6071).
        let half = SectionFlow.color(ratio: 0.5)
        XCTAssertEqual(Int(half.red), 97)
        XCTAssertEqual(Int(half.green), 138)
        XCTAssertEqual(Int(half.blue), 197)
    }

    func testTheWidthRunsFromTwoToTenPointsBySquareRoot() {
        XCTAssertEqual(SectionFlow.width(load: 0, busiest: 100), 2)
        XCTAssertEqual(SectionFlow.width(load: 100, busiest: 100), 10)
        XCTAssertEqual(SectionFlow.width(load: 25, busiest: 100), 6, accuracy: 1e-9)
        XCTAssertEqual(SectionFlow.width(load: 500, busiest: 100), 10)
        XCTAssertEqual(SectionFlow.width(load: 5, busiest: 0), 2)
    }

    func testALegGivesItsPassengersToEverySectionItRunsOver() {
        let stations = (1...4).map { StationID(rawValue: $0) }
        let line = ServiceLine(id: LineID(rawValue: 1), name: "L", stops: stations)
        XCTAssertEqual(SectionFlow.segments(of: line, from: stations[0], to: stations[3], direction: .outbound), [0, 1, 2])
        XCTAssertEqual(SectionFlow.segments(of: line, from: stations[3], to: stations[1], direction: .inbound), [1, 2])
        XCTAssertEqual(SectionFlow.segments(of: line, from: stations[3], to: stations[1], direction: .outbound), [], "not that way")
        XCTAssertEqual(SectionFlow.stations(of: line, segment: 1, direction: .outbound).to, stations[2])
        XCTAssertEqual(SectionFlow.stations(of: line, segment: 1, direction: .inbound).to, stations[1])
    }

    func testATappedSectionIsPickedAndWordedInBothLanguages() throws {
        let world = try playedDemo()
        let flow = SectionFlow(world: world)
        let hour = try XCTUnwrap((0..<24).first { flow.strokes(at: $0).contains { $0.width > 2 } })
        let stroke = try XCTUnwrap(flow.strokes(at: hour).last)
        let piece = try XCTUnwrap(stroke.pieces.first)
        let geometry = try XCTUnwrap(world.trackGeometry(of: piece.edge))
        let middle = geometry.location(at: (piece.start + min(piece.end, geometry.length)) / 2).position
        let picked = flow.nearestSection(toX: middle.x, y: middle.y, at: hour, within: 1_000, in: world)
        XCTAssertNotNil(picked)
        XCTAssertNil(flow.nearestSection(toX: middle.x + 10_000_000, y: middle.y, at: hour, within: 1_000, in: world))
        let text = try XCTUnwrap(flow.tooltip(of: stroke.section, at: hour, world: world, language: .traditionalChinese))
        XCTAssertTrue(text.contains("往"), text)
        XCTAssertTrue(text.contains("人／運能"), text)
        XCTAssertTrue(text.hasPrefix(SectionFlow.hourText(hour) + "–"), text)
        let english = try XCTUnwrap(flow.tooltip(of: stroke.section, at: hour, world: world, language: .english))
        XCTAssertTrue(english.contains("riders / capacity"), english)
    }

    func testThePassengerLoadLayerIsOneOfTheMapLayersAndFollowsTheTimeline() {
        XCTAssertTrue(PopTravelMode.allCases.contains(.sectionFlow))
        XCTAssertTrue(PopTravelMode.sectionFlow.followsTimeline)
        XCTAssertFalse(PopTravelMode.sectionFlow.usesHour, "it reads no travel demand grid")
        XCTAssertFalse(PopTravelMode.sectionFlow.isCityLayer)
        XCTAssertEqual(PopTravelMode.sectionFlow.title(in: .traditionalChinese), "載客量")
        XCTAssertFalse(PopTravelMode.sectionFlow.description(in: .english).isEmpty)
        var layers = MapLayerPreferences()
        layers.setShows(.sectionFlow, true)
        XCTAssertTrue(layers.shows(.sectionFlow))
        layers.setShows(.travel, true)
        XCTAssertFalse(layers.shows(.sectionFlow), "one layer at a time")
        XCTAssertTrue(PopTravelMode.travel.followsTimeline)
        XCTAssertFalse(PopTravelMode.landValue.followsTimeline)
    }
}
