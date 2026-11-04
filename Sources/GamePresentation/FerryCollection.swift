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

    /// The pages of the collection, in the order its picker shows them.
    public enum Page: String, CaseIterable, Hashable, Sendable {
        case trains, ferries

        /// "Trains" / "列車", "Ferries" / "渡輪".
        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .trains: language.text("Trains", "列車")
            case .ferries: language.text("Ferries", "渡輪")
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
}
