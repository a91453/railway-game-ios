/// Decision 415: the "What's New" card (這版新增): what each build brought,
/// for the player, in both languages. It shows once, the first time an
/// updated app opens (``GameLauncher/showsWhatsNew``), and again from Help.
///
/// Before each TestFlight release, the newest entry is written with
/// `.github/testflight-whats-new.md` (decision 415 says how): a new entry
/// on top with a new ``Entry/id`` shows the card again to everyone who
/// updates; an entry already released keeps its id.
public enum WhatsNew {
    /// One build's news.
    public struct Entry: Equatable, Sendable, Identifiable {
        /// Never changed once released: the card shows again whenever the
        /// newest entry's id is not the one last seen.
        public let id: String
        /// What the player can now do, one line each.
        public let items: [Line]
        /// What works again.
        public let fixes: [Line]
    }

    /// One line in both languages.
    public struct Line: Equatable, Sendable {
        public let english: String
        public let chinese: String

        public func text(in language: DisplayLanguage) -> String {
            language.text(english, chinese)
        }
    }

    /// The builds' news, the newest first.
    public static let entries: [Entry] = [
        Entry(
            id: "2026-10-25",
            items: [
                Line(
                    english: "Idle Mode, beside Settings in the game menu: the camera follows your trains and looks over your stations and lines by itself. Tap to come back.",
                    chinese: "遊戲選單「設定」旁的「放空模式」：鏡頭自己跟著列車、看車站和路線，碰一下就回來。"
                ),
                Line(
                    english: "Metro lines can be bought, as light rail could: the Xinbeitou and Xiaobitan branches too.",
                    chinese: "捷運路線可以收購了，和輕軌一樣；新北投、小碧潭支線也可以。"
                ),
                Line(
                    english: "You can build your own schools, hospitals and night markets: they help the town round them grow.",
                    chinese: "可以自己蓋學校、醫院和夜市了，周圍的城鎮會長得更好。"
                ),
                Line(
                    english: "Each achievement has its own picture.",
                    chinese: "每個成就都有自己的圖。"
                ),
                Line(
                    english: "The EMU3000 in 3D has a new look, closer to the real train.",
                    chinese: "3D 的 EMU3000 外型重做，更像真的車。"
                ),
            ],
            fixes: [
                Line(
                    english: "The high-speed rail demo opens without a long wait.",
                    chinese: "高鐵示範打開時不再卡很久。"
                ),
                Line(
                    english: "In 3D, the back half of the N700S-G faces the right way, and the end of long trains stays on the track.",
                    chinese: "3D 的 N700S-G 後半列方向對了；長編組的車尾不再飄離軌道。"
                ),
                Line(
                    english: "A high-speed viaduct changes its look as soon as it is built.",
                    chinese: "高鐵高架蓋好就馬上換樣子。"
                ),
            ]
        ),
    ]

    /// The newest entry's id: what ``LauncherPreferences/whatsNewSeen``
    /// is compared with.
    public static var edition: String? { entries.first?.id }

    /// The card's title.
    public static func title(in language: DisplayLanguage) -> String {
        language.text("What's New", "這版新增")
    }

    /// The headings over an entry's two lists.
    public static func itemsHeading(in language: DisplayLanguage) -> String {
        language.text("New", "新增")
    }

    public static func fixesHeading(in language: DisplayLanguage) -> String {
        language.text("Fixed", "修好的")
    }

    /// Under the row's title in Help.
    public static func helpDetail(in language: DisplayLanguage) -> String {
        language.text("What the latest update brought", "最近一次更新多了什麼")
    }

    /// The row's identifier in Help, for the UI tests.
    public static let helpIdentifier = "help.whatsNew"
    /// The card's close button, for the UI tests.
    public static let doneIdentifier = "whatsNew.done"

    /// Whether Help's search, `query`, shows the row: with no search, and
    /// with a search for its title or one of the newest entry's words.
    public static func shows(matching query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return true }
        let lines = (entries.first.map { $0.items + $0.fixes } ?? []).flatMap { [$0.english, $0.chinese] }
        let haystack = ([
            title(in: .english), title(in: .traditionalChinese),
            helpDetail(in: .english), helpDetail(in: .traditionalChinese),
            "update version 更新 版本 新功能",
        ] + lines).joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}
