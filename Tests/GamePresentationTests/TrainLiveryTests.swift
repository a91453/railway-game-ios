import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// ARCHITECTURE decision 243: each real model's paint and nose, found from
/// a train's type or its performance.
final class TrainLiveryTests: XCTestCase {
    func testATrainTakesItsTypesLiveryElseItsPerformancesElsePlain() {
        XCTAssertEqual(TrainLivery.of(type: .highSpeed, performance: .standard), .highSpeed, "the type first")
        XCTAssertEqual(TrainLivery.of(type: .emu3000, performance: .tiltingPuyuma), .emu3000)
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .tiltingPuyuma), .puyuma)
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .tiltingTaroko.withTopSpeed(120)), .taroko, "whatever its top speed")
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .emu800), .emu800)
        XCTAssertEqual(TrainLivery.of(type: .a, performance: .metroC381), .metroC381, "a type with none takes its performance's")
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .highSpeed), .highSpeed)
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .emu3000), .emu3000)
        XCTAssertEqual(TrainLivery.of(type: nil, performance: .standard), .plain)
        XCTAssertEqual(TrainLivery.of(type: .b, performance: .local), .plain, "a model the table has not")
        XCTAssertEqual(TrainLivery.of(type: nil, performance: TrainPerformance(acceleration: 1_234, braking: 2_345, topSpeed: 100)), .plain)
    }

    func testEveryCodeIsTheCatalogsAndOnlyTheHighSpeedSetIsPointed() {
        let types = Set(TrainType.allCases.map(\.rawValue))
        XCTAssertTrue(Set(TrainLivery.byType.keys).isSubset(of: types))
        let presets = Set(PerformancePreset.allCases.map(\.code))
        XCTAssertTrue(Set(TrainLivery.byPerformance.keys).isSubset(of: presets))
        for type in TrainType.allCases {
            XCTAssertEqual(TrainLivery.of(type: type, performance: .standard).nose == .pointed, type.isHighSpeed, type.rawValue)
        }
        let models = Array(TrainLivery.byType.values) + Array(TrainLivery.byPerformance.values)
        for livery in models {
            XCTAssertNotNil(livery.body)
            XCTAssertNotNil(livery.stripe)
            XCTAssertNotNil(livery.cab)
            XCTAssertEqual(livery.nose == .pointed, livery == .highSpeed)
        }
        XCTAssertEqual(TrainLivery.plain.nose, .round, "as every train's nose was")
        XCTAssertNil(TrainLivery.plain.body)
    }

    /// docs/UI_THEME.md: no model's colour is near the stations' and the
    /// selection's warm yellow or the track's teal (CIE76 at least 30), and
    /// models with the same nose have fronts apart (at least 40).
    func testTheColoursKeepClearOfTheMapsAndOfEachOther() {
        let models: [String: TrainLivery] = [
            "highSpeed": .highSpeed, "emu3000": .emu3000, "puyuma": .puyuma, "taroko": .taroko, "emu800": .emu800, "metroC381": .metroC381,
        ]
        for (name, livery) in models {
            for colour in [livery.body, livery.cab].compactMap(\.self) {
                for reserved in [0xFFC86B, 0x10917F, 0x45D3C0] {
                    XCTAssertGreaterThanOrEqual(Self.difference(colour, reserved), 30, "\(name) \(String(colour, radix: 16)) near \(String(reserved, radix: 16))")
                }
            }
        }
        for (a, b) in [("emu3000", "puyuma"), ("emu3000", "taroko"), ("puyuma", "taroko"), ("emu800", "metroC381")] {
            let first = models[a]!, second = models[b]!
            XCTAssertEqual(first.nose, second.nose)
            XCTAssertGreaterThanOrEqual(Self.difference(first.cab!, second.cab!), 40, "\(a) and \(b)")
        }
    }

    /// A train's run carries its livery.
    func testARunCarriesItsTrainsLivery() throws {
        var world = try makeWorld(width: 8_192, height: 4_096, balance: 100_000_000)
        let track = TestLine(tiles: 7, row: 1)
        try track.build(in: &world)
        let express = try world.purchaseTrain(named: "Puyuma")
        try world.setTrainPerformance(express.id, to: .tiltingPuyuma)
        try world.placeTrain(express.id, at: track.at(1, facingEast: true))
        let set = try world.purchaseTrain(named: "THSR", as: .highSpeed)
        try world.placeTrain(set.id, at: track.at(4, facingEast: true))
        let plain = try world.purchaseTrain(named: "Plain")
        try world.placeTrain(plain.id, at: track.at(6, facingEast: false))
        let liveries = Dictionary(uniqueKeysWithValues: TrainMotion(world: world, time: 0).runs.map { ($0.train, $0.livery) })
        XCTAssertEqual(liveries, [express.id: .puyuma, set.id: .highSpeed, plain.id: .plain])
    }

    /// CIE76: the distance of two sRGB colours in CIELAB (D65).
    static func difference(_ a: Int, _ b: Int) -> Double {
        func lab(_ rgb: Int) -> (Double, Double, Double) {
            let linear = [16, 8, 0].map { shift -> Double in
                let c = Double((rgb >> shift) & 0xFF) / 255
                return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055).power(2.4)
            }
            let x = (0.4124 * linear[0] + 0.3576 * linear[1] + 0.1805 * linear[2]) / 0.95047
            let y = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
            let z = (0.0193 * linear[0] + 0.1192 * linear[1] + 0.9505 * linear[2]) / 1.08883
            func f(_ t: Double) -> Double { t > 216.0 / 24_389 ? t.power(1.0 / 3) : (24_389.0 / 27 * t + 16) / 116 }
            return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
        }
        let p = lab(a), q = lab(b)
        return ((p.0 - q.0) * (p.0 - q.0) + (p.1 - q.1) * (p.1 - q.1) + (p.2 - q.2) * (p.2 - q.2)).squareRoot()
    }
}

private extension Double {
    func power(_ exponent: Double) -> Double { Foundation.pow(self, exponent) }
}
