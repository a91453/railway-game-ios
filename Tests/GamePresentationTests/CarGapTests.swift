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
        let laid = Map3DRealTrains.cars(of: formation, hasModels: true, models: pack).cars
        var spans: [ClosedRange<Float>] = []
        for (car, slot) in laid.enumerated() {
            let index = try XCTUnwrap(slot.model ?? pack.modelIndex(forType: key, carIndex: car, count: cars), key)
            let length = Float(slot.length * 1_000)
            let model = pack.models[index], stretch = length / model.length
            let front = -Float(slot.start * 1_000), back = front - length
            let shell = body(model)
            // Its minimum at the back, or turned round at the front.
            let ends = pack.isTurned(forType: key, carIndex: car, count: laid.count)
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
        // Decision 930: the EMU100 has its own cars, which reach their
        // couplers (it borrowed the commuter shell, which keeps the gap).
        for key in ["emu800", "emu3000", "highSpeed", "puyuma", "E200CK", "MINGRI", "pushPull", "EMU100"] {
            XCTAssertTrue(pack.touches(forType: key, count: 6), key)
        }
        for key in ["greenTram", "metroGeneric"] {
            XCTAssertFalse(pack.touches(forType: key, count: 6), key)
        }
        XCTAssertEqual(Map3DRealTrains.carLength(of: .init(key: "emu800", cars: 8), hasModels: false, models: pack), Map3DRealTrains.carLength)
    }

    /// REAL-CAR-LENGTH (decision 399, later): a real timetable's train is
    /// as long as its models make it, each car its own length, not a car
    /// each 20 m: before, a 12-car 700T was 240 m (its 25.5 m cars
    /// squeezed) and a Wenhu line train 80 m (its 13.8 m cars stretched,
    /// the gap between them with them).
    func testTheRealTrainsCarsAreTheirOwnLength() throws {
        func whole(_ key: String, _ cars: Int) -> Double {
            Map3DRealTrains.cars(of: .init(key: key, cars: cars), hasModels: true, models: pack).length * 1_000
        }
        XCTAssertEqual(whole("highSpeed", 12), 305.3, accuracy: 1)
        XCTAssertEqual(whole("metroC381", 6), 142.2, accuracy: 1)
        // Decision 906: the studio's Taroko at the real car lengths (21.995 m and 20.5 m).
        XCTAssertEqual(whole("taroko", 8), 167.0, accuracy: 1)
        XCTAssertEqual(whole("emu3000", 12), 245.7, accuracy: 1)
        for key in [Map3DTrainSet.wenhu370Key, Map3DTrainSet.wenhuVAL256Key] {
            XCTAssertEqual(whole(key, 4), 55.1, accuracy: 0.5, key)
            // The models' own gap, no longer stretched with the car.
            for gap in try realGaps(key, cars: 4) { XCTAssertLessThan(gap, 1.5, "\(key): \(gap) m between two cars") }
        }
        // Each car where the one before it ends.
        let laid = Map3DRealTrains.cars(of: .init(key: "highSpeed", cars: 12), hasModels: true, models: pack).cars
        XCTAssertEqual(laid.count, 12)
        for (car, next) in zip(laid, laid.dropFirst()) { XCTAssertEqual(next.start, car.start + car.length, accuracy: 1e-9) }
        // Boxes, and a set not drawn at its own lengths, a car each 20 m.
        XCTAssertEqual(Map3DRealTrains.cars(of: .init(key: "highSpeed", cars: 12), hasModels: false, models: pack).length, 0.24, accuracy: 1e-9)
        XCTAssertEqual(Map3DRealTrains.cars(of: .init(key: "metroGeneric", cars: 6), hasModels: true, models: pack).length, 0.12, accuracy: 1e-9)
    }
}
