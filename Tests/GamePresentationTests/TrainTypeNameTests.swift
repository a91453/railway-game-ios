import GameCore
import GamePresentation
import XCTest

/// The names of the train types (ARCHITECTURE decision 171): the ones a
/// player in Taiwan would not recognize, the reference's letters and its sky
/// rail, are named for what they are; the others keep the names they had.
final class TrainTypeNameTests: XCTestCase {
    /// Every type with its name in both languages, as decision 171 lists
    /// them. A new type has to be named here: the test below fails until it
    /// is.
    private static let names: [(type: TrainType, english: String, chinese: String)] = [
        (.a, "Large metro", "大型捷運"),
        (.b, "Medium metro", "中型捷運"),
        (.c, "Light rail", "輕軌"),
        (.l, "Linear-motor metro", "線性馬達捷運"),
        (.d, "Suburban express", "市郊快線"),
        (.apm, "APM", "APM"),
        (.maglev, "Maglev", "磁浮"),
        (.skyRail, "Light monorail", "輕型單軌"),
        (.monorail, "Monorail", "單軌"),
        (.steam, "Steam train", "蒸汽列車"),
        (.highSpeed, "High-speed set", "高鐵列車"),
        (.emu3000, "EMU3000", "EMU3000 新自強號"),
    ]

    func testEveryTypeHasItsName() {
        XCTAssertEqual(Set(Self.names.map(\.type)), Set(TrainType.allCases), "every type is named here, once")
        XCTAssertEqual(Self.names.count, TrainType.allCases.count)
        for entry in Self.names {
            XCTAssertEqual(entry.type.title(in: .english), entry.english, "\(entry.type.rawValue) in English")
            XCTAssertEqual(entry.type.title(in: .traditionalChinese), entry.chinese, "\(entry.type.rawValue) in Chinese")
        }
    }

    func testNoTwoTypesShareAName() {
        for language in DisplayLanguage.allCases {
            let titles = TrainType.allCases.map { $0.title(in: language) }
            XCTAssertEqual(Set(titles).count, titles.count, "\(language): \(titles)")
        }
    }

    /// The point of the decision: a letter on its own tells a player nothing.
    func testTheLettersAndTheSkyRailAreNamedForWhatTheyAre() {
        for type in [TrainType.a, .b, .c, .l, .d] {
            XCTAssertNotEqual(type.title(in: .english), "Type \(type.rawValue)")
            XCTAssertNotEqual(type.title(in: .traditionalChinese), "\(type.rawValue)型")
        }
        XCTAssertNotEqual(TrainType.skyRail.title(in: .traditionalChinese), "雲軌")
    }

    /// The names that were already known stay as they were, so does the
    /// standard car (a train without a type).
    func testTheKnownNamesAndTheStandardCarStay() {
        XCTAssertEqual(Train.typeText(.monorail, in: .traditionalChinese), "單軌 · 每節 224 人 · 2 門")
        XCTAssertEqual(Train.typeText(.maglev, in: .traditionalChinese), "磁浮 · 每節 240 人 · 3 門")
        XCTAssertEqual(Train.typeText(.apm, in: .english), "APM · 138 a car · 2 doors")
        XCTAssertEqual(Train.typeText(nil, in: .traditionalChinese), "標準車 · 每節 320 人 · 4 門")
        XCTAssertEqual(Train.typeText(nil, in: .english), "Standard car · 320 a car · 4 doors")
    }

    /// What the menu, the train's card and the status line read.
    func testTheTypeTextCarriesTheNewName() {
        XCTAssertEqual(Train.typeText(.b, in: .traditionalChinese), "中型捷運 · 每節 260 人 · 4 門")
        XCTAssertEqual(Train.typeText(.b, in: .english), "Medium metro · 260 a car · 4 doors")
        XCTAssertEqual(Train.typeText(.a, in: .traditionalChinese), "大型捷運 · 每節 310 人 · 5 門")
        XCTAssertEqual(Train.typeText(.skyRail, in: .traditionalChinese), "輕型單軌 · 每節 140 人 · 2 門")
    }

    /// The era's message puts the name in a sentence, so it has to read as one.
    func testTheEraMessageReadsWithTheNewNames() {
        XCTAssertEqual(
            GameError.trainTypeUnavailable(.a).playerMessage(in: .traditionalChinese),
            "這個年代還沒有大型捷運列車。"
        )
        XCTAssertEqual(
            GameError.trainTypeUnavailable(.c).playerMessage(in: .english),
            "This era has no Light rail trains."
        )
        XCTAssertEqual(GameError.trainTypeUnavailable(nil).playerMessage(in: .traditionalChinese), "這個年代還沒有標準車。")
    }
}
