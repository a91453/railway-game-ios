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
}
