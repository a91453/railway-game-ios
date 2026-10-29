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
            id: "2026-10-30-95",
            items: [
                Line(
                    english: "The lines panel is a short list with two rows per line (yesterday's riders, profit and a trend); tap a line for a page of its own, with previous and next line.",
                    chinese: "路線面板改成短清單，每條線兩行；點一條線進它自己的頁，有上一條與下一條。"
                ),
                Line(
                    english: "Long line lists fold into groups, and a new Needs attention filter shows only the lines to look at.",
                    chinese: "線多時分組可收合，也能只看「需要注意」的線。"
                ),
                Line(
                    english: "Three new charts show how full things are: riders between stops on a line's panel, a section hour by hour, and each day's fullest train.",
                    chinese: "三張新的載客圖：路線面板的各站間載客、區間各時段、每日最擠的一班。"
                ),
                Line(
                    english: "The Finance panel shows income and costs as two donut charts.",
                    chinese: "財務面板用兩張甜甜圈圖，看錢從哪裡來、花到哪裡去。"
                ),
                Line(
                    english: "Bubbles, fares, prices and place names on the map no longer cover each other, and the whole of Taiwan comes first when you pick a real map.",
                    chinese: "地圖上的泡泡、票價、價錢和地名不再互相蓋住；選真實地圖時，「整個臺灣」排在第一個。"
                ),
                Line(
                    english: "Buying the Sanying line builds the real Sanxia depot with it, so its trains rest there overnight and start on time in the morning.",
                    chinese: "買三鶯線時一起蓋真實的三峽機廠，車晚上收在機廠，早上準時出發。"
                ),
                Line(
                    english: "Roads you lay are drawn as wide as the map's own lanes, and city buses follow one-way streets and go through tunnels.",
                    chinese: "你鋪的路畫得和底圖的巷弄一樣寬；市區公車照單行道的方向走，也會穿過隧道。"
                ),
                Line(
                    english: "The loading screen shows the steps actually done, and you can go back to the previous screen.",
                    chinese: "載入畫面顯示實際完成的步驟，也能回到上一個畫面。"
                ),
                Line(
                    english: "In a station's panel, jump between groups from the menu in the navigation bar; tapping a short-of-materials bubble opens the freight group.",
                    chinese: "車站面板的跳組改到導覽列的選單；點「缺建材」泡泡，直接停在貨運那一組。"
                ),
                Line(
                    english: "In 3D, the Puyuma is redrawn as an eight-car train with new lights and red stripes.",
                    chinese: "3D 的普悠瑪換成新版八節車，燈與紅色雙帶重畫。"
                ),
                Line(
                    english: "Kaohsiung's Red and Orange lines run three-car trains, Taichung's Green line runs the new two-car train, and the Mingri runs in the E200 Mingri style.",
                    chinese: "高雄紅橘線跑三節車，台中綠線跑新版兩節車，鳴日號改畫 E200 鳴日號風格。"
                ),
            ],
            fixes: [
                Line(
                    english: "Choosing the high-speed rail or Yilan line demo closes the menu at once, and the loading screen is no longer covered.",
                    chinese: "高鐵、宜蘭線示範按下就關掉選單，載入畫面不再被蓋住。"
                ),
                Line(
                    english: "The fleet list can be dragged from a train's card.",
                    chinese: "車隊清單從車卡上也拖得動。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-29-94",
            items: [
                Line(
                    english: "With no bus tool chosen, tap the road and then the stops in order to open a city bus route that skips stations.",
                    chinese: "公車工具什麼都沒選時點路面，再依序點站牌，就開一條不經過車站的市區路線。"
                ),
                Line(
                    english: "The new Route | Road switch lets you drag a finger across the map to lay your own roads, and take a stretch away.",
                    chinese: "工具上方多了「路線｜道路」切換：單指拖過地圖自己鋪路，也能拆掉一段。"
                ),
                Line(
                    english: "Tracing along a real line now joins the track you or an acquisition already laid, and that stretch costs nothing.",
                    chinese: "沿著真實路線描線，碰到自己或收購的軌道會直接接上繼續描，這一段不用再付錢。"
                ),
                Line(
                    english: "Real lines give way to your own track: where your track covers one, that stretch and its real trains are not drawn, and a line mostly made of your stations runs no real trains. Take yours away and they come back.",
                    chinese: "自己的軌道蓋住的真實路線不再畫出來，那一段的真實列車也不跑；車站大多是你的那條線，整條不跑真實列車。拆掉就回來。"
                ),
                Line(
                    english: "The Sanying line can be bought, and its real timetable runs on both days; in 3D it is a two-car train.",
                    chinese: "三鶯線可以買了，真實班次兩天都照常發車；3D 裡的三鶯線是兩節一組的車。"
                ),
                Line(
                    english: "Taichung Metro's Green line trains in 3D have redrawn fronts and bodies.",
                    chinese: "3D 的台中捷運綠線，車頭與車身重畫。"
                ),
                Line(
                    english: "3D street corners have bus stop poles, and three in ten stops have a pair of red and green post boxes.",
                    chinese: "3D 街角的公車站多了站牌，三成的站旁有一對紅綠郵筒。"
                ),
                Line(
                    english: "Holding the phone sideways with the detail card open, the layers strip folds into one Layers button, and the next step and Skip night fold by width.",
                    chinese: "手機橫拿、開著細節卡時，地圖上方空間不夠，圖層條會收成一顆「圖層」鈕，下一步與「跳過夜晚」也依寬度收起來。"
                ),
                Line(
                    english: "Finance charts: a line's ridership and profit are separate charts, the income chart's legend shows costs, and all five charts can be read point by point with VoiceOver.",
                    chinese: "財務圖表：路線的運量與損益分成兩張圖；收入與成本圖的圖例看得到成本；五張圖都能用 VoiceOver 逐點聽。"
                ),
                Line(
                    english: "Removing things such as clearing a timetable, a platform or a freight yard asks to confirm first.",
                    chinese: "清空時刻表、拆月台、拆貨運場、刪停靠站這類移除動作，先跳確認再執行。"
                ),
            ],
            fixes: [
                Line(
                    english: "After loading a save or changing a route, trains stop for about a third as long.",
                    chinese: "載入存檔和改路線之後，列車停住的那幾秒縮短到約三分之一。"
                ),
                Line(
                    english: "After building a station, opening a line, renaming a station or buying a train, the screen pauses less.",
                    chinese: "蓋車站、開路線、改站名、買列車之後，畫面少卡一截。"
                ),
                Line(
                    english: "The follow bar, finance charts and ledger no longer redraw every moment, so they stay smoother while open.",
                    chinese: "跟隨列車、財務圖表和帳目不再每個瞬間重算，開著時更順。"
                ),
                Line(
                    english: "In dark mode, the bankruptcy countdown and news count on red are easy to read.",
                    chinese: "深色模式下，紅底上的破產倒數和新聞數字看得清楚。"
                ),
                Line(
                    english: "Small buttons on phones are easier to tap.",
                    chinese: "手機上的小按鈕更好點了。"
                ),
                Line(
                    english: "Closing 3D while it is still loading no longer wastes the work, and reopening picks it up; the speed tip shows again if it was dismissed unseen.",
                    chinese: "3D 還在載入時關掉不會白費，重開接著用；速度提示被收掉時還會再跳一次。"
                ),
                Line(
                    english: "Stop following is no longer red, and the layer notes, colour names and sell-train confirmation read more clearly.",
                    chinese: "「取消跟隨」不再是紅色，圖層說明、顏色名稱、賣車確認的文字更清楚。"
                ),
                Line(
                    english: "With Reduce Motion on, bubbles, the mini map and panels no longer bounce or slide.",
                    chinese: "打開「減少動態效果」後，泡泡、小地圖和面板不再彈跳或滑動。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-28-93",
            items: [
                Line(
                    english: "Each Taipei Metro line in 3D runs its own trains: C371, C381 and C341, and the Circular line's four-car train.",
                    chinese: "3D 的台北捷運各線跑自己的車：C371、C381、C341，環狀線是四節的列車。"
                ),
                Line(
                    english: "The Liujia and Neiwan lines can both be bought, in either order; Zhuzhong's Liujia line platform is raised, as in reality.",
                    chinese: "六家線和內灣線都能買，先買哪條都行；竹中的六家線月台照真實架高。"
                ),
                Line(
                    english: "Central Taipei in 3D has its landmarks and old city gates; Taipei Station and Taipei 101 are redrawn, and Kaohsiung Station has its two towers.",
                    chinese: "3D 的台北市中心多了地標與城門；台北車站和 101 重畫，高雄車站多了兩棟共構大樓。"
                ),
                Line(
                    english: "3D maps have conifers, shrubs and storage tanks.",
                    chinese: "3D 地圖多了針葉樹、灌木叢和儲槽。"
                ),
                Line(
                    english: "3D quality follows each device's memory and chip: larger iPads look sharper, and phones with less memory stay steady.",
                    chinese: "3D 的畫質照每台裝置的記憶體與晶片調整：大 iPad 更清楚，記憶體小的手機更穩。"
                ),
                Line(
                    english: "When your device can't keep up with the speed you set, a tip says how fast this map really runs and offers to switch to that speed.",
                    chinese: "裝置跑不到設定的倍速時，會跳一次提示，告訴你這張地圖實際跑得到多快，並可一鍵改成那一檔。"
                ),
            ],
            fixes: [
                Line(
                    english: "At 6000× on a big map the game no longer pauses every few seconds or at 6:00 each morning.",
                    chinese: "大地圖開 6000 倍速，不再每隔幾秒或每天早上 6 點卡一下。"
                ),
                Line(
                    english: "The first time 3D opens it no longer freezes for a moment, and far-off city blocks draw faster.",
                    chinese: "第一次開 3D 不再頓一下，遠處的城市畫得更快。"
                ),
                Line(
                    english: "The speed you set is kept through the night skip and in the demo lines.",
                    chinese: "設定的遊戲速度在跳過夜晚和示範路線裡都會保留。"
                ),
                Line(
                    english: "Road markings on bridge approaches lie flat on the road, and pedestrian signals no longer jump.",
                    chinese: "橋頭引道的標線貼著路面，行人號誌不再跳格。"
                ),
                Line(
                    english: "On the whole-island map, bus stops, stations and track line up with Apple Maps instead of sitting about 1 km off.",
                    chinese: "整島世界的站牌、車站和軌道對齊 Apple 地圖，不再偏約 1 公里。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-28",
            items: [
                Line(
                    english: "At night the 3D trains light up: headlights, tail lights and lit windows.",
                    chinese: "夜裡 3D 的列車會亮燈：車頭燈、車尾紅燈和車廂窗。"
                ),
                Line(
                    english: "Train windows reflect the sky, and stainless steel cars shine like metal.",
                    chinese: "列車車窗會反光，不鏽鋼車身有金屬光澤。"
                ),
                Line(
                    english: "The 3D map's pale tint is softer; traffic lights and level crossings keep their own colours.",
                    chinese: "3D 地圖的淡色調更柔；紅綠燈和平交道仍保留原色。"
                ),
                Line(
                    english: "Scooters on 3D streets ride like Taipei's: three kinds, side by side, parked in a row under arcades.",
                    chinese: "3D 街上多了台北那樣的機車：三種車、並排騎、騎樓前停一排。"
                ),
                Line(
                    english: "3D crossings have zebra crossings, scooter waiting boxes, hook-turn boxes and red and yellow kerb lines, as in Taiwan.",
                    chinese: "3D 路口照台灣的做法畫斑馬線、機車停等區、待轉區和紅黃線。"
                ),
                Line(
                    english: "Lanes have marked footpaths, and arcade widths follow the road's class.",
                    chinese: "巷子有標線畫出的人行道，騎樓也依道路等級調整寬度。"
                ),
                Line(
                    english: "3D crossings show pedestrian signals: the green man and the countdown.",
                    chinese: "3D 路口有行人號誌：小綠人和倒數。"
                ),
                Line(
                    english: "3D depots have maintenance sheds, and the Changhua roundhouse has its turntable.",
                    chinese: "3D 機廠多了檢修庫，彰化的扇形車庫有轉車台。"
                ),
                Line(
                    english: "3D platforms have stop markers, edge lights, bins and train destination boards.",
                    chinese: "3D 月台多了停車位置標、月台邊燈、回收桶和車頭方向幕。"
                ),
                Line(
                    english: "A garbage truck makes its rounds in the evening.",
                    chinese: "傍晚街上會有垃圾車。"
                ),
                Line(
                    english: "City buses run on roads you lay yourself.",
                    chinese: "市區公車可以走自己鋪的路。"
                ),
                Line(
                    english: "Real-world Taiwan maps that give all the land now have roads and buses too, including old games, the demo and the Pingxi Line challenge.",
                    chinese: "土地全給的台灣實景地圖也有道路與公車（舊存檔、實景示範、平溪線挑戰）。"
                ),
                Line(
                    english: "A new real-world game can start at a place in each of Taiwan's 22 counties and cities.",
                    chinese: "實景新局：台灣 22 個縣市各有一個地點可選。"
                ),
                Line(
                    english: "Passenger route searches are much faster, so games with many lines run smoother.",
                    chinese: "乘客的路線搜尋快了很多，線多的存檔更順。"
                ),
            ],
            fixes: [
                Line(
                    english: "Changing the game speed no longer drops the work in progress; the timeline no longer stalls with many trains.",
                    chinese: "改遊戲速度時不再丟掉正在算的進度；車多時時間軸不再卡住。"
                ),
                Line(
                    english: "Train showcase: tap the screen after hiding the buttons and they come back.",
                    chinese: "列車展示：隱藏按鈕後點畫面，按鈕會回來。"
                ),
            ]
        ),
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
