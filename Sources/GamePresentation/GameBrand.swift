import Foundation

/// The game's own name, save file extension, website and mailbox.
///
/// The public repository carries only a neutral brand (``neutral``): the
/// released app's name is kept out of it (the owner, 2026-11-15) and put in
/// at release time. `tools/brand/apply_brand.py` writes the private brand
/// into `RailwayGameApp/Resources/GameBrand.json` (and the Info.plist
/// strings) of a working copy before Xcode builds it; the app reads that
/// file from its bundle. A build without it, a fork's or a Linux test's,
/// is the neutral game, with no website.
public struct GameBrand: Codable, Hashable, Sendable {
    /// The name in English and in Traditional Chinese.
    public var english: String
    public var chinese: String
    /// The file name extension of the game's own save type, without a dot
    /// (``SharedNetwork/fileExtension``; the Info.plist declares it too).
    public var saveExtension: String
    /// The website's host, such as `www.example.com`, or nil when the game
    /// has none: then the settings have no website and no 3D city preview.
    public var website: String?
    /// The mailbox the data credits offer the derived files from (decision
    /// 503), or nil: then they name the developer instead.
    public var contactEmail: String?

    public init(english: String, chinese: String, saveExtension: String, website: String? = nil, contactEmail: String? = nil) {
        self.english = english
        self.chinese = chinese
        self.saveExtension = saveExtension
        self.website = website
        self.contactEmail = contactEmail
    }

    /// The brand of a build the private brand was not put into.
    public static let neutral = GameBrand(english: "Railway Game", chinese: "鐵道遊戲", saveExtension: "railwaygame")

    /// The brand of this build: `GameBrand.json` in the app's bundle, or
    /// ``neutral`` when there is none or it cannot be read.
    public static let current: GameBrand = {
        guard let url = Bundle.main.url(forResource: "GameBrand", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let brand = try? JSONDecoder().decode(GameBrand.self, from: data),
              brand.isValid else {
            return .neutral
        }
        return brand
    }()

    /// The name in `language`.
    public func name(in language: DisplayLanguage) -> String {
        language.text(english, chinese)
    }

    /// The website's home page, or nil.
    public var home: String? {
        website.map { "https://\($0)/" }
    }

    /// The website as the settings name it: its host without `www.`.
    public var websiteName: String? {
        website.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }

    /// Whether every field is usable: names, an extension of letters and
    /// digits, and a host with no scheme or path.
    public var isValid: Bool {
        !english.isEmpty && !chinese.isEmpty && !saveExtension.isEmpty
            && saveExtension.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
            && (website.map { !$0.isEmpty && !$0.contains("/") && !$0.contains(":") } ?? true)
            && (contactEmail.map { $0.contains("@") } ?? true)
    }
}
