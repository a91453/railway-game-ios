// The help guide (ARCHITECTURE decision 177): questions players ask, with
// answers, searchable in English and Traditional Chinese. A-Train Tourism has
// hint pages sorted by the problem the player has; the reference's `Ci/`
// keeps six questions of its own (`guide.metro.faq.0` to `.5` in
// `lib/ui-locales/zh-CN__q_8e57e7fa49d074d2.js`: how to create a line, add a
// node or station, move or delete a station, get trains running, extend a
// line, see the introduction again), written for its mouse and keys. Those
// six are carried over, turned into this game's touch controls and into
// Taiwan's wording; the rest are this project's own. Presentation only:
// nothing here is stored.

import GameCore

/// One question and its answer, in both languages.
public struct HelpEntry: Hashable, Sendable, Identifiable {
    public enum Topic: String, CaseIterable, Sendable {
        case building, running, money, city

        public func title(in language: DisplayLanguage) -> String {
            switch self {
            case .building: language.text("Building", "建設")
            case .running: language.text("Running trains", "營運")
            case .money: language.text("Money", "財務")
            case .city: language.text("The city", "城市")
            }
        }
    }

    public let id: String
    public let topic: Topic
    private let question: [String]
    private let answer: [String]
    /// Words to find it by besides its text, both languages.
    private let keywords: String

    init(_ id: String, _ topic: Topic, question: (String, String), answer: (String, String), keywords: String = "") {
        self.id = id
        self.topic = topic
        self.question = [question.0, question.1]
        self.answer = [answer.0, answer.1]
        self.keywords = keywords
    }

    public func question(in language: DisplayLanguage) -> String {
        language.text(question[0], question[1])
    }

    public func answer(in language: DisplayLanguage) -> String {
        language.text(answer[0], answer[1])
    }

    /// The same question or answer in the language `language` is not: the
    /// guide shows both (the guide is bilingual, decision 177).
    public func otherQuestion(than language: DisplayLanguage) -> String {
        language.text(question[1], question[0])
    }

    public func otherAnswer(than language: DisplayLanguage) -> String {
        language.text(answer[1], answer[0])
    }

    /// Whether every word of `query` (split at spaces, case ignored) is in
    /// the question, the answer or the keywords, in either language.
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
        guard !words.isEmpty else { return true }
        let haystack = (question + answer + [keywords]).joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// The guide: ``entries`` and the search over them.
public enum HelpGuide {
    /// The entries whose text has every word of `query`; all of them for an
    /// empty query, in the guide's order.
    public static func entries(matching query: String) -> [HelpEntry] {
        entries.filter { $0.matches(query) }
    }

    /// What the search field says.
    public static func searchPrompt(in language: DisplayLanguage) -> String {
        language.text("Search: extend a line, loan, fares…", "搜尋：如 延長路線、貸款、票價…")
    }

    public static let entries: [HelpEntry] = [
        HelpEntry(
            "firstLine", .building,
            question: ("How do I build my first line?", "如何建造第一條路線？"),
            answer: (
                "Tap Build, then Network, and drag track between two spots. Add a platform on the track for each station: a line needs two. Then open Lines, create a line through the stations and give it a train. The station master tells you the next step, and the Tutorial in the game menu walks you through it.",
                "點「建設」，選「路網」，在兩處之間拖出軌道。在軌道上為每座車站加月台：一條路線至少兩站。接著打開「路線」，把車站連成一條路線並配一列車。站長會告訴你下一步；遊戲選單裡的「教學」會一步步帶你做。"
            ),
            keywords: "create line track station 第一條 建立 開始 新手"
        ),
        HelpEntry(
            "addStation", .building,
            question: ("How do I add a station?", "如何增設車站？"),
            answer: (
                "Build track first, then use the building tools to put a platform on it. Put stations where people live and work: the Population layer in Map Layers shows where. Stations less than about 800 m apart share the same people, so spread them out.",
                "先鋪好軌道，再用建設工具在軌道上設置月台。車站要蓋在有人居住或工作的地方，「地圖圖層」的人口圖層會告訴你在哪。相距不到約 800 公尺的車站會分攤同一批人，所以盡量拉開距離。"
            ),
            keywords: "platform node 月台 節點 新增 蓋站"
        ),
        HelpEntry(
            "moveRemoveStation", .building,
            question: ("How do I rename, move or remove a station?", "如何改名、移動或拆除車站？"),
            answer: (
                "Tap a station to select it, then tap its tag (or touch and hold the station) to open the station panel. There you can rename it, change its platforms or remove it. To move one, remove it and build it again where you want it.",
                "點選車站，再點它上方的標籤（或長按車站），打開車站面板，可以改名、調整月台或拆除。要搬移車站，就拆除後在想要的位置重新蓋一座。"
            ),
            keywords: "delete rename 刪除 移動 改名"
        ),
        HelpEntry(
            "extendLine", .building,
            question: ("How do I extend a line?", "如何延長路線？"),
            answer: (
                "Build track and a station beyond the line's last stop, then open Lines, pick the line and choose Add Stop at the End. Extending toward a town with no station is the surest way to turn a losing line around: the station master points to the nearest one.",
                "在路線的最後一站之外鋪軌道、蓋車站，然後打開「路線」，選這條路線，按「在最後加入停靠站」。往還沒有車站的城鎮延伸，是讓虧損路線轉虧為盈最可靠的方法，站長會指出最近的一個。"
            ),
            keywords: "extend lengthen add stop 延伸 加站 加長"
        ),
        HelpEntry(
            "startTrains", .running,
            question: ("How do I get trains running?", "如何讓列車開始運行？"),
            answer: (
                "Open Lines, pick the line and give it a train. A line with no train carries no one, and the station master says so. More trains mean shorter waits but higher running costs; add cars when stations are crowded and trains when they are full.",
                "打開「路線」，選這條路線，幫它配車。沒有列車的路線沒人搭，站長也會提醒你。列車越多等車越短，但營運成本越高；車站擠就加掛車廂，車站滿就加開列車。"
            ),
            keywords: "train assign 配車 發車 上線 開車"
        ),
        HelpEntry(
            "whyLosing", .money,
            question: ("Why does my line lose money?", "為什麼我的路線會虧錢？"),
            answer: (
                "Usually the stations are too close together and too few people live near them, while the train costs the same to run. Open Economy to see the day's fares against running costs. Fixes: extend the line to a bigger town, build stations where more people live, use fewer or shorter trains, and check the fares. A short first line often loses money at first; the station master reports the daily loss in the first month.",
                "通常是車站太近、附近的人太少，列車的營運成本卻一樣。打開「經濟明細」可以看每天的票價收入和營運成本。解法：把路線延伸到更大的城鎮、在人口多的地方蓋站、減少列車或縮短編組、檢查票價。起步的短線一開始常常虧錢；頭一個月站長會告訴你每天虧多少。"
            ),
            keywords: "loss deficit red profit 虧損 賠錢 赤字 破產 負債"
        ),
        HelpEntry(
            "cityGrowth", .city,
            question: ("How does the city grow?", "城市怎麼成長？"),
            answer: (
                "Towns grow around stations that serve their passengers well, fastest within 250 m of a station. If a station can carry only part of its passengers (under about 80%), the buildings round it stop growing taller, so run more trains. Growth also needs building materials. The more people a town has, the more riders its stations bring.",
                "城市會圍繞服務良好的車站成長，車站 250 公尺內長得最快。如果車站只能載走一部分旅客（低於約 80%），附近的建築就不會長高，所以要加開列車。成長也需要建材。城市人口越多，車站的客源也越多。"
            ),
            keywords: "grow town building 成長 發展 長高 人口"
        ),
        HelpEntry(
            "mapColours", .city,
            question: ("What do the colours on the map mean?", "地圖上的顏色是什麼？"),
            answer: (
                "The blocks are the town's own buildings, coloured by what they are for: green homes, blue shops, orange offices, purple industry and warehouses, salmon-red public buildings (schools, offices of the state), teal sights and leisure. Flat beige ground is farmland and flat pale green a park. The taller a block stands, the more people live or work there. Map Layers shows the same uses as a layer.",
                "地圖上的方塊是城鎮自己的建物，依用途上色：綠色是住宅、藍色是商業、橘色是辦公、紫色是工業物流、鮭紅色是公共設施（學校、機關）、青綠色是觀光休閒。平的米色是農地，平的淡綠色是公園。方塊越高，住或工作的人越多。「地圖圖層」也能用圖層看同樣的用途。"
            ),
            keywords: "colour color legend block building land use green blue 顏色 圖例 方塊 建物 用途 住宅 商業 辦公 工業"
        ),
        HelpEntry(
            "materials", .city,
            question: ("What are building materials?", "建材是什麼？"),
            answer: (
                "Towns need building materials to grow, as in the real world. Build a freight yard to send materials (in the station panel's Freight section: tap a station, then its tag), give the station near the town a yard too, and the town grows at full speed. A freight line is an ordinary line switched to Freight line in Lines; it needs no special trains: any train carries \(Freight.tonsPerCar) t a car. A town short of materials grows slowly, and the station master says which one; tap its bubble on the map to open that station. A new game can turn this rule off in its options.",
                "城市和現實一樣需要建材才能成長。蓋一座貨運場出建材（在車站面板的「貨運」：點車站，再點它的標籤），城鎮附近的車站也蓋一座，城市才能全速成長。貨運路線就是在「路線」裡把一條路線打開「貨運路線」，不需要特別的貨車：任何列車每節載 \(Freight.tonsPerCar) 噸。缺建材的城市成長很慢，站長會告訴你是哪一座；點地圖上「缺建材」的泡泡就會打開那座車站。新遊戲的選項可以關掉這個規則。"
            ),
            keywords: "freight yard material cargo 貨運 貨運場 材料"
        ),
        HelpEntry(
            "buyMap", .building,
            question: ("How do I buy more of the map?", "怎麼買地圖？"),
            answer: (
                "On a map that is bought tile by tile, open the build tools and choose Expand the Map, then tap a tile next to one you own. The price depends on how many tiles you own, and you must have carried enough riders in a day to unlock the next. Track and stations can only be built on land you own.",
                "在分區購買的地圖上，打開建設工具，選「擴建地圖」，點選和已擁有區塊相鄰的一塊。價格依你已擁有的區塊數而定，而且單日載客量要夠才能解鎖下一塊。軌道和車站只能蓋在你擁有的土地上。"
            ),
            keywords: "expand tile land purchase 擴建 買地 區塊 土地"
        ),
        HelpEntry(
            "loan", .money,
            question: ("How do I borrow money?", "怎麼借錢？"),
            answer: (
                "Open Economy and choose Borrow in the Loan section. Each tap borrows one step, up to a limit, and the loan pays daily interest. Repay from the same place when you have cash. Only a managed company (not Free Play) can borrow.",
                "打開「經濟明細」，在「貸款」區按「借入」。每按一次借一個單位，有上限，貸款每天計息。有現金時可從同一處還款。只有經營模式的公司（自由模式不行）才能貸款。"
            ),
            keywords: "loan bank interest repay borrow 貸款 銀行 利息 還款"
        ),
        HelpEntry(
            "fares", .money,
            question: ("How do I set fares?", "票價怎麼設？"),
            answer: (
                "Open Economy and look at the Fares section: choose a flat fare, or a distance-based fare. People find the standard fare fair; raise it and fewer ride, lower it and more ride but each pays less. Try small changes and watch the day's income.",
                "打開「經濟明細」，在「票價」區選固定票價或依距離計費。乘客覺得標準票價合理；調高會讓搭車的人變少，調低則搭的人變多但每人付得少。小幅調整，再看當天的收入。"
            ),
            keywords: "fare price ticket 票價 漲價 降價 收費"
        ),
        HelpEntry(
            "oneTrain", .running,
            question: ("Why does my line run only one train at a time?", "為什麼我的路線一次只跑一列車？"),
            answer: (
                "A new game has Traffic control on: a train takes its whole route before it leaves, so on single track with nowhere to pass, only one train fits. Give trains somewhere to pass: open the station panel of a station in the middle and add a platform track to make a passing loop; or turn Snap to track off in Network and lay a second track 4 m or more beside the first, for double track; or add a second platform at the end stations. Turning Traffic control off at the top of Lines lets trains run regardless.",
                "新遊戲預設開啟「交通控制」：列車要先取得整段路線才會發車，所以單線又沒有地方會車時，只能跑一列。讓列車有地方會車：打開中間某站的車站面板，用「加月台軌道」做一條待避線；或在「路網」關掉「吸附軌道」，在旁邊相距 4 公尺以上鋪第二條軌道，做成雙線；或在終點站加第二股月台。在「路線」最上方關掉「交通控制」，列車也能照開。"
            ),
            keywords: "single track passing loop double one train capacity signal 單線 會車 待避 雙線 一列 列車數 上限"
        ),
        HelpEntry(
            "unassignedTrain", .running,
            question: ("What do No line and No path ahead mean?", "「未配屬路線」和「前方沒有路徑」是什麼？"),
            answer: (
                "No line: the train belongs to no line, so it carries no one and has nowhere to go; No path ahead is what such a train, or one whose track was cut, shows. Put it on a line: select the train, open Lines, pick the line and assign the train to it (or give the line a new train there). If a train on a line shows No path ahead, check that the line's track still joins all its stops.",
                "「未配屬路線」是列車不屬於任何路線，不載客也沒有地方去；這種列車，或軌道被切斷的列車，會顯示「前方沒有路徑」。把它配到路線：選取列車，打開「路線」，選一條路線，把這列車指派給它（或在那裡幫路線配一列新車）。有路線的列車還顯示「前方沒有路徑」，就檢查路線的軌道是否仍連接所有停靠站。"
            ),
            keywords: "assign unassigned no line no path stuck idle 配屬 指派 未配屬 沒有路徑 停住 不動"
        ),
        HelpEntry(
            "trafficControl", .running,
            question: ("What is traffic control (signalling)?", "什麼是號誌控制？"),
            answer: (
                "With Traffic control on, a train takes its whole route before it leaves, so two trains never share a track at once. Trains may wait for the route ahead to clear, and a busy line carries fewer trains. Turn it on or off with the switch at the top of the Lines panel.",
                "開啟「交通控制」後，列車要先取得整段路線才會發車，所以兩列車不會同時佔用同一段軌道。列車可能會等前方路線淨空，繁忙的路線能容納的列車也比較少。開關在「路線」面板的最上方。"
            ),
            keywords: "signal signalling block 號誌 閉塞 交通控制 等待"
        ),
        HelpEntry(
            "timeScale", .running,
            question: ("Why do trains look so fast? What does 600× mean?", "列車怎麼跑這麼快？600× 是什麼意思？"),
            answer: (
                "A new game runs at 600 times real time: a second on your screen is ten minutes in the game, so a high-speed train at 300 km/h crosses 50 km of map in a second. The map and the track are true to scale. To watch a train at its real speed, tap it and follow it, then tap 1× (real time) or 10× on the follow bar at the top of the map; the status bar shows the train's speed in km/h. You can also choose any speed from the speed menu beside the pause button. The game keeps the speed you chose when you stop following. If the status bar says \"falling behind\", the device cannot run the game that fast: choose a slower speed.",
                "新遊戲以真實時間的 600 倍進行：畫面上的 1 秒是遊戲裡的 10 分鐘，所以時速 300 公里的高鐵，畫面上每秒跑過 50 公里。地圖和軌道的比例是真實的。想看列車用真實的速度跑，點列車並跟隨它，再點地圖上方跟隨列的「1×」（真實時間）或「10×」；頂端的狀態列會顯示列車的時速。也可以從暫停鈕旁的速度選單選任何速度。停止跟隨後，遊戲會維持你選的速度。如果狀態列顯示「跟不上」，表示裝置跑不動這個速度，請改選慢一點的速度。"
            ),
            keywords: "speed fast slow real time 1x 10x 600x follow km/h falling behind 速度 太快 真實時間 倍速 跟隨 時速 跟不上"
        ),
        HelpEntry(
            "express", .running,
            question: ("How do I run a non-stop or a short working?", "怎麼開直達車或短程班次？"),
            answer: (
                "Open Lines, pick the line, and under Add a stopping pattern at the bottom choose the first and last stop and tap Add: a run over part of the line is a short working; switch on Non-stop to call at the two ends only. They run beside the all-stops trains, so give the line enough trains for all of them.",
                "打開「路線」，選這條路線，在最下方的「新增停站模式」選起點與終點，按「加入」：只跑其中一段就是短程班次；開啟「直達車」就只停兩端。它們與各站停車並行，所以路線要有足夠的列車都跑得動。"
            ),
            keywords: "pattern skip stop limited express non-stop short working 快車 直達車 快速列車 短程班次 越站 停站模式 通過"
        ),
        HelpEntry(
            "annualReport", .money,
            question: ("How do I read the annual report?", "怎麼看年報？"),
            answer: (
                "When a year closes, the report opens by itself: revenue against costs, profit and what the company owns and owes. Compare it with last year's. Open Economy at any time for the day, week, month and year so far.",
                "年度結算時年報會自動打開：收入、成本、利潤，以及公司的資產與負債。可以和去年比較。想隨時查看，打開「經濟明細」就能看到當日、當週、當月與今年的數字。"
            ),
            keywords: "year report statement profit 年度 報表 結算 損益"
        ),
        HelpEntry(
            "disruptions", .running,
            question: ("What are holidays, weather and typhoons?", "假日、天氣與颱風是什麼？"),
            answer: (
                "Public holidays raise passenger numbers, and typhoons and fuel price spells change them for a few days. The station master warns you days ahead. Choose how strongly they bite when you start a new game (New Game options) or later in Settings.",
                "國定假日會讓旅客增加，颱風與油價波動則會在幾天內改變客流。站長會提前幾天警告你。開始新遊戲時可以選影響的強度（新遊戲選項），之後也能在「設定」調整。"
            ),
            keywords: "holiday typhoon fuel event 連假 颱風 油價 事件 干擾"
        ),
        HelpEntry(
            "difficulty", .money,
            question: ("What do the difficulty levels change?", "難度會改變什麼？"),
            answer: (
                "Easy starts with $5,000,000 and no holidays or weather; Standard with $3,000,000 and light ones; Expert with $1,500,000 and all of them in full. Open New Game options on the start screen to change each rule separately, and to type a map seed to share a map.",
                "輕鬆從 $5,000,000 開始，沒有假日與天氣影響；標準 $3,000,000，影響較輕；達人 $1,500,000，影響完整。在開始畫面的「新遊戲選項」可以分別調整每條規則，也能輸入地圖種子來分享地圖。"
            ),
            keywords: "easy standard expert seed 輕鬆 標準 達人 種子 起始資金"
        ),
        HelpEntry(
            "saveGame", .running,
            question: ("How do I save, and where is my game?", "怎麼存檔？遊戲存在哪？"),
            answer: (
                "The game saves itself whenever you leave it, and keeps one autosave for every 15 minutes of play, the last 5. Open the game menu (the three lines at the top) to Save Game, or Save, Export or Go Back to name a save, share it as a file, or go back to an autosave of some minutes before. Continue on the start screen resumes the latest autosave, and Saved Games lists the earlier ones and your own saves.",
                "遊戲離開時會自動存檔，遊戲中每 15 分鐘也會另存一份，保留最近 5 份。打開遊戲選單（頂端的三條線）可以「儲存遊戲」，或在「另存、匯出或回到之前」裡為存檔命名、匯出成檔案，或回到幾分鐘前的自動存檔。開始畫面的「繼續」會接續最新的自動存檔，「存檔」則列出之前的自動存檔與你自己的存檔。"
            ),
            keywords: "load autosave export 讀檔 自動存檔 匯出"
        ),
        HelpEntry(
            "tutorialAgain", .running,
            question: ("How do I see the tutorial again?", "如何再看一次入門教學？"),
            answer: (
                "Open the game menu and choose Tutorial. The station master's first-line card on the start screen also starts a short tutorial game of about five minutes.",
                "打開遊戲選單，選「教學」。開始畫面上站長的第一條線卡片也會開啟約 5 分鐘的教學遊戲。"
            ),
            keywords: "intro guide 導覽 簡介 重看"
        ),
    ]
}
