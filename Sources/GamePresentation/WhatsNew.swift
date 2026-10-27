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
            id: "2026-10-27",
            items: [
                Line(
                    english: "In 3D, the TRA local trains are the new EMU800, EMU500 and EMU900, running mixed.",
                    chinese: "3D 的台鐵區間車換成新的 EMU800、EMU500 和 EMU900，三款混著跑。"
                ),
                Line(
                    english: "In 3D, half the Taipei Metro trains are the new C341.",
                    chinese: "3D 的台北捷運有一半換成新的 C341。"
                ),
                Line(
                    english: "Kaohsiung Station stands on the 3D map: the new station, its great canopy and the old station building.",
                    chinese: "3D 地圖多了高雄車站：新站房、大天棚和帝冠式舊站房。"
                ),
                Line(
                    english: "In 3D, the Puyuma, the Chu-Kuang coaches and the push-pull Tze-Chiang have a new look; the push-pull sets have an E500 at each end.",
                    chinese: "3D 的普悠瑪號、莒光號客車和推拉式自強號換新外型，推拉式兩端都是 E500。"
                ),
                Line(
                    english: "With the train pack, the push-pull Tze-Chiang can take the classic E1000 look.",
                    chinese: "列車包裡，推拉式自強號可以換成 E1000 經典外觀。"
                ),
                Line(
                    english: "Old games can turn on roads and buses: choose the bus tool and tap Turn On Roads and Buses.",
                    chinese: "舊存檔也能開公車：選公車工具，按「打開道路與公車」。"
                ),
                Line(
                    english: "The traffic lights at 3D crossings change with the clock.",
                    chinese: "3D 路口的紅綠燈會照時間換燈。"
                ),
            ],
            fixes: []
        ),
        Entry(
            id: "2026-10-26",
            items: [
                Line(
                    english: "Draw your own bus routes from a station: tap the stops along the streets, and the buses run in 2D and 3D.",
                    chinese: "可以從車站自己畫公車路線：沿著街點站牌，公車在 2D 和 3D 都會跑。"
                ),
                Line(
                    english: "On real-world maps the buses follow the real streets, and a stop tapped beside a real bus stop takes its place and name.",
                    chinese: "實景地圖的公車沿真的街道走；點在真的公車站旁，站牌會吸過去、用它的站名。"
                ),
                Line(
                    english: "Bus stops are numbered, arrows point the way to the station, and one line sums up the stops, distance and minutes.",
                    chinese: "站牌有編號，箭頭指向車站，上方一行寫站數、公里和分鐘。"
                ),
                Line(
                    english: "How to Get There, in a station's panel: pick where to go and see the lines, changes, minutes and fare.",
                    chinese: "車站面板的「怎麼搭」：選要去哪，就看到搭哪條線、轉幾次、幾分鐘、多少錢。"
                ),
                Line(
                    english: "The line panel and the ridership layer show each line's riders, the most crowded sections and the trips no line serves.",
                    chinese: "路線面板與載客量圖層：看每條線的客流、最擠的區間和沒接到的旅客。"
                ),
                Line(
                    english: "In 3D, the Taroko Express, the E500 and the push-pull Tze-Chiang coaches have a new look.",
                    chinese: "3D 的太魯閣號、E500 與推拉式自強號客車外型重做。"
                ),
            ],
            fixes: [
                Line(
                    english: "Continuing or loading a game no longer freezes the screen.",
                    chinese: "按「繼續」或讀存檔時，畫面不再凍住。"
                ),
                Line(
                    english: "The bus tool and the 3D map no longer stop for a moment the first time they read the streets.",
                    chinese: "公車工具和 3D 地圖第一次讀街道時，不再停一下。"
                ),
                Line(
                    english: "When the phone is busy in 3D, the street traffic thins out first; every train and bus stays.",
                    chinese: "3D 負荷重時先少畫街上的車，列車和公車一輛都不少。"
                ),
                Line(
                    english: "In Business and Group count only department stores, hotels and amusement parks.",
                    chinese: "成就「多角經營」「企業集團」只算百貨公司、飯店、遊樂園。"
                ),
            ]
        ),
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
