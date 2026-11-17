import XCTest
@testable import GamePresentation

/// CAR-GAP (decision 399, later): two cars of a train stand their models'
/// own gap apart, some half a metre to 0.7 m as on the real trains, not
/// that and ``Map3DTrains/carGap`` more. The owner, 2026-11-18, on the
/// real timetables' trains: 「台鐵的列車縫隙 怎麼比高鐵還大」 (an EMU's 1.3 m
/// beside the High Speed Rail's 1.0 m).
final class CarGapTests: XCTestCase {
    let pack = Map3DModelPack.standard

    /// Where a model's side walls end along it, from its minimum: the
    /// shell's corners at the body's height, not its couplers or bellows.
    func body(_ model: Map3DModelPack.Model) -> ClosedRange<Float> {
        var low = Float.infinity, high = -Float.infinity
        for v in model.vertices where v.z > 1.0 && v.z < 3.5 && abs(v.y) >= 1.2 {
            low = min(low, v.x)
            high = max(high, v.x)
        }
        return (low - model.minimum.x)...(high - model.minimum.x)
    }

    /// The gaps, metres, between the bodies of a `cars`-car train of `key`
    /// as ``Map3DRealTrains`` lays it, front to back.
    func realGaps(_ key: String, cars: Int) throws -> [Float] {
        let formation = Map3DRealTrains.Formation(key: key, cars: cars)
        let length = Float(Map3DRealTrains.carLength(of: formation, hasModels: true, models: pack) * 1_000)
        let pitch = Float(Map3DRealTrains.carPitch * 1_000)
        var spans: [ClosedRange<Float>] = []
        for car in 0..<cars {
            let index = try XCTUnwrap(pack.modelIndex(forType: key, carIndex: car, count: cars), key)
            let model = pack.models[index], stretch = length / model.length
            let front = -Float(car) * pitch, back = front - length
            let shell = body(model)
            // Its minimum at the back, or turned round at the front.
            let ends = pack.isTurned(forType: key, carIndex: car, count: cars)
                ? [front - shell.lowerBound * stretch, front - shell.upperBound * stretch]
                : [back + shell.lowerBound * stretch, back + shell.upperBound * stretch]
            spans.append(ends.min()!...ends.max()!)
        }
        return zip(spans, spans.dropFirst()).map { $0.0.lowerBound - $0.1.upperBound }
    }

    func testTheRealTrainsCarsStandTheirOwnGapApart() throws {
        let highSpeed = try realGaps("highSpeed", cars: 12)
        for gap in highSpeed { XCTAssertEqual(gap, 0.4, accuracy: 0.15, "highSpeed") }
        // Taiwan Railway's stock on its lines (Map3DRealTrains.formation).
        // Its multiple units' gaps are a gangway's, as the High Speed
        // Rail's but a little wider (the EMU3000's some 0.7 m, was 1.3 m).
        for (key, cars) in [("emu800", 8), ("emu900", 10), ("emu500", 8), ("emu700", 8), ("emu3000", 12), ("puyuma", 8), ("taroko", 8),
                            ("dieselExpress", 3)] {
            for gap in try realGaps(key, cars: cars) {
                XCTAssertTrue((0.05...0.75).contains(gap), "\(key): \(gap) m between two cars")
                XCTAssertLessThanOrEqual(gap, (highSpeed.max() ?? 0) + 0.4, "\(key): no wider than the High Speed Rail's but a little")
            }
        }
        // Its coaches behind a locomotive have buffers and couplers between
        // their end walls, a little wider still.
        for (key, cars) in [("pushPull", 14), ("E200CK", 9)] {
            for gap in try realGaps(key, cars: cars) { XCTAssertTrue((0.05...0.9).contains(gap), "\(key): \(gap) m between two cars") }
        }
    }

    /// The player's trains too: a set whose models reach their couplers is
    /// laid end to end; boxes and the style cars keep the gap.
    func testCarsReachingTheirCouplersTouch() {
        for key in ["emu800", "emu3000", "highSpeed", "puyuma", "E200CK", "MINGRI", "pushPull"] {
            XCTAssertTrue(pack.touches(forType: key, count: 6), key)
        }
        for key in ["EMU100", "greenTram", "metroGeneric"] {
            XCTAssertFalse(pack.touches(forType: key, count: 6), key)
        }
        XCTAssertEqual(Map3DRealTrains.carLength(of: .init(key: "emu800", cars: 8), hasModels: false, models: pack), Map3DRealTrains.carLength)
    }
}
