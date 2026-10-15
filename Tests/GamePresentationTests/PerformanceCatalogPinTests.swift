import GameCore
@testable import GamePresentation
import XCTest

/// Decision 236: every performance preset as it was before the presets moved
/// from `switch`es to the built-in table. This file was written against the
/// `enum` and is not to change when the table changes how the presets are
/// kept: a value moved here is a behaviour change.
final class PerformanceCatalogPinTests: XCTestCase {
    /// One preset as it was: its names, and how it accelerates, brakes,
    /// coasts and how fast it runs.
    private struct Pinned {
        let english: String
        let chinese: String
        let acceleration: Int64
        let braking: Int64
        let topSpeed: Int64
        var alternativeAcceleration: Int64? = nil
        var alternativeBraking: Int64? = nil
        var coast: (deceleration: Int64, speedRatio: Int64)? = nil

        var performance: TrainPerformance {
            TrainPerformance(
                acceleration: acceleration, braking: braking, topSpeed: topSpeed,
                alternativeAcceleration: alternativeAcceleration, alternativeBraking: alternativeBraking,
                coast: coast.map { TrainPerformance.Coast(deceleration: $0.deceleration, speedRatio: $0.speedRatio) }
            )
        }
    }

    private static let pinned: [Pinned] = [
        .init(english: "Standard", chinese: "標準", acceleration: 1500, braking: 2500, topSpeed: 110),
        .init(english: "Metro", chinese: "捷運", acceleration: 3960, braking: 4680, topSpeed: 80),
        .init(english: "Local EMU", chinese: "區間車", acceleration: 2500, braking: 3000, topSpeed: 120),
        .init(english: "Ordinary", chinese: "普快車", acceleration: 1300, braking: 2400, topSpeed: 100),
        .init(english: "Chu-Kuang / Fu-Hsing", chinese: "莒光／復興", acceleration: 1500, braking: 2600, topSpeed: 120),
        .init(english: "Tze-Chiang", chinese: "自強", acceleration: 1800, braking: 2900, topSpeed: 130),
        .init(english: "EMU3000", chinese: "EMU3000", acceleration: 2520, braking: 3600, topSpeed: 135),
        .init(english: "Push-pull Tze-Chiang", chinese: "推拉式自強", acceleration: 1600, braking: 2800, topSpeed: 130),
        .init(english: "Taroko", chinese: "太魯閣", acceleration: 1880, braking: 3600, topSpeed: 135),
        .init(english: "Puyuma", chinese: "普悠瑪", acceleration: 1840, braking: 3600, topSpeed: 135),
        .init(english: "Diesel Tze-Chiang", chinese: "柴聯自強", acceleration: 1500, braking: 2448, topSpeed: 110),
        .init(english: "DR1000 railcar", chinese: "DR1000", acceleration: 1500, braking: 2448, topSpeed: 110),
        .init(english: "Alishan Forest Railway", chinese: "阿里山林鐵", acceleration: 700, braking: 1100, topSpeed: 45),
        .init(
            english: "High-speed rail", chinese: "高鐵", acceleration: 1400, braking: 1500, topSpeed: 300,
            alternativeAcceleration: 2000, alternativeBraking: 2700, coast: (deceleration: 450, speedRatio: 450)
        ),
        .init(english: "Steam train", chinese: "蒸汽列車", acceleration: 400, braking: 1200, topSpeed: 40),
    ]

    func testEveryPresetKeepsItsNamesAndNumbersInItsOrder() {
        // Decision 237 added rows after these: the first fifteen stay as
        // they were.
        XCTAssertGreaterThanOrEqual(PerformancePreset.allCases.count, Self.pinned.count)
        for (preset, pin) in zip(PerformancePreset.allCases, Self.pinned) {
            XCTAssertEqual(preset.title(in: .english), pin.english)
            XCTAssertEqual(preset.title(in: .traditionalChinese), pin.chinese, pin.english)
            XCTAssertEqual(preset.performance, pin.performance, pin.english)
        }
    }

    /// GameCore's presets keep their numbers too: the menu's are the same
    /// values, and the train types' own performances point at three of them.
    func testGameCoresPresetsKeepTheirNumbers() {
        let byName = Dictionary(uniqueKeysWithValues: Self.pinned.map { ($0.english, $0.performance) })
        XCTAssertEqual(TrainPerformance.standard, byName["Standard"])
        XCTAssertEqual(TrainPerformance.metro, byName["Metro"])
        XCTAssertEqual(TrainPerformance.local, byName["Local EMU"])
        XCTAssertEqual(TrainPerformance.ordinary, byName["Ordinary"])
        XCTAssertEqual(TrainPerformance.semiExpress, byName["Chu-Kuang / Fu-Hsing"])
        XCTAssertEqual(TrainPerformance.express, byName["Tze-Chiang"])
        XCTAssertEqual(TrainPerformance.emu3000, byName["EMU3000"])
        XCTAssertEqual(TrainPerformance.pushPull, byName["Push-pull Tze-Chiang"])
        XCTAssertEqual(TrainPerformance.tiltingTaroko, byName["Taroko"])
        XCTAssertEqual(TrainPerformance.tiltingPuyuma, byName["Puyuma"])
        XCTAssertEqual(TrainPerformance.dieselExpress, byName["Diesel Tze-Chiang"])
        XCTAssertEqual(TrainPerformance.dieselRailcar, byName["DR1000 railcar"])
        XCTAssertEqual(TrainPerformance.forestRailway, byName["Alishan Forest Railway"])
        XCTAssertEqual(TrainPerformance.highSpeed, byName["High-speed rail"])
        XCTAssertEqual(TrainPerformance.steam, byName["Steam train"])
    }

    /// Which preset a performance reads as: the first in the order that
    /// accelerates, brakes and coasts as it does, whatever its top speed.
    func testAPerformanceReadsAsTheSamePreset() {
        for pin in Self.pinned {
            for speed in [pin.topSpeed, 60, 200] {
                let found = PerformancePreset(matching: pin.performance.withTopSpeed(speed))
                // The diesel railcar runs as the diesel express does, which
                // comes first.
                let expected = pin.english == "DR1000 railcar" ? "Diesel Tze-Chiang" : pin.english
                XCTAssertEqual(found?.title(in: .english), expected, "\(pin.english) at \(speed)")
            }
        }
        XCTAssertNil(PerformancePreset(matching: TrainPerformance(acceleration: 1, braking: 2, topSpeed: 10)))
    }

    func testTheTextsOfEveryPreset() {
        XCTAssertEqual(TrainPerformance.standard.displayText(in: .english), "Standard · 110 km/h · 1.5 / 2.5 km/h/s")
        XCTAssertEqual(TrainPerformance.metro.displayText(in: .traditionalChinese), "捷運 · 80 km/h · 3.96 / 4.68 km/h/s")
        XCTAssertEqual(TrainPerformance.highSpeed.displayText(in: .traditionalChinese), "高鐵 · 300 km/h · 1.4 / 1.5 km/h/s")
        XCTAssertEqual(TrainPerformance.dieselRailcar.displayText(in: .english), "Diesel Tze-Chiang · 110 km/h · 1.5 / 2.448 km/h/s")
        XCTAssertEqual(TrainPerformance(acceleration: 1, braking: 2, topSpeed: 10).displayText(in: .traditionalChinese), "自訂 · 10 km/h · 0.001 / 0.002 km/h/s")
        XCTAssertEqual(PerformancePreset.designSpeeds, [60, 80, 90, 100, 120, 140, 150, 160, 180, 200])
    }
}
