import GameCore
@testable import GamePresentation
import XCTest

/// Decision 533: the station panel's row for the riders a school or a
/// hospital of the company's brings.
final class CivicRidersTextTests: XCTestCase {
    func testTheRowSaysWhoComesAndWhen() {
        let school = CivicRiders(kind: .school, riders: 1_250)
        XCTAssertEqual(school.text(in: .english), "School · about 1,250 students ride here today, in the morning and home after school")
        XCTAssertEqual(school.text(in: .traditionalChinese), "學校 · 今天約 1,250 名學生搭車來，早上到校、放學回家")
        let hospital = CivicRiders(kind: .hospital, riders: 1)
        XCTAssertEqual(hospital.text(in: .english), "Hospital · about 1 patient or visitor rides here today and home again")
        XCTAssertEqual(hospital.text(in: .traditionalChinese), "醫院 · 今天約 1 位看病、探病的旅客搭車來回")
    }
}
