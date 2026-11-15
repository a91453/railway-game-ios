import Foundation
import GamePresentation

/// The brand the app under test was built with: the same
/// `Resources/GameBrand.json` is in this test bundle (project.yml), so a
/// build with the released game's brand put in (tools/brand) and a neutral
/// one are both checked against their own name.
enum BuiltBrand {
    private final class Token {}

    static let current: GameBrand = {
        guard let url = Bundle(for: Token.self).url(forResource: "GameBrand", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let brand = try? JSONDecoder().decode(GameBrand.self, from: data) else {
            return .neutral
        }
        return brand
    }()
}
