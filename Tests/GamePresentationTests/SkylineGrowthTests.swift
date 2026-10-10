import GameCore
import GamePresentation
import XCTest

/// Decision 140: a night's growth on the plain map, from one skyline to the
/// next: new buildings rise out of the ground, raised ones from their old
/// height, one after another, lit as they rise; only for growth the clock
/// moved forward to.
final class SkylineGrowthTests: XCTestCase {
    private let night = GameTime(seconds: GameTime.secondsPerDay)

    private func lot(_ row: Int, _ column: Int, _ use: LandUse, _ density: Int) -> CitySkyline.Lot {
        CitySkyline.Lot(row: row, column: column, use: use, density: density)
    }

    func testNewAndRaisedBuildingsGrowAndNothingElseDoes() throws {
        let old = CitySkyline(lots: [
            lot(0, 0, .residential, 1),
            lot(0, 1, .residential, 2),
            lot(0, 2, .commercial, 3),
            lot(1, 0, .park, 0),
            lot(1, 1, .residential, 2),
            lot(1, 2, .office, 2),
        ], time: .zero)
        let new = CitySkyline(lots: [
            lot(0, 0, .residential, 2), // raised
            lot(0, 1, .residential, 2), // the same
            lot(0, 2, .commercial, 2), // lower: drawn as it is
            lot(1, 0, .residential, 1), // built on open ground
            lot(1, 1, .commercial, 2), // rebuilt for another use
            lot(1, 2, .park, 0), // now open ground
            lot(2, 0, .industrial, 1), // a new cell
        ], time: night)
        let growth = try XCTUnwrap(SkylineGrowth(from: old, to: new))
        XCTAssertEqual(growth.count, 4)
        let raised = try XCTUnwrap(growth.rise(row: 0, column: 0))
        XCTAssertEqual(raised.fromDensity, 1)
        XCTAssertFalse(raised.isNew)
        for (row, column) in [(1, 0), (1, 1), (2, 0)] {
            let rise = try XCTUnwrap(growth.rise(row: row, column: column), "\(row), \(column)")
            XCTAssertTrue(rise.isNew)
            XCTAssertEqual(rise.fromDensity, 0)
        }
        for (row, column) in [(0, 1), (0, 2), (1, 2)] {
            XCTAssertNil(growth.rise(row: row, column: column), "\(row), \(column)")
        }
        XCTAssertNil(growth.frame(of: new.lots[1], elapsed: 0.5), "a lot that did not grow is drawn as it is")
    }

    /// A save loaded, an undo or the same moment changes the map at once.
    func testOnlyGrowthTheClockMovedForwardToAFewDaysAtMostIsPlayed() {
        let old = CitySkyline(lots: [lot(0, 0, .residential, 1)], time: night)
        let grown = [lot(0, 0, .residential, 3)]
        XCTAssertNotNil(SkylineGrowth(from: old, to: CitySkyline(lots: grown, time: GameTime(seconds: 2 * GameTime.secondsPerDay))))
        let longest = GameTime(seconds: night.seconds + SkylineGrowth.longestGapDays * GameTime.secondsPerDay)
        XCTAssertNotNil(SkylineGrowth(from: old, to: CitySkyline(lots: grown, time: longest)))
        XCTAssertNil(SkylineGrowth(from: old, to: CitySkyline(lots: grown, time: GameTime(seconds: longest.seconds + 1))))
        XCTAssertNil(SkylineGrowth(from: old, to: CitySkyline(lots: grown, time: night)), "the clock did not move")
        XCTAssertNil(SkylineGrowth(from: old, to: CitySkyline(lots: grown, time: .zero)), "the clock went back")
        XCTAssertNil(SkylineGrowth(from: old, to: CitySkyline(lots: old.lots, time: GameTime(seconds: 2 * GameTime.secondsPerDay))), "nothing grew")
    }

    func testABuildingRisesFromItsOldHeightToItsNewWhileItsLightFades() throws {
        let old = CitySkyline(lots: [lot(0, 0, .residential, 1)], time: .zero)
        let lots = [lot(0, 0, .residential, 4), lot(5, 7, .commercial, 2)]
        let growth = try XCTUnwrap(SkylineGrowth(from: old, to: CitySkyline(lots: lots, time: night)))
        let raised = lots[0], built = lots[1]
        let raisedDelay = try XCTUnwrap(growth.rise(row: 0, column: 0)).delay
        let builtDelay = try XCTUnwrap(growth.rise(row: 5, column: 7)).delay

        let waiting = try XCTUnwrap(growth.frame(of: raised, elapsed: raisedDelay))
        XCTAssertEqual(waiting, SkylineGrowth.Frame(heightShare: CitySkyline.heightShare(density: 1), sideShare: 1, light: 0))
        XCTAssertFalse(try XCTUnwrap(growth.frame(of: built, elapsed: builtDelay)).isShown, "not started: not drawn")

        for (lot, delay) in [(raised, raisedDelay), (built, builtDelay)] {
            let frames = stride(from: 0.05, through: SkylineGrowth.riseDuration, by: 0.05).map {
                growth.frame(of: lot, elapsed: delay + $0)!
            }
            XCTAssertTrue(frames.allSatisfy(\.isShown))
            XCTAssertEqual(frames.map(\.heightShare), frames.map(\.heightShare).sorted(), "rises steadily")
            XCTAssertEqual(frames.map(\.sideShare), frames.map(\.sideShare).sorted())
            XCTAssertEqual(frames.map(\.light), frames.map(\.light).sorted(by: >), "the light fades")
            XCTAssertGreaterThan(frames[0].light, 0.9)
            let done = try XCTUnwrap(growth.frame(of: lot, elapsed: SkylineGrowth.duration))
            XCTAssertEqual(done, SkylineGrowth.Frame(heightShare: CitySkyline.heightShare(density: lot.density), sideShare: 1, light: 0))
        }
        let swelling = try XCTUnwrap(growth.frame(of: built, elapsed: builtDelay + 0.01))
        XCTAssertLessThan(swelling.sideShare, 0.5, "a new building starts small")
        XCTAssertLessThan(swelling.heightShare, 0.05, "and on the ground")
        XCTAssertEqual(try XCTUnwrap(growth.frame(of: raised, elapsed: raisedDelay + 0.01)).sideShare, 1, "a raised one keeps its size")
    }

    /// Neighbours start apart, the same every time, and all are done in
    /// the growth's duration.
    func testBuildingsStartOneAfterAnotherAndAllFinishInTime() throws {
        let lots = (0..<10).flatMap { row in (0..<10).map { lot(row, $0, .residential, 2) } }
        let growth = try XCTUnwrap(SkylineGrowth(from: CitySkyline(lots: [], time: .zero), to: CitySkyline(lots: lots, time: night)))
        let delays = try lots.map { try XCTUnwrap(growth.rise(row: $0.row, column: $0.column)).delay }
        XCTAssertTrue(delays.allSatisfy { (0...SkylineGrowth.longestDelay).contains($0) })
        XCTAssertGreaterThan(Set(delays).count, 50, "spread out, not together")
        XCTAssertGreaterThan(delays.max()! - delays.min()!, SkylineGrowth.longestDelay * 0.8)
        let again = try XCTUnwrap(SkylineGrowth(from: CitySkyline(lots: [], time: .zero), to: CitySkyline(lots: lots, time: night)))
        XCTAssertEqual(try lots.map { try XCTUnwrap(again.rise(row: $0.row, column: $0.column)).delay }, delays)
        XCTAssertEqual(SkylineGrowth.duration, SkylineGrowth.longestDelay + SkylineGrowth.riseDuration)
        for lot in lots {
            XCTAssertEqual(growth.frame(of: lot, elapsed: SkylineGrowth.duration)?.light, 0)
        }
    }

    /// The skyline the map makes from a world keeps the world's time.
    func testASkylineKeepsItsWorldsTime() throws {
        let world = GameWorld.newGame()
        XCTAssertEqual(CitySkyline(world: world).time, world.clock.now)
    }

    /// A new game's first line between two towns: the towns grow at
    /// midnight, and the map has their growth to play.
    func testAFirstLinesTownsGrowOvernightAndTheMapPlaysIt() throws {
        let towns = Land.townCentres(seed: 1, in: GameWorld.newGameBounds)
        var world = try newGameLine(through: [towns[0], towns[1]])
        let evening = CitySkyline(world: world)
        try world.advance(ticks: 1 + 1_440)
        let morning = CitySkyline(world: world)
        let growth = try XCTUnwrap(SkylineGrowth(from: evening, to: morning))
        XCTAssertGreaterThan(growth.count, 0)
        let before = Dictionary(uniqueKeysWithValues: evening.lots.map { ([$0.row, $0.column], $0) })
        for lot in morning.lots {
            guard let rise = growth.rise(row: lot.row, column: lot.column) else { continue }
            let earlier = before[[lot.row, lot.column]]
            if rise.isNew {
                XCTAssertTrue(earlier == nil || earlier!.isOpenGround || earlier!.use != lot.use)
            } else {
                XCTAssertEqual(rise.fromDensity, earlier?.density)
                XCTAssertGreaterThan(lot.density, rise.fromDensity)
            }
        }
    }
}
