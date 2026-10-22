// The help guide (ARCHITECTURE decision 177): questions players ask, with
// answers in the game's language, searchable in English and Traditional
// Chinese. A-Train Tourism has
// hint pages sorted by the problem the player has; the reference's `Ci/`
// keeps six questions of its own (`guide.metro.faq.0` to `.5` in
// `lib/ui-locales/zh-CN__q_8e57e7fa49d074d2.js`: how to create a line, add a
// node or station, move or delete a station, get trains running, extend a
// line, see the introduction again), written for its mouse and keys. Those
// six are carried over, turned into this game's touch controls and into
// Taiwan's wording; the rest are this project's own. Presentation only:
// nothing here is stored.

import GameCore

/// One question and its answer, kept in both languages for the search;
/// the guide shows the game's language only.
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

    /// What the guide shows of it in `language`: the question, then its
    /// answer, in that language only (decision 177, later). The other
    /// language's text is still searched (``matches(_:)``).
    public func shownText(in language: DisplayLanguage) -> (question: String, answer: String) {
        (question(in: language), answer(in: language))
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
                "Tap a station, then Station… on its details card (or touch and hold the station) to open the station panel; the pencil on the tag under the station opens it to rename. There you can rename it, add a platform track beside a platform, remove one platform or demolish the whole station. To move one, remove it and build it again where you want it.",
                "點車站，再按詳細卡上的「車站…」（或長按車站），打開車站面板；車站下方標籤上的鉛筆會打開面板直接改名。在面板裡可以改名、在月台旁加月台軌道、拆除其中一座月台，或拆除整個車站。要搬移車站，就拆除後在想要的位置重新蓋一座。"
            ),
            keywords: "delete rename 刪除 移動 改名"
        ),
        HelpEntry(
            "removePlatform", .building,
            question: ("How do I remove a platform or a station?", "怎麼拆除月台或車站？"),
            answer: (
                "Track with a platform on it cannot be removed until the platform goes. In Build → Network, choose Remove and tap the track: the card lists its platforms, each with a “Remove platform” button; then tap Remove Track. The station panel also has a button for each platform, and Demolish Station removes the station with all its platforms. Undo brings back what you removed.",
                "有月台的軌道要先拆掉月台才能拆。在「建設 → 路網」選「拆除」並點那段軌道，卡片會列出上面的月台，各有一個「拆除月台」按鈕，拆完再按「拆除軌道」。車站面板裡每座月台也有拆除按鈕，「拆除車站」則會連同所有月台一起拆掉。拆錯了可以按復原。"
            ),
            keywords: "remove delete demolish platform station track 拆除 刪除 月台 車站 軌道 拆月台"
        ),
        HelpEntry(
            "islandOrSide", .building,
            question: ("What is the difference between an island and a side platform?", "島式和岸式月台差在哪？"),
            answer: (
                "Only the track layout: an island platform stands between the two tracks, so the new track lies 11 m out and needs 88 m of straight, level track past each end of the platform; side platforms stand outside each track, 5 m apart, and need 50 m. Trains and passengers use both the same way. Each choice in the station panel's platform track menu shows its cost.",
                "只差在軌道配置：島式月台在兩條軌道中間，新軌道離原軌道 11 公尺，月台兩端外各要 88 公尺平直的軌道；岸式月台在兩條軌道外側，軌道相距 5 公尺，只要 50 公尺。列車和乘客用起來都一樣。車站面板的「加月台軌道」選單會列出每個選項的費用。"
            ),
            keywords: "island side platform track turnout cost 島式 岸式 月台 月台軌道 差別 費用"
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
            "simpleRules", .running,
            question: ("What are simple and realistic rules?", "簡單規則和寫實規則差在哪？"),
            answer: (
                "Simple rules, the default: trains keep their speed through curves, every train costs the same, and there is no weather or building materials. Realistic rules add these, with block signals, punctuality and crowded doors. Under simple rules a new line comes with a train, and Add a Train in the line panel puts on another, with a passing loop where the track is single. Choose in New Game Options; a game keeps its rules to the end, and Settings shows which it has.",
                "簡單規則是預設：列車過彎不減速，每種車價錢一樣，也沒有天氣與建材。寫實規則把這些加回來，再加上閉塞號誌、準點率與車門擁擠。簡單規則下，新路線會自動配一列車；在路線面板按「加開一列車」可以再加一列，單線上會自動加待避線。在「新遊戲選項」選；開始後不能更改，「設定」會顯示這一局用哪一種。"
            ),
            keywords: "simple realistic rules difficulty signals curve 簡單 寫實 規則 難度 號誌 彎道"
        ),
        HelpEntry(
            "startTrains", .running,
            question: ("How do I get trains running?", "如何讓列車開始運行？"),
            answer: (
                "Open Lines, pick the line, choose how often a train comes and tap Buy … and Start Service: the trains are bought, wait at the first station and leave in turn. A line with no train carries no one, and the station master says so. More trains mean shorter waits but higher running costs; add cars when stations are crowded and trains when they are full.",
                "打開「路線」，選這條路線，選多久來一班，按「購買…列並開始營運」：列車會買好、在第一站等候、依序發車。沒有列車的路線沒人搭，站長也會提醒你。列車越多等車越短，但營運成本越高；車站擠就加掛車廂，車站滿就加開列車。"
            ),
            keywords: "train assign 配車 發車 上線 開車"
        ),
        HelpEntry(
            "moreTrains", .running,
            question: ("How do I run more trains on a line?", "一條路線怎麼多跑幾列車？"),
            answer: (
                "Open Lines and pick the line. Under Headway and trains, choose how often a train should come, then tap the button once. The trains the line lacks are bought and set off evenly apart; if it has more than it needs, the extra ones go to no line: those waiting back to the depot, the others after their trip. If a time of day is set to more trains than the line has, a warning says so, with a button that buys the rest. On single track trains can only pass at stations, so a line holds just a few trains: to run more, build double track or passing loops (see \"Why does my line run only one train at a time?\").",
                "打開「路線」，選這條路線。在「班距與列車數」選多久來一班，再按一下按鈕。不夠的列車會自動買好，保持等間隔發車；車太多時，多的車回到未配屬：等車的收回車庫，正在跑的跑完這一趟。某個時段設定的列車比路線實際有的多時，會出現警告，按一下就補齊。單線只能在車站會車，能跑的列車有上限：要再多跑，就蓋雙線或待避線（見「為什麼我的路線一次只跑一列車？」）。"
            ),
            keywords: "more trains headway frequency add train how many dispatch 加開 多跑 班距 列車數 調度 配車 發車 補齊 上限"
        ),
        HelpEntry(
            "crowdedButLowLoad", .running,
            question: ("Why is my station full while the peak load is low?", "車站客滿，尖峰載客率卻不高，為什麼？"),
            answer: (
                "A station is full at 4,000 waiting. Each of them waits for one line and one way and boards only a train that stops where they are going; people changing trains wait there too. So one way of one line can fill the station while the other trains leave part empty. The peak load is the fullest departure of the day, not the average. When a line has closed for the night its passengers wait for the first train, so a station can be full overnight. Open the station panel: it lists who waits for each line and way. Run more trains on the busiest one, lengthen its service hours, or build a line to where they are going.",
                "候車達 4,000 人時車站就客滿。每位乘客只等一條路線的一個方向，只上會停他目的地的車；轉乘的乘客也在站內等。所以可能某條路線的某個方向就把車站擠滿，其他列車卻沒坐滿。尖峰載客率是當天最滿的那一班，不是平均。路線收班後，乘客會留在站內等首班車，所以半夜車站也可能是滿的。打開車站面板，會依路線和方向列出候車人數；在最多人等的那條加開列車、延長營運時間，或開一條到他們目的地的路線。"
            ),
            keywords: "full crowded station waiting peak load transfer closed overnight 客滿 擁擠 滿了 候車 載客率 尖峰 轉乘 收班"
        ),
        HelpEntry(
            "whyLosing", .money,
            question: ("Why does my line lose money?", "為什麼我的路線會虧錢？"),
            answer: (
                "Usually the stations are too close together and too few people live near them, while the train costs the same to run. Tap Data at the bottom to see the day's fares against running costs. Fixes: extend the line to a bigger town, build stations where more people live, use fewer or shorter trains, and check the fares. A short first line often loses money at first; the station master reports the daily loss in the first month.",
                "通常是車站太近、附近的人太少，列車的營運成本卻一樣。按底部的「資料」可以看每天的票價收入和營運成本。解法：把路線延伸到更大的城鎮、在人口多的地方蓋站、減少列車或縮短編組、檢查票價。起步的短線一開始常常虧錢；頭一個月站長會告訴你每天虧多少。"
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
                "The blocks are the town's own buildings, coloured by what they are for: green homes, blue shops, orange offices, purple industry and warehouses, salmon-red public buildings (schools, offices of the state), teal sights and leisure. Flat beige ground is farmland and flat pale green a park. The taller a block stands, the more people live or work there. What you build is warm yellow, like your stations, with a symbol for what it is (a house, a shop, an office tower). Map Layers shows the same uses as a layer.",
                "地圖上的方塊是城鎮自己的建物，依用途上色：綠色是住宅、藍色是商業、橘色是辦公、紫色是工業物流、鮭紅色是公共設施（學校、機關）、青綠色是觀光休閒。平的米色是農地，平的淡綠色是公園。方塊越高，住或工作的人越多。你自己蓋的建物和車站一樣是暖黃色，上面的圖示表示種類（住宅、商店、辦公大樓等）。「地圖圖層」也能用圖層看同樣的用途。"
            ),
            keywords: "colour color legend block building land use green blue yellow 顏色 圖例 方塊 建物 用途 住宅 商業 辦公 工業 黃色 自己蓋"
        ),
        HelpEntry(
            "materials", .city,
            question: ("What are building materials?", "建材是什麼？"),
            answer: (
                "Towns need building materials to grow, as in the real world. Build a freight yard to send materials (in the station panel's Freight section: tap a station, then Station… on its details card), give the station near the town a yard too, and the town grows at full speed. A freight line is an ordinary line switched to Freight line in Lines; it needs no special trains: any train carries \(Freight.tonsPerCar) t a car. A town short of materials grows slowly, and the station master says which one; tap its bubble on the map to open that station. A new game can turn this rule off in its options.",
                "城市和現實一樣需要建材才能成長。蓋一座貨運場出建材（在車站面板的「貨運」：點車站，再按詳細卡上的「車站…」），城鎮附近的車站也蓋一座，城市才能全速成長。貨運路線就是在「路線」裡把一條路線打開「貨運路線」，不需要特別的貨車：任何列車每節載 \(Freight.tonsPerCar) 噸。缺建材的城市成長很慢，站長會告訴你是哪一座；點地圖上「缺建材」的泡泡就會打開那座車站。新遊戲的選項可以關掉這個規則。"
            ),
            keywords: "freight yard material cargo 貨運 貨運場 材料"
        ),
        HelpEntry(
            "buyMap", .building,
            question: ("How do I buy more of the map?", "怎麼買地圖？"),
            answer: (
                "On a map that is bought tile by tile, tap Expand Map at the bottom left of the map (put the build tools away first; while building, the message about land not yet yours has the same button), then tap a tile next to one you own. The price depends on how many tiles you own, and you must have carried enough riders in a day to unlock the next. Track and stations can only be built on land you own.",
                "在分區購買的地圖上，按地圖左下角的「擴建地圖」（先收起建設工具；建造時跳出「這塊地還不是你的」，旁邊也有同一顆鈕），再點選和已擁有區塊相鄰的一塊。價格依你已擁有的區塊數而定，而且單日載客量要夠才能解鎖下一塊。軌道和車站只能蓋在你擁有的土地上。"
            ),
            keywords: "expand tile land purchase 擴建 買地 區塊 土地"
        ),
        HelpEntry(
            "buyRealLine", .building,
            question: ("How do I buy a real branch line?", "怎麼收購真實支線？"),
            answer: (
                "On a real-world map, open Lines: Real lines for sale lists the TRA branch lines whose stations are all on the map, such as the Pingxi or Jiji Line. Tap one to see its price; it comes with its track, stations, trains and real timetable. A station on such a line has the same button at the top of its panel. When none is listed, the line under the heading says why.",
                "在實景地圖上打開「路線」，「可收購的真實路線」會列出車站都在地圖上的臺鐵支線，例如平溪線、集集線。點一條看價格，買下時軌道、車站、列車和真實班次一起過來。這種支線上的車站，車站面板最上面也有同一顆鈕。一條都沒有列出時，標題下面那一行會說明原因。"
            ),
            keywords: "buy acquire purchase real branch line TRA Pingxi Jiji Neiwan 收購 真實 支線 臺鐵 平溪線 集集線 內灣線 買線"
        ),
        HelpEntry(
            "loan", .money,
            question: ("How do I borrow money?", "怎麼借錢？"),
            answer: (
                "Tap Data at the bottom and choose Borrow in the Loan section, just under Today. Each tap borrows one step, up to a limit, and the loan pays daily interest. Repay from the same place when you have cash. Only a managed company (not Free Play) can borrow.",
                "按底部的「資料」，在「今天」下面的「貸款」區按「借入」。每按一次借一個單位，有上限，貸款每天計息。有現金時可從同一處還款。只有經營模式的公司（自由模式不行）才能貸款。"
            ),
            keywords: "loan bank interest repay borrow 貸款 銀行 利息 還款"
        ),
        HelpEntry(
            "fares", .money,
            question: ("How do I set fares?", "票價怎麼設？"),
            answer: (
                "Tap Data at the bottom and look at the Fares section: choose a flat fare, or a distance-based fare. People find the standard fare fair; raise it and fewer ride, lower it and more ride but each pays less. Try small changes and watch the day's income.",
                "按底部的「資料」，在「票價」區選固定票價或依距離計費。乘客覺得標準票價合理；調高會讓搭車的人變少，調低則搭的人變多但每人付得少。小幅調整，再看當天的收入。"
            ),
            keywords: "fare price ticket 票價 漲價 降價 收費"
        ),
        HelpEntry(
            "trackNumbers", .running,
            question: ("Where are the track numbers, and which track does a route take?", "軌段編號在哪裡？進路會走哪一條軌道？"),
            answer: (
                "Every stretch of track between two junctions has a number (Track #7). Tap a track with the select tool to see its number, or zoom in close: the numbers appear on the track. In Lines, each leg of a line (A → B) has a route menu: Automatic lets the trains find their own way, or pick a platform or a whole path by its track numbers. Tap the map button beside the leg to show it on the map: the path is outlined with arrows the way the trains go and the number of each track along it; inside the menu, Show on Map previews a choice before you pick it. A line's colour on the map also has arrows where it runs one way only, so on double track you can see which track each way takes.",
                "兩個道岔或端點之間的每一段軌道都有編號（軌段 #7）。用「選取」工具點軌道就看得到它的編號，或把地圖拉近，軌道上會標出編號。在「路線」裡，路線的每一段（A → B）都有進路選單：「自動選路」讓列車自己找路，也可以指定月台或整條路徑（用軌段編號表示）。點那一段旁邊的地圖按鈕，就會在地圖上框出這條路徑，箭頭是列車行進的方向，沿途標出每個軌段的編號；選單裡的「先在地圖上看」可以在選定之前預覽每個選項。地圖上路線的顏色在只走單一方向的地方也有箭頭，蓋了雙線時就看得出每個方向走哪一條軌道。"
            ),
            keywords: "track number route path platform double track arrow direction 股道 軌段 編號 進路 雙線 方向 箭頭 月台"
        ),
        HelpEntry(
            "oneTrain", .running,
            question: ("Why does my line run only one train at a time?", "為什麼我的路線一次只跑一列車？"),
            answer: (
                "A new game has Traffic control on: a train takes its whole route before it leaves, so on single track with nowhere to pass, only one train fits. Give trains somewhere to pass: open the station panel of a station in the middle and add a platform track to make a passing loop; or turn Snap to track off in Network and lay a second track 4 m or more beside the first, for double track; or add a second platform at the end stations. Turning Traffic control off lets trains run regardless: in Lines, switch on Advanced, and the switch is at the bottom.",
                "新遊戲預設開啟「交通控制」：列車要先取得整段路線才會發車，所以單線又沒有地方會車時，只能跑一列。讓列車有地方會車：打開中間某站的車站面板，用「加月台軌道」做一條待避線；或在「路網」關掉「吸附軌道」，在旁邊相距 4 公尺以上鋪第二條軌道，做成雙線；或在終點站加第二股月台。關掉「交通控制」，列車也能照開：在「路線」打開「進階」，開關在最下面。"
            ),
            keywords: "single track passing loop double one train capacity signal 單線 會車 待避 雙線 一列 列車數 上限"
        ),
        HelpEntry(
            "depot", .running,
            question: ("What is a depot, and how do I build one?", "機廠是什麼？怎麼蓋？"),
            answer: (
                "A depot is where a line keeps its trains out of service: they leave it before the first train, go back after the last or when fewer trains are needed, and pay only upkeep while they stand there. To build one, open Network, choose Depot, tap the end of a track and choose how many sidings: they are laid with their turnouts and a depot with a platform on each. Or make a station no line stops at a depot on its station panel. Then open Lines, pick the line and tick its depots: one or several. A depot takes no passengers, and no line runs over its sidings. On the map a train leaving shows a plate with the garage on the left, one going in the garage on the right; the fleet list and the line panel say how many stand In depot.",
                "機廠是路線停放列車的地方：首班前出庫、收班後或需要的車變少時入庫，停在機廠只付保養費。要蓋機廠：打開「路網」，選「機廠」，點軌道的盡頭，選要幾股，就會鋪好停車線、道岔，和每股都有月台的機廠。也可以在沒有路線停靠的車站面板按「設為機廠」。然後打開「路線」，選這條路線，勾選它的機廠，可以勾好幾個。機廠不載客，路線也不能走它的停車線。地圖上，出庫的列車頭上有一塊車庫在左的小方牌，入庫的車庫在右；車隊清單和路線面板會寫幾列「在庫」。"
            ),
            keywords: "depot yard siding garage out of service pull out pull in 機廠 車庫 停車線 出庫 入庫 在庫 回送"
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
                "With Traffic control on, a train takes its whole route before it leaves, so two trains never share a track at once. Trains may wait for the route ahead to clear, and a busy line carries fewer trains. Turn it on or off in the Lines panel: switch on Advanced, and the switch is at the bottom.",
                "開啟「交通控制」後，列車要先取得整段路線才會發車，所以兩列車不會同時佔用同一段軌道。列車可能會等前方路線淨空，繁忙的路線能容納的列車也比較少。開關在「路線」面板：打開「進階」，在最下面。"
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
                "When a year closes, the report opens by itself: revenue against costs, profit and what the company owns and owes. Compare it with last year's. Tap Data at the bottom at any time for the day, week, month and year so far (under More reports and settings, when they are folded).",
                "年度結算時年報會自動打開：收入、成本、利潤，以及公司的資產與負債。可以和去年比較。想隨時查看，按底部的「資料」就能看到當日、當週、當月與今年的數字（收起時在「更多報表與設定」裡）。"
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
        HelpEntry(
            "reportProblem", .running,
            question: ("Where do I send a problem or an idea?", "問題或意見要送到哪裡？"),
            answer: (
                "Open the game menu (the three lines at the top), choose More, then Report a Problem. It writes a note with the version, your device and what is in the game, for Mail, Messages or any app you choose; you may also attach the game's save and what you did since, so the problem can be played again. Nothing is sent until you send it. Settings has the same button.",
                "打開遊戲選單（頂端的三條線），選「更多」→「回報問題」。它會寫好一則附上版本、裝置與這局狀態的訊息，由你選擇用郵件、訊息或其他 App 傳送；也可以附上這局的存檔和之後做過的事，讓問題可以重現。你按下傳送前不會送出任何東西。設定頁也有同一個按鈕。"
            ),
            keywords: "report bug problem feedback idea suggestion send 回報 問題 意見 建議 錯誤 送"
        ),
    ]
}
