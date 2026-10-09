import GameCore

/// What "Report a Problem" in the settings shares (ARCHITECTURE decision
/// 127): a note for the player to fill in, with what a fix needs to know
/// already written under it: the app's version and build, the system and
/// the device, and, from a game, what is in it. The player chooses where it
/// goes (Mail, Messages, Notes …) in the share sheet; the app names no
/// recipient and adds nothing personal.
///
/// The references have none to port (gap): `Ci/` is a website.
public struct ProblemReport: Hashable, Sendable {
    /// The app's version (`CFBundleShortVersionString`) and build
    /// (`CFBundleVersion`).
    public let version: String
    public let build: String
    /// "iOS 26.0", and the device's model identifier ("iPhone17,1").
    public let system: String
    public let device: String
    /// What is in the game it was sent from (``GameSession/problemReportGame``),
    /// or `nil` from the start screen.
    public let game: String?

    public init(version: String, build: String, system: String, device: String, game: String? = nil) {
        self.version = version
        self.build = build
        self.system = system
        self.device = device
        self.game = game
    }

    /// "0.4.0 (12)": the version and, in brackets, the build.
    public var versionText: String {
        "\(version) (\(build))"
    }

    /// The subject of the note: the app's name and version.
    public func subject(in language: DisplayLanguage) -> String {
        language.text("Along the Line \(versionText): a problem", "沿線 \(versionText)：問題回報")
    }

    /// The note: three questions for the player, then the details.
    public func text(in language: DisplayLanguage) -> String {
        var lines = [
            language.text("What happened?", "發生了什麼事？"),
            "",
            "",
            language.text("What did you expect?", "原本預期會怎樣？"),
            "",
            "",
            language.text("How can it be made to happen again?", "怎麼做可以再發生一次？"),
            "",
            "",
            "—",
            language.text("Version: \(versionText)", "版本：\(versionText)"),
            language.text("System: \(system), \(device)", "系統：\(system)，\(device)"),
        ]
        if let game {
            lines.append(language.text("Game: \(game)", "遊戲：\(game)"))
        }
        return lines.joined(separator: "\n")
    }
}

extension GameSession {
    /// What the game holds, in one line for a problem report (decision
    /// 127): the map, the scenario's id if one is played, the time, the
    /// money and how much is built, and the save version it would be
    /// written in.
    public var problemReportGame: String {
        let map: String
        if world.geoAnchor == nil {
            map = language.text("blank map", "空白地圖")
        } else {
            map = language.text("real-world map", "實景地圖")
        }
        let mode = world.accounts.mode == .free ? language.text("free", "自由") : language.text("managed", "經營")
        var parts = [
            "\(map) · \(mode)",
            world.clock.displayText(in: language),
            world.economy.balance.moneyText,
            language.text(
                "\(world.stations.count) stations, \(world.lines.count) lines, \(world.trains.count) trains",
                "\(world.stations.count) 站、\(world.lines.count) 條路線、\(world.trains.count) 列車"
            ),
            language.text("save version \(SavedGame.currentVersion)", "存檔版本 \(SavedGame.currentVersion)"),
        ]
        if let scenario = world.scenario {
            parts.insert(scenario.scenario.id, at: 1)
        }
        return parts.joined(separator: " · ")
    }
}
