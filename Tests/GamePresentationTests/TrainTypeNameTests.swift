import Foundation
import GameCore
import GamePresentation
import XCTest

/// The names of the train types (ARCHITECTURE decision 171), as the author
/// named them for players in Taiwan: the metros are "…捷運", the other trains
/// "…列車", and no letter or brand stands for a name.
final class TrainTypeNameTests: XCTestCase {
    /// Every type with its name in both languages, as decision 171 lists
    /// them. A new type has to be named here: the test below fails until it
    /// is.
    private static let names: [(type: TrainType, english: String, chinese: String)] = [
        (.a, "Large metro", "大型捷運"),
        (.b, "Medium metro", "中型捷運"),
        (.c, "Light metro", "輕型捷運"),
        (.l, "Linear-motor metro", "線性馬達捷運"),
        (.d, "Multi-door metro", "多門捷運"),
        (.apm, "Automated shuttle", "自動接駁列車"),
        (.maglev, "Maglev train", "磁浮列車"),
        (.skyRail, "Light monorail", "輕型單軌"),
        (.monorail, "Monorail train", "單軌列車"),
        (.steam, "Steam train", "蒸汽列車"),
        (.highSpeed, "High-speed set", "高鐵列車"),
        (.emu3000, "New Tze-Chiang", "新自強號"),
        (.emu100, "EMU100 Tze-Chiang", "EMU100 自強號"),
        (.e200ChuKuang, "Chu-Kuang, E200 locomotive", "莒光號（E200 電力機車）"),
        (.e500ChuKuang, "Chu-Kuang, E500 locomotive", "莒光號（E500 電力機車）"),
        (.r100ChuKuang, "Chu-Kuang, R100 diesel", "莒光號（R100 柴電機車）"),
        (.r200ChuKuang, "Chu-Kuang, R200 diesel", "莒光號（R200 柴電機車）"),
        (.haiFeng, "Hai-Feng sightseeing train", "海風號"),
        (.blueTrain, "Blue Train sightseeing train", "藍皮解憂號"),
        (.shanLan, "Shan-Lan sightseeing train", "山嵐號"),
        (.mingRi, "Ming-Ri sightseeing train", "鳴日號"),
        (.formosaStar, "Formosa Star sightseeing train", "環島之星"),
    ]

    func testEveryTypeHasItsName() {
        XCTAssertEqual(Set(Self.names.map(\.type)), Set(TrainType.allCases), "every type is named here, once")
        XCTAssertEqual(Self.names.count, TrainType.allCases.count)
        for entry in Self.names {
            XCTAssertEqual(entry.type.title(in: .english), entry.english, "\(entry.type.rawValue) in English")
            XCTAssertEqual(entry.type.title(in: .traditionalChinese), entry.chinese, "\(entry.type.rawValue) in Chinese")
        }
    }

    /// The car a train without a type has is named too, and no type shares
    /// its name.
    func testNoTwoTypesShareAName() {
        for language in DisplayLanguage.allCases {
            let titles = TrainType.allCases.map { $0.title(in: language) } + [Train.standardCarName(in: language)]
            XCTAssertEqual(Set(titles).count, titles.count, "\(language): \(titles)")
        }
    }

    /// The point of the decision: a letter or a brand on its own tells a
    /// player nothing.
    func testNoLetterOrBrandStandsForAName() {
        for type in [TrainType.a, .b, .c, .l, .d] {
            XCTAssertNotEqual(type.title(in: .english), "Type \(type.rawValue)")
            XCTAssertNotEqual(type.title(in: .traditionalChinese), "\(type.rawValue)型")
        }
        XCTAssertNotEqual(TrainType.apm.title(in: .english), "APM")
        XCTAssertNotEqual(TrainType.apm.title(in: .traditionalChinese), "APM")
        XCTAssertNotEqual(TrainType.skyRail.title(in: .traditionalChinese), "雲軌")
    }

    /// The scheme: the metros end in 捷運, the trains of the other systems in
    /// 列車.
    func testTheMetrosAreNamedMetroAndTheOtherTrainsTrain() {
        for type in [TrainType.a, .b, .c, .l, .d] {
            XCTAssertTrue(type.title(in: .traditionalChinese).hasSuffix("捷運"), type.rawValue)
            XCTAssertTrue(type.title(in: .english).lowercased().hasSuffix("metro"), type.rawValue)
        }
        for type in [TrainType.apm, .maglev, .monorail, .steam, .highSpeed] {
            XCTAssertTrue(type.title(in: .traditionalChinese).hasSuffix("列車"), type.rawValue)
        }
        XCTAssertTrue(Train.standardCarName(in: .traditionalChinese).hasSuffix("列車"))
    }

    /// A train without a type, which every old save has, is the general train.
    func testTheStandardCarIsTheGeneralTrain() {
        XCTAssertEqual(Train.standardCarName(in: .traditionalChinese), "通用列車")
        XCTAssertEqual(Train.standardCarName(in: .english), "General train")
        XCTAssertEqual(Train.typeText(nil, in: .traditionalChinese), "通用列車 · 每節 320 人 · 4 門")
        XCTAssertEqual(Train.typeText(nil, in: .english), "General train · 320 a car · 4 doors")
    }

    /// What the menu, the train's card and the status line read.
    func testTheTypeTextCarriesTheName() {
        XCTAssertEqual(Train.typeText(.a, in: .traditionalChinese), "大型捷運 · 每節 310 人 · 5 門")
        XCTAssertEqual(Train.typeText(.b, in: .english), "Medium metro · 260 a car · 4 doors")
        XCTAssertEqual(Train.typeText(.d, in: .traditionalChinese), "多門捷運 · 每節 230 人 · 5 門")
        XCTAssertEqual(Train.typeText(.apm, in: .traditionalChinese), "自動接駁列車 · 每節 138 人 · 2 門")
        XCTAssertEqual(Train.typeText(.monorail, in: .traditionalChinese), "單軌列車 · 每節 224 人 · 2 門")
        XCTAssertEqual(Train.typeText(.skyRail, in: .traditionalChinese), "輕型單軌 · 每節 140 人 · 2 門")
        XCTAssertEqual(Train.typeText(.emu3000, in: .traditionalChinese), "新自強號 · 每節 45 人 · 2 門")
        XCTAssertEqual(Train.typeText(.emu3000, in: .english), "New Tze-Chiang · 45 a car · 2 doors")
    }

    /// The era's message puts the name in a sentence of its own, so a name
    /// that ends in 列車 is not followed by another.
    func testTheEraMessageReadsWithTheNames() {
        XCTAssertEqual(GameError.trainTypeUnavailable(.maglev).playerMessage(in: .traditionalChinese), "這個年代還沒有磁浮列車。")
        XCTAssertEqual(GameError.trainTypeUnavailable(.a).playerMessage(in: .traditionalChinese), "這個年代還沒有大型捷運。")
        XCTAssertEqual(GameError.trainTypeUnavailable(.highSpeed).playerMessage(in: .traditionalChinese), "這個年代還沒有高鐵列車。")
        XCTAssertEqual(GameError.trainTypeUnavailable(nil).playerMessage(in: .traditionalChinese), "這個年代還沒有通用列車。")
        XCTAssertEqual(
            GameError.trainTypeUnavailable(.c).playerMessage(in: .english),
            "Light metro is not available in this era."
        )
        XCTAssertEqual(
            GameError.trainTypeUnavailable(nil).playerMessage(in: .english),
            "General train is not available in this era."
        )
    }

    /// What a save, a golden scenario or a replay stores for a train's type is
    /// its code, never its name: the names changed, the codes did not. A save
    /// written before the names changed still reads, every code to the type
    /// it was.
    func testTheCodesTheSavesStoreDidNotMove() throws {
        let codes = ["A", "B", "C", "L", "D", "APM", "MAGLEV", "SKYRAIL", "MONORAIL", "STEAM", "HSR", "EMU3000", "EMU100", "E200CK", "E500CK", "R100CK", "R200CK", "HAIFENG", "BLUE", "SHANLAN", "MINGRI", "STAR"]
        XCTAssertEqual(TrainType.allCases.map(\.rawValue), codes)
        for type in TrainType.allCases {
            let data = try JSONEncoder().encode([type])
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"\(type.rawValue)\"]")
            XCTAssertEqual(try JSONDecoder().decode([TrainType].self, from: data), [type])
        }
        let before = Data("[\(codes.map { "\"\($0)\"" }.joined(separator: ","))]".utf8)
        XCTAssertEqual(try JSONDecoder().decode([TrainType].self, from: before), TrainType.allCases)
    }

    /// A whole save with a train of every type the menu offers, and one of
    /// standard cars: written and read back, each train is the type it was,
    /// and the text the screen shows for it is built from the new name.
    func testASaveWithEveryTypeLoadsBackAndIsShownByTheNewNames() throws {
        var world = try makeWorld(balance: 100_000_000)
        let types: [TrainType?] = [nil] + world.offeredTrainTypes.map { Optional($0) }
        var trains: [(id: TrainID, type: TrainType?)] = []
        for type in types {
            let id = try world.purchaseTrain(named: "T\(trains.count)").id
            try world.setTrainType(id, to: type)
            trains.append((id, type))
        }
        let data = try JSONEncoder().encode(SavedGame(world: world))
        let loaded = try JSONDecoder().decode(SavedGame.self, from: data).world
        XCTAssertEqual(loaded, world)
        XCTAssertEqual(trains.count, TrainType.offered.count + 1)
        for entry in trains {
            let train = try XCTUnwrap(loaded.train(id: entry.id))
            XCTAssertEqual(train.type, entry.type)
            for language in DisplayLanguage.allCases {
                let name = entry.type?.title(in: language) ?? Train.standardCarName(in: language)
                XCTAssertTrue(train.typeText(in: language).hasPrefix(name), "\(entry.type?.rawValue ?? "standard") in \(language)")
            }
        }
    }

    /// The type menu chooses by type, not by its text: every type it offers
    /// can be chosen, and the status line then reads the new name.
    @MainActor
    func testTheMenuChoosesEveryOfferedTypeAndTheStatusLineNamesIt() throws {
        var world = try makeWorld(balance: 100_000_000)
        let id = try world.purchaseTrain(named: "Menu").id
        let session = GameSession(world: world, language: .traditionalChinese)
        session.selectTrain(id)
        for type in session.world.offeredTrainTypes {
            session.setSelectedTrainType(type)
            XCTAssertEqual(session.world.train(id: id)?.type, type, type.rawValue)
            XCTAssertEqual(session.message?.kind, .success, type.rawValue)
            XCTAssertTrue(session.message?.text.contains(type.title(in: .traditionalChinese)) ?? false, type.rawValue)
        }
        session.setSelectedTrainType(nil)
        XCTAssertNil(session.world.train(id: id)?.type)
        XCTAssertTrue(session.message?.text.contains("通用列車") ?? false)
    }
}
