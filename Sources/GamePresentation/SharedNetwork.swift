import Foundation
import GameCore

// Decision 409: a network shared between players with no server. The game
// menu's export and the postcard's "Share Network" write a save file of
// the game's own type; a friend who taps it in LINE, AirDrop or Files
// opens the game on it, sees its postcard, and plays a new game from it,
// with money of their own, or only looks round it. Neither writes over a
// save of theirs.

/// A save file someone sent, read as untrusted input: no larger than
/// ``maximumBytes``, of a version this build reads, that GameCore accepts.
/// Reading one that is not changes nothing.
public struct SharedNetwork: Sendable {
    /// The file name extension of the game's own save type. The file is
    /// JSON, as the saves in the folder are.
    public static let fileExtension = "alongtheline"
    /// The save type's identifier (the app's Info.plist declares it, with
    /// ``fileExtension``).
    public static let typeIdentifier = "io.github.a91453.RailwayGame.save"
    /// The largest file read: 64 MB, some nine times the largest save
    /// measured (the High Speed Rail demo's, 7.2 MB). A larger file is
    /// refused before it is read.
    public static let maximumBytes = 64 << 20

    /// The world in the file, as its sender left it.
    public let world: GameWorld
    /// The sender's news log, when the file carries one that reads.
    public let news: NewsLog?
    /// The name on the sender's postcard, cleaned and cut as the postcard
    /// cuts it, or `nil` when the file names none.
    public let company: String?

    /// The network in the save file `data`.
    public init(data: Data) throws(SaveError) {
        guard data.count <= Self.maximumBytes else { throw .tooLarge }
        let file = try SaveLibrary.decodeFile(data)
        world = file.game.world
        news = file.news
        company = file.company.flatMap(Self.cleanCompany)
    }

    /// The network in the file at `url`: its size is asked first, so a
    /// file too large is never read into memory. `url` may be outside the
    /// app's container (a file from Files or another app): it is read
    /// with its security scope.
    public init(contentsOf url: URL) throws(SaveError) {
        #if canImport(Darwin)
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        #endif
        let size: Int?
        do {
            size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        } catch {
            throw .fileSystem
        }
        guard (size ?? 0) <= Self.maximumBytes else { throw .tooLarge }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw .fileSystem
        }
        try self.init(data: data)
    }

    /// The name on the postcard, trimmed and cut as the postcard cuts the
    /// player's own (``NetworkPostcard/companyName(_:in:)``), without
    /// control or format characters (a right-to-left override would turn
    /// the text round); `nil` when nothing is left.
    static func cleanCompany(_ name: String) -> String? {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: name.unicodeScalars.filter { scalar in
            ![.control, .format].contains(scalar.properties.generalCategory) || scalar == "\n"
        })
        let trimmed = String(scalars).split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(NetworkPostcard.nameLimit))
    }

    /// The postcard of this network, under the sender's name, or
    /// "Friend's Network" (within the postcard's 16 characters) when the
    /// file names none.
    public func postcard(in language: DisplayLanguage) -> NetworkPostcard {
        NetworkPostcard(world: world, companyName: company ?? language.text("Friend's Network", "朋友的路網"), in: language)
    }

    /// The world a new game from this network starts with: the sender's
    /// lines, stations, trains, timetables and town, with money of the
    /// player's own. The balance is `balance` (a new game's), the sender's
    /// loan, ledger, days and closed years are gone and unlimited funds
    /// are off; the fare rules, what was built at what it cost, and the
    /// date stay. A challenge's goals are not carried over.
    ///
    /// GameCore keeps the money out of reach of everything but its
    /// commands, and none starts the books again, so this is done on the
    /// world's save (the `SavedGame` JSON), which GameCore then reads back
    /// with every check it makes of a save.
    public func newGameWorld(balance: Money = GameWorld.startingBalance) throws(SaveError) -> GameWorld {
        do {
            let encoder = JSONEncoder()
            let saved = try encoder.encode(SavedGame(world: world))
            guard var root = try JSONSerialization.jsonObject(with: saved) as? [String: Any],
                  var world = root["world"] as? [String: Any],
                  var economy = world["economy"] as? [String: Any],
                  var accounts = world["accounts"] as? [String: Any] else { throw SaveError.damaged }
            economy["balance"] = try Self.fragment(balance, encoder)
            economy["unlimitedFunds"] = nil
            accounts["pending"] = try Self.fragment(HourlyAccrual.empty, encoder)
            accounts["entries"] = [Any]()
            accounts["days"] = [Any]()
            for key in ["loan", "capitalDays", "years", "depotHours"] {
                accounts[key] = nil
            }
            world["economy"] = economy
            world["accounts"] = accounts
            world["scenario"] = nil
            root["world"] = world
            let data = try JSONSerialization.data(withJSONObject: root)
            return try JSONDecoder().decode(SavedGame.self, from: data).world
        } catch {
            throw .damaged
        }
    }

    /// `value` encoded alone, as `JSONSerialization` holds it.
    private static func fragment(_ value: some Encodable, _ encoder: JSONEncoder) throws -> Any {
        try JSONSerialization.jsonObject(with: encoder.encode(value), options: .fragmentsAllowed)
    }
}

/// What the player does with a network someone sent (decision 409).
public enum SharedNetworkChoice: String, CaseIterable, Hashable, Sendable {
    /// A new game from the network, with money of the player's own.
    case newGame
    /// Only look round it: nothing of it is saved.
    case look

    public func title(in language: DisplayLanguage) -> String {
        switch self {
        case .newGame: language.text("Start a New Game from This Network", "從這張路網開新的一局")
        case .look: language.text("Just Look", "只看")
        }
    }

    public func detail(in language: DisplayLanguage) -> String {
        switch self {
        case .newGame:
            language.text(
                "Its lines, stations and timetables are yours, with a new company's money. Your saves stay as they are.",
                "路線、車站、班次都給你，錢從新公司重新算。你的存檔不會被蓋掉。"
            )
        case .look:
            language.text(
                "Look round it as it is. Nothing here is saved, and your own game is still there.",
                "照原樣看看。這裡的一切都不會存檔，你自己的遊戲也還在。"
            )
        }
    }

    public var accessibilityIdentifier: String { "sharedNetwork.\(rawValue)" }
}
