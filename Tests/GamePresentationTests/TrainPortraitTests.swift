import Foundation
import GameCore
@testable import GamePresentation
import XCTest

/// TRAIN-IDENTITY: the train types' pictures are the 3D map's own models,
/// and a train goes by one name.
final class TrainPortraitTests: XCTestCase {
    /// Every type the map draws as a model of its own has a picture, wider
    /// than tall, the train filling some of it.
    func testEveryModelledTypeHasAPicture() throws {
        var pictured = 0
        for type in TrainType.allCases {
            let key = TrainPortrait.key(of: type)
            let modelled = Map3DTrainSet.named(key) != nil || Map3DModelPack.styleByType[key] != nil
            let portrait = TrainPortrait.make(key: key, cars: 3)
            guard modelled else {
                XCTAssertNil(portrait, type.spec.code)
                continue
            }
            let picture = try XCTUnwrap(portrait, type.spec.code)
            pictured += 1
            XCTAssertEqual(picture.width, TrainPortrait.pixelWidth, type.spec.code)
            XCTAssertGreaterThan(picture.width, picture.height, type.spec.code)
            XCTAssertEqual(picture.rgba.count, picture.width * picture.height * 4, type.spec.code)
            // Some of the page is the train.
            let opaque = stride(from: 3, to: picture.rgba.count, by: 4).filter { picture.rgba[$0] == 255 }.count
            XCTAssertGreaterThan(opaque, picture.width * picture.height / 10, type.spec.code)
        }
        XCTAssertGreaterThan(pictured, TrainType.allCases.count / 2)
    }

    /// REVIEW-L32: the app asks for one to three cars, and for the trains
    /// with no type by their performance's key; each has a picture
    /// whenever three cars of it do, the same size, the train in it.
    func testEveryKeyTheAppAsksForPaintsAtEveryLength() throws {
        var keys = Set(TrainType.allCases.map { TrainPortrait.key(of: $0) })
        for preset in PerformancePreset.allCases {
            keys.insert(TrainPortrait.key(type: nil, performance: preset.performance))
        }
        for key in keys.sorted() {
            let three = TrainPortrait.make(key: key, cars: 3)
            for cars in 1...2 {
                let portrait = TrainPortrait.make(key: key, cars: cars)
                XCTAssertEqual(portrait == nil, three == nil, "\(key) x\(cars)")
                guard let portrait else { continue }
                XCTAssertEqual(portrait.width, TrainPortrait.pixelWidth, "\(key) x\(cars)")
                XCTAssertGreaterThan(portrait.height, 0, "\(key) x\(cars)")
                XCTAssertEqual(portrait.rgba.count, portrait.width * portrait.height * 4, "\(key) x\(cars)")
                XCTAssertTrue(stride(from: 3, to: portrait.rgba.count, by: 4).contains { portrait.rgba[$0] == 255 }, "\(key) x\(cars)")
            }
        }
    }

    /// Owner's report, 2026-11-24: a train with no type running as the
    /// EMU100 (or the Alishan, steam or Hai-Feng train) is pictured, and
    /// drawn, as that type's own model, not the commuter shell.
    func testAPresetWithAModelIsPicturedAsIt() throws {
        for (code, key) in ["emu100": "EMU100", "forestRailway": "ALISHAN", "steam": "STEAM", "haiFeng": "HAIFENG"] {
            let preset = try XCTUnwrap(PerformancePreset.allCases.first { $0.code == code }, code)
            XCTAssertEqual(TrainPortrait.key(type: nil, performance: preset.performance), key, code)
            XCTAssertNotNil(TrainPortrait.make(key: key, cars: 2), code)
        }
    }

    /// The same picture each time.
    func testThePictureIsTheSameEachTime() throws {
        let a = try XCTUnwrap(TrainPortrait.make(key: "E500CK", cars: 2))
        let b = try XCTUnwrap(TrainPortrait.make(key: "E500CK", cars: 2))
        XCTAssertEqual(a, b)
    }

    /// A train with no type running as the E500 Chu-Kuang is that train,
    /// by one name; its cars' figures say they are the cars'.
    func testOneName() throws {
        let preset = try XCTUnwrap(PerformancePreset.allCases.first { $0.code == "e500ChuKuang" })
        XCTAssertEqual(Train.identityName(type: nil, performance: preset.performance, in: .traditionalChinese), "莒光號（E500 電力機車）")
        XCTAssertEqual(Train.identityName(type: .a, performance: preset.performance, in: .traditionalChinese), "大型捷運")
        let standard = try XCTUnwrap(PerformancePreset.allCases.first { $0.code == "standard" })
        XCTAssertEqual(Train.identityName(type: nil, performance: standard.performance, in: .traditionalChinese), "通用列車")
        XCTAssertEqual(Train.carsFigureText(nil, in: .traditionalChinese), "車廂：每節 320 人 · 4 門")
        XCTAssertEqual(Train.carsFigureText(.a, in: .english), "Cars: 310 a car · 5 doors")
        XCTAssertEqual(preset.performance.figuresText(in: .traditionalChinese), "最高 120 km/h · 加速 1.657 · 減速 2.6 km/h/s")
        XCTAssertFalse(preset.performance.figuresText(in: .traditionalChinese).contains("莒光"))
    }

    /// `TRAIN_PORTRAIT_DIR=<dir>`: each type's picture as a PPM, to look at.
    func testWritePictures() throws {
        guard let dir = ProcessInfo.processInfo.environment["TRAIN_PORTRAIT_DIR"] else { throw XCTSkip("TRAIN_PORTRAIT_DIR not set") }
        var keys = TrainType.allCases.map { TrainPortrait.key(of: $0) }
        keys += ["E500CK", "R100CK", ""]
        for key in keys {
            guard let picture = TrainPortrait.make(key: key, cars: 3) else { continue }
            let w = picture.width, h = picture.height
            var pixels = [UInt32](repeating: 0x2A2F5A, count: w * h)
            for at in pixels.indices {
                let r = UInt32(picture.rgba[at * 4]), g = UInt32(picture.rgba[at * 4 + 1]), b = UInt32(picture.rgba[at * 4 + 2]), a = UInt32(picture.rgba[at * 4 + 3])
                // Premultiplied over the panel's navy.
                pixels[at] = ((r + 0x2A * (255 - a) / 255) << 16) | ((g + 0x2F * (255 - a) / 255) << 8) | (b + 0x5A * (255 - a) / 255)
            }
            var data = Data("P6 \(w) \(h) 255\n".utf8)
            for p in pixels { data.append(contentsOf: [UInt8((p >> 16) & 0xFF), UInt8((p >> 8) & 0xFF), UInt8(p & 0xFF)]) }
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(key.isEmpty ? "standard" : key).ppm"))
        }
    }
}
