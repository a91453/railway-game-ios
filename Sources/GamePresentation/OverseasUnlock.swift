import Foundation

// Decision 1010: the overseas maps unlock, the game's one purchase. Taiwan
// is free for ever; one non-consumable in-app purchase opens new games on
// every map outside Taiwan (Japan, Hong Kong, Finland), today's and later
// ones. A game already saved on one of those maps plays on without it, and
// a player who downloaded the game while it was free (0.7.x) has it as a
// gift, read from the App Store's record of the first version they
// downloaded (`AppTransaction.originalAppVersion`). It is not game state:
// no save, golden value or replay moves. The App Store side (StoreKit) is
// the app's, `RailwayGameApp/App/OverseasStore.swift`; this is the rule it
// hands its answers to, here so a Linux test can check it.

/// The overseas maps unlock: its product, who has it and what the map
/// picker and the settings say about it.
public enum OverseasUnlock {
    /// The product's identifier in App Store Connect (non-consumable).
    public static let productID = "overseas_maps"

    /// The first build (`CFBundleVersion`, ``testflight-preflight.sh``'s
    /// run number) that sells the unlock: a player whose first download
    /// was an earlier build downloaded a free version, where every map was
    /// open, and keeps them all as a gift. Set to one more than the last
    /// build uploaded before this rule reached `main`, so every 0.7.x
    /// build is below it and every build with the lock is not.
    public static let firstLockedBuild = 150

    /// Where the App Store's answer comes from (`AppTransaction.environment`).
    public enum StoreEnvironment: Sendable {
        /// The App Store itself: what a player's copy says.
        case production
        /// TestFlight and the sandbox, where `originalAppVersion` is always
        /// "1.0" and says nothing about when the tester first came.
        case sandbox
        /// Xcode's own StoreKit testing.
        case xcode
    }

    /// Whether `originalVersion` (`AppTransaction.originalAppVersion`: on
    /// iOS the `CFBundleVersion` first downloaded, "148" or, for a re-run
    /// of the release, "148.2") is a build from before ``firstLockedBuild``.
    /// Only the App Store's own answer counts: the sandbox's is always
    /// "1.0". A version that is not a build number is not a gift.
    public static func isFreeVersionPlayer(originalVersion: String, environment: StoreEnvironment, firstLockedBuild: Int = firstLockedBuild) -> Bool {
        guard environment == .production, let build = buildNumber(originalVersion) else { return false }
        return build < firstLockedBuild
    }

    /// The whole number at the front of a build number ("148" of "148.2"),
    /// or `nil` when it does not start with one.
    static func buildNumber(_ version: String) -> Int? {
        let trimmed = version.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.split(separator: ".", omittingEmptySubsequences: false).first,
              !first.isEmpty, first.allSatisfy(\.isASCII), first.allSatisfy(\.isNumber) else { return nil }
        return Int(first)
    }

    /// What the device knows of the unlock: from the App Store when it
    /// answered, from the device's last answer until then.
    public struct State: Equatable, Sendable {
        /// The unlock was bought (or restored, or shared by the family).
        public var purchased: Bool
        /// The player first downloaded a free version (``isFreeVersionPlayer(originalVersion:environment:firstLockedBuild:)``).
        public var freeVersionPlayer: Bool
        /// Its price as the App Store shows it in the player's country
        /// (`Product.displayPrice`), `nil` until the App Store answers.
        public var price: String?

        public init(purchased: Bool = false, freeVersionPlayer: Bool = false, price: String? = nil) {
            self.purchased = purchased
            self.freeVersionPlayer = freeVersionPlayer
            self.price = price
        }

        /// Whether new games can start on the overseas maps.
        public var isOpen: Bool { purchased || freeVersionPlayer }

        /// Every map open: a game run with no App Store (the Linux tests,
        /// the headless game, a Debug build).
        public static let open = State(purchased: true)

        /// Nothing bought and no gift.
        public static let locked = State()
    }

    // MARK: - Text

    /// The product's name, as the map picker and the settings call it.
    public static func title(in language: DisplayLanguage) -> String {
        language.text("Unlock Overseas Maps", "海外地圖全解鎖")
    }

    /// What it opens, under its name.
    public static func summary(in language: DisplayLanguage) -> String {
        language.text(
            "One purchase opens new games on every map outside Taiwan: Japan, Hong Kong, Finland and the ones still to come. Taiwan stays free. Games you already saved there keep playing either way.",
            "買一次，台灣以外的地圖都能開新局：日本、香港、芬蘭，以及之後新增的。台灣永遠免費。已經存檔的海外遊戲不買也能繼續玩。"
        )
    }

    /// Why an overseas map's row is closed until the unlock is bought.
    public static func lockedText(in language: DisplayLanguage) -> String {
        language.text(
            "Buy Unlock Overseas Maps, at the top of this list, to start a new game here.",
            "購買本頁上方的「海外地圖全解鎖」後，就能在這裡開新局。"
        )
    }

    /// What the player is told when a new game there is refused.
    public static func refusedText(in language: DisplayLanguage) -> String {
        language.text(
            "New games outside Taiwan need Unlock Overseas Maps.",
            "在台灣以外開新局，需要「海外地圖全解鎖」。"
        )
    }

    /// The buy button: with its price once the App Store answered.
    public static func buyTitle(price: String?, in language: DisplayLanguage) -> String {
        guard let price else { return language.text("Buy", "購買") }
        return language.text("Buy · \(price)", "購買 · \(price)")
    }

    /// The restore button.
    public static func restoreTitle(in language: DisplayLanguage) -> String {
        language.text("Restore Purchases", "恢復購買")
    }

    /// The settings' line once it is open, saying why.
    public static func openText(_ state: State, in language: DisplayLanguage) -> String {
        if state.purchased { return language.text("Unlocked. Thank you!", "已解鎖，謝謝支持！") }
        return language.text(
            "Unlocked as a gift: you downloaded the game while it was free.",
            "已解鎖：你在免費版時就下載了遊戲，送你完整版。"
        )
    }

    /// What a finished purchase or restore says.
    public enum Outcome: Equatable, Sendable {
        case bought
        case restored
        /// Restore found nothing bought with this Apple Account.
        case nothingToRestore
        /// Waiting for someone's approval (Ask to Buy) or the bank.
        case pending
        /// The player closed the App Store's sheet.
        case cancelled
        /// The App Store could not be reached or refused.
        case failed

        /// The line shown after it, `nil` when there is nothing to say.
        public func text(in language: DisplayLanguage) -> String? {
            switch self {
            case .bought: language.text("Overseas maps unlocked. Have a good trip!", "海外地圖已解鎖，祝旅途愉快！")
            case .restored: language.text("Your purchase is restored.", "已恢復購買。")
            case .nothingToRestore: language.text("No purchase was found for this Apple Account.", "這個 Apple 帳號沒有找到購買紀錄。")
            case .pending: language.text("The purchase is waiting for approval. The maps open once it is approved.", "購買正在等待核准，核准後地圖就會打開。")
            case .cancelled: nil
            case .failed: language.text("The App Store could not be reached. Please try again later.", "目前連不上 App Store，請稍後再試。")
            }
        }
    }
}
