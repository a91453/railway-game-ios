import GameCore

/// The collection's ferry page (decision 585): the two real boats the
/// game's ferries are drawn from (decision 579's studies) and the two real
/// crossings its demo lays, in words a player reads.
public enum FerryCollection {
    /// The Gushan–Cijin full fare: NT$30 a rider since 2024-11 (decision
    /// 585: the game charges one fare a mode, Tamsui–Bali's, so this is the
    /// collection's text only).
    public static let gushanCijinFare = Money(3_000)

    /// One entry: a name and the lines under it.
    public struct Entry: Hashable, Sendable, Identifiable {
        public let id: String
        public let title: String
        public let lines: [String]
    }

    /// The pages of the collection, in the order its picker shows them
    /// (decision 632 adds the cable cars, decision 701 the aircraft).
    public enum Page: String, CaseIterable, Hashable, Sendable {
        case trains, ferries, cableways, aircraft

        /// "Trains" / "列車", "Ferries" / "渡輪", "Cable Cars" / "纜車".
        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .trains: language.text("Trains", "列車")
            case .ferries: language.text("Ferries", "渡輪")
            case .cableways: language.text("Cable Cars", "纜車")
            case .aircraft: language.text("Aircraft", "飛機")
            }
        }

        /// Decision 632: the 3D stage the page opens, `nil` for the trains'
        /// own garage.
        public var exhibit: Map3DCollectionShowcase.Exhibit? {
            switch self {
            case .trains: nil
            case .ferries: .ferries
            case .cableways: .cableways
            case .aircraft: .aircraft
            }
        }
    }

    /// The collection's name in Settings: "Collection" / "圖鑑".
    public static func name(in language: DisplayLanguage) -> String {
        language.text("Collection", "圖鑑")
    }

    /// The boats: Shun Feng 166 (Tamsui–Bali) and Chi Gu No. 2 (Gushan–Cijin).
    public static func boats(in language: DisplayLanguage) -> [Entry] {
        [
            Entry(id: "shunfeng166", title: language.text("Shun Feng 166", "順風 166 號"), lines: [
                language.text("Tamsui–Bali ferry", "淡水—八里渡輪"),
                language.text("18.00 m long, 4.43 m wide · 99 passengers", "長 18.00 公尺、寬 4.43 公尺 · 載客 99 人"),
            ]),
            Entry(id: "chigu2", title: language.text("Chi Gu No. 2", "旗鼓二號"), lines: [
                language.text("Gushan–Cijin ferry", "鼓山—旗津渡輪"),
                language.text("25.3 m long · 170 passengers", "長 25.3 公尺 · 載客 170 人"),
            ]),
        ]
    }

    /// The real crossings the transit tool can lay (``RealFerry``).
    public static func routes(in language: DisplayLanguage) -> [Entry] {
        [
            Entry(id: "tamsuiBali", title: language.text("Tamsui–Bali", "淡水—八里"), lines: [
                language.text(
                    "About \(RealFerry.tamsuiBali.legMetres.reduce(0, +).groupedText) m across the Tamsui River mouth",
                    "橫越淡水河口約 \(RealFerry.tamsuiBali.legMetres.reduce(0, +).groupedText) 公尺"
                ),
                language.text(
                    "Weekdays 7:00–19:00, weekends 7:00–20:00 · \(FerryRoute.fare.moneyText) a ride",
                    "平日 7:00–19:00、假日 7:00–20:00 · 每人 \(FerryRoute.fare.moneyText)"
                ),
            ]),
            Entry(id: "gushanCijin", title: language.text("Gushan–Cijin", "鼓山—旗津"), lines: [
                language.text(
                    "About \(RealFerry.gushanCijin.legMetres.reduce(0, +).groupedText) m across Kaohsiung Harbour",
                    "橫越高雄港約 \(RealFerry.gushanCijin.legMetres.reduce(0, +).groupedText) 公尺"
                ),
                language.text(
                    "About 5 minutes across · 5:00 to 2:00 the next day · \(Self.gushanCijinFare.moneyText) a ride",
                    "船程約 5 分 · 5:00 到翌日 2:00 · 每人 \(Self.gushanCijinFare.moneyText)"
                ),
            ]),
        ]
    }

    /// The page's note: how a ferry comes into a game.
    public static func note(in language: DisplayLanguage) -> String {
        language.text(
            "Open a ferry with the Transit tool's Ferries mode: tap piers on the shore, or lay one of these crossings where the map has it.",
            "用「接駁」工具的「渡輪」模式開航線：在岸邊點碼頭，或在地圖上有這條航線的地方照真實航線拉。"
        )
    }

    /// Decision 632: the real cable cars the game draws cabins of, with
    /// their real figures (sources in the decision).
    public static func cableways(in language: DisplayLanguage) -> [Entry] {
        [
            Entry(id: "maokong", title: language.text("Maokong Gondola", "貓空纜車"), lines: [
                language.text("Taipei · opened 4 July 2007", "臺北 · 2007 年 7 月 4 日通車"),
                language.text("4.033 km · 4 stations and 2 angle stations", "全長 4.033 公里 · 4 個車站、2 個轉角站"),
                language.text("136 cabins, 30 of them crystal cabins with a glass floor", "車廂 136 部，其中 30 部是玻璃地板的水晶車廂"),
                language.text("8 passengers a cabin, 5 in a crystal cabin", "每部載 8 人，水晶車廂 5 人"),
            ]),
            Entry(id: "sunMoonLake", title: language.text("Sun Moon Lake Ropeway", "日月潭纜車"), lines: [
                language.text("Nantou · opened 28 December 2009", "南投 · 2009 年 12 月 28 日通車"),
                language.text("1.877 km · 2 stations, over a hill", "全長 1.877 公里 · 2 個車站，翻過一座山"),
                language.text("86 cabins · 8 passengers a cabin", "車廂 86 部 · 每部載 8 人"),
            ]),
        ]
    }

    /// Decision 632: the cable car page's note: how one comes into a game.
    public static func cablewayNote(in language: DisplayLanguage) -> String {
        language.text(
            "Build a cable car with the building tools' Cable car mode: tap its stations, or lay the Maokong Gondola where the map has it. Near Sun Moon Lake its cabins are Sun Moon Lake's.",
            "用建造工具的「纜車」模式蓋纜車：點出各站，或在地圖上有貓空纜車的地方照真實路線拉。蓋在日月潭附近，吊廂就是日月潭的。"
        )
    }
}
