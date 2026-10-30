import Foundation
@testable import GamePresentation
import XCTest

/// Decision 503: the data sources screen never leads a player to the game's
/// own GitHub project, in either language.
final class DataSourceCreditsNoRepoLinkTests: XCTestCase {
    private let languages: [DisplayLanguage] = [.english, .traditionalChinese]

    func testNoLinkOrTextPointsToTheGameRepository() {
        for language in languages {
            for section in DataSourceCredits.sections(in: language) {
                for credit in section.credits {
                    let texts = [section.title, credit.title, credit.detail, credit.notice]
                        + credit.links.flatMap { [$0.title, $0.url] }
                    for text in texts {
                        XCTAssertFalse(text.lowercased().contains("github.com/a91453"), "\(credit.id): \(text)")
                        XCTAssertFalse(text.contains("原始碼儲存庫"), "\(credit.id): \(text)")
                        XCTAssertFalse(text.lowercased().contains("source repository"), "\(credit.id): \(text)")
                        XCTAssertFalse(text.lowercased().contains("public repository"), "\(credit.id): \(text)")
                    }
                }
            }
        }
    }

    func testDerivedDataOfferNamesTheMailbox() {
        for language in languages {
            let odbl = DataSourceCredits.sections(in: language).flatMap(\.credits)
                .filter { $0.notice.contains("ODbL") && $0.notice.contains("hello@alongthelinegame.com") }
            XCTAssertGreaterThanOrEqual(odbl.count, 3, "OSM, Overture and the base map each offer the files")
        }
    }
}
