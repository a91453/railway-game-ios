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
        // 121.
        Entry(
            id: "2026-11-08-121",
            items: [
                Line(
                    english: "Track building lets you raise or lower the end of the track yourself for bridges and tunnels, and when a track is refused it offers a height that works.",
                    chinese: "鋪軌時可以自己調終點的高度（橋、隧道），被拒絕時直接給你一個能過的高度。"
                ),
                Line(
                    english: "On a single line with three trains, one tap adds the passing loops it needs.",
                    chinese: "單線上跑三列車時，一鍵加齊需要的待避線。"
                ),
                Line(
                    english: "Track numbers on the map keep clear of switches and station names, and can be turned off in the layers list.",
                    chinese: "地圖上的軌道編號避開道岔和站名，可在圖層清單關掉。"
                ),
                Line(
                    english: "The layers bar on the map can be folded away.",
                    chinese: "地圖上的圖層列可以收起來。"
                ),
                Line(
                    english: "The Collection now shows the ferries as 3D ships, and has a new Cable Car page.",
                    chinese: "圖鑑的渡輪改用 3D 船展示，並新增纜車頁。"
                ),
                Line(
                    english: "The 3D map shows eleven real station buildings (Taiwan Railway and high-speed rail) in their real places, with the tracks left clear and windows lit at night.",
                    chinese: "3D 地圖多了 11 個真實站房外觀（臺鐵與高鐵），照真實位置放，軌道讓開，晚上亮窗。"
                ),
                Line(
                    english: "A new game opens on the first town, and the help page's search box no longer covers the first entry.",
                    chinese: "新遊戲開場直接框住第一座城鎮；說明頁的搜尋框不再蓋住第一條。"
                ),
                Line(
                    english: "A heat map now outlines the tracks so they stay visible.",
                    chinese: "熱圖開著時，軌道多一圈白邊，看得到。"
                ),
            ],
            fixes: [
                Line(
                    english: "The tutorial card no longer covers buttons, banners or the clock, and the tutorial now says to press \u{2715} to finish building.",
                    chinese: "教學卡片不再擋住按鈕、通知和時鐘，教學也改成「按 ✕ 結束建造」。"
                ),
                Line(
                    english: "Notices at the top of the map keep their width when a side panel is open, the speed warning shows in full, and income pop-ups fade out before the status bar.",
                    chinese: "開側面板時地圖上緣的通知不再被擠窄，倍速提示完整顯示，收入飄字在狀態列前淡出。"
                ),
                Line(
                    english: "The \"where people are\" legend is no longer hidden behind the station master.",
                    chinese: "「哪裡人多」圖例不再被站務員蓋住。"
                ),
                Line(
                    english: "After you buy a real line, the 2D map runs smoother, and the line page opens with less stutter.",
                    chinese: "收購真實路線後 2D 地圖比較順，路線頁打開不再卡一下。"
                ),
                Line(
                    english: "Pausing, resuming or changing speed no longer makes the game stall on the hour.",
                    chinese: "暫停、繼續或換速度，整點不再卡一下。"
                ),
                Line(
                    english: "Three trains on one single line no longer lock up.",
                    chinese: "單線上三列車不再卡死。"
                ),
                Line(
                    english: "A depot no longer shows \"crowded\" or a service area, and the service-area switch now really turns it off.",
                    chinese: "機廠不再顯示「擠」和服務圈，服務圈開關關了就真的關。"
                ),
                Line(
                    english: "On the high-speed demo, the Liujia depot now sits north of the Touqian River instead of over the water.",
                    chinese: "高鐵示範的六家基地收在頭前溪北岸，不再蓋在河上。"
                ),
            ]
        ),
        // 120.
        Entry(
            id: "2026-11-07-120",
            items: [
                Line(
                    english: "The tracks into a depot you build now fan out symmetrically, like a real train yard.",
                    chinese: "自己蓋的機廠，進出的分岔改成像真實車場的對稱扇形。"
                ),
                Line(
                    english: "The high-speed demo's northern end now has Nangang's stabling sidings and the Liujia depot beside Hsinchu, laid out as in real life.",
                    chinese: "高鐵示範北端：南港留置線和新竹旁的六家基地，照真實配置。"
                ),
                Line(
                    english: "On the Kaohsiung Circular Light Rail, the depot's tracks now run in a strip along the line like the real Qianzhen depot, so fewer empty trains run.",
                    chinese: "高雄環狀輕軌的機廠照真實前鎮機廠沿線排成一條帶，空車少跑。"
                ),
                Line(
                    english: "The 3D map shows road tunnel mouths, and lights glow at night.",
                    chinese: "3D 地圖多了公路隧道口，晚上的燈有光暈。"
                ),
            ],
            fixes: [
                Line(
                    english: "At 10x speed game time keeps up, even with trains waiting at stations to depart.",
                    chinese: "10 倍速時遊戲時間跟得上，有車在站上等出發也不再拖慢。"
                ),
                Line(
                    english: "Correction to the last build: the cab window view only now glides smoothly instead of jerking, at 10x and at 1x.",
                    chinese: "更正上一版：車窗視角走走停停，這一版才真的改好，10 倍速和 1 倍速都滑行連貫。"
                ),
                Line(
                    english: "Following a train in 3D no longer drops you back to 2D after a short while.",
                    chinese: "3D 跟車不會沒多久自己跳回 2D。"
                ),
                Line(
                    english: "The 3D map uses less memory.",
                    chinese: "3D 地圖比較省記憶體。"
                ),
                Line(
                    english: "The Wenhu Line runs late less often in realistic mode.",
                    chinese: "文湖線擬真模式誤點變少。"
                ),
                Line(
                    english: "Vehicle dispatch on the Kaohsiung Circular Light Rail is more accurate.",
                    chinese: "高雄環狀輕軌的車輛調度更準。"
                ),
            ]
        ),
        // 119.1.
        Entry(
            id: "2026-11-07-119-1",
            items: [
                Line(
                    english: "The Kaohsiung Circular Light Rail can now be bought: it follows the real tracks, has a light rail depot, and keeps running every trip with traffic control off.",
                    chinese: "高雄環狀輕軌開放收購：照真實股道鋪、有輕軌機廠，行車控制關掉也不漏班。"
                ),
                Line(
                    english: "Cable car cabins now change with the place: near Sun Moon Lake you get the Sun Moon Lake cabin, and the cabin glass is clear.",
                    chinese: "纜車吊廂照地點換，日月潭附近是日月潭吊廂，玻璃改透明。"
                ),
                Line(
                    english: "Real-world buildings along a street now show arcade pillars, window grilles, air conditioners, upright signs and rooftop add-ons.",
                    chinese: "實景建物沿街立面多了騎樓柱、鐵窗、冷氣機、直立招牌和頂樓加蓋。"
                ),
                Line(
                    english: "The Changhua roundhouse now has locomotives parked in its stalls.",
                    chinese: "彰化扇形車庫的庫位停著機車。"
                ),
            ],
            fixes: [
                Line(
                    english: "Laying track or adding a platform on the 3D map now redraws only the area around it, so it feels smoother.",
                    chinese: "3D 地圖鋪軌、加月台只重畫周圍，操作更順。"
                ),
                Line(
                    english: "The 3D map uses less memory.",
                    chinese: "3D 地圖比較省記憶體。"
                ),
                Line(
                    english: "The cab window view no longer jerks along in fits and starts.",
                    chinese: "車窗視角走走停停的問題修好了。"
                ),
                Line(
                    english: "After you rebuild a real-world line, the whole scene updates with it.",
                    chinese: "改建實景線後，整片場景跟著更新。"
                ),
                Line(
                    english: "The picture no longer jumps after you pause.",
                    chinese: "暫停後畫面不再跳一下。"
                ),
                Line(
                    english: "Small fixes to the sights panel and a few other spots.",
                    chinese: "觀光景點面板等幾處小修。"
                ),
            ]
        ),
        // 118.1.
        Entry(
            id: "2026-11-06-118-1",
            items: [
                Line(
                    english: "On the Wenhu Line you buy, the Muzha and Neihu depots are laid out like the real yards, with an extra track in and out of the depot, and buying costs a little less.",
                    chinese: "收購的文湖線，木柵、內湖機廠照真實車場鋪，多一條進出機廠的線，收購也便宜一點。"
                ),
                Line(
                    english: "On the Taoyuan Airport MRT you buy, express trains stop only at the real express stations, and Chang Gung Memorial Hospital has passing tracks on both sides.",
                    chinese: "收購的桃園機場捷運，直達車照真實的站停車，長庚醫院兩側有待避線。"
                ),
                Line(
                    english: "With traffic control on, spare trains that cannot depart and block the way go back to the depot first.",
                    chinese: "行車控制下多出來、發不出去又擋路的空車會先回機廠。"
                ),
            ],
            fixes: [
                Line(
                    english: "Ferry mode now tints shores far from any station, such as Cijin and Bali, light blue, so you can build a pier there.",
                    chinese: "旗津、八里這些離車站遠的岸邊，渡輪模式也會標出淺藍色，可以直接蓋碼頭。"
                ),
                Line(
                    english: "Fixed the game freezing or crashing while the sights panel was open.",
                    chinese: "觀光景點面板開著時遊戲會卡住、當掉，修好了。"
                ),
                Line(
                    english: "Where a highway ramp meets the bridge deck, the road surface now lines up instead of overlapping.",
                    chinese: "高速公路匝道接上橋面的地方，路面高度對齊，不再互相交疊。"
                ),
                Line(
                    english: "On a large network, starting a line or building a station or track no longer stalls for a moment.",
                    chinese: "路網大了以後，開路線、蓋車站、蓋軌道不再卡一下。"
                ),
            ]
        ),
        // 115.1.
        Entry(
            id: "2026-11-06-115-1",
            items: [
                Line(
                    english: "In ferry mode the shore squares where a pier can go are tinted light blue, and a tap near the shore lands on the nearest one. Tap too far away and you are told which way the shore is.",
                    chinese: "渡輪模式把能蓋碼頭的岸邊格子塗成淡藍；點在岸邊附近就會落在最近的一格，點太遠會告訴你岸在哪個方向。"
                ),
                Line(
                    english: "Real trains on the 3D map now use the platform tracks they are scheduled for, and side-by-side viaducts no longer leave a gap between them.",
                    chinese: "3D 地圖的真實列車會進被排定的月台股道，並排的高架橋面中間也不再漏縫。"
                ),
                Line(
                    english: "Idle mode now also follows the real trains running on the map, with the train's name and destination shown faintly in the corner.",
                    chinese: "放空模式也會跟著地圖上跑的真實列車，角落淡淡寫出車名與往哪裡。"
                ),
                Line(
                    english: "The Xiaobitan Branch Line you buy is now a single track with one train shuttling back and forth, and costs less.",
                    chinese: "新買的小碧潭支線照真實鋪成單線，一列車來回，收購價也便宜了。"
                ),
                Line(
                    english: "Building a bigger station elsewhere no longer leaves sights such as Jiji and Pingxi with no tourists.",
                    chinese: "別處蓋了大站，集集、平溪這類景點也不會再沒有觀光客。"
                ),
            ],
            fixes: [
                Line(
                    english: "Fixed a crash that could happen when opening the real-world map or the high-speed demo.",
                    chinese: "修正開啟真實世界地圖或高鐵示範時可能閃退的問題。"
                ),
                Line(
                    english: "Taking a stop off a line you bought now also takes away that stop's regular riders.",
                    chinese: "從買下的支線拿掉一站後，那一站的常客也跟著不見。"
                ),
                Line(
                    english: "Cable cars and ferries no longer connect to a depot.",
                    chinese: "纜車與渡輪不再接到機廠。"
                ),
                Line(
                    english: "The advice to shorten a train to fewer cars now gives a number that fits the platform.",
                    chinese: "列車太長時「減到幾節」的提示，節數現在停得進月台。"
                ),
            ]
        ),
        // 114.1.
        Entry(
            id: "2026-11-05-114-1",
            items: [
                Line(
                    english: "The Taoyuan Airport MRT joins the real maps: you can buy it and run its timetable.",
                    chinese: "實景地圖有了桃園機場捷運，可以買下來、照時刻表營運。"
                ),
                Line(
                    english: "On the 3D map you can follow a ferry: from the bridge, from a cabin window, from behind and above, or from the side.",
                    chinese: "3D 地圖可以跟隨渡輪：駕駛台、船艙窗、上後方、旁邊四種視角。"
                ),
                Line(
                    english: "At 600× speed the game runs more smoothly, and the pause on the hour is gone.",
                    chinese: "600 倍速下跑得更順，整點不再頓一下。"
                ),
                Line(
                    english: "On the 3D street scene, cars stop at the stop line for a red light and pedestrians wait for the green walking figure.",
                    chinese: "3D 街景裡，車會在停止線前等紅燈，行人會等小綠人亮了才走。"
                ),
                Line(
                    english: "A branch line you buy now brings regular riders you can see: the buying card shows about how many a day.",
                    chinese: "收購的支線會帶來看得見的常客；收購卡上寫著沿線的常客每天約多少人。"
                ),
                Line(
                    english: "The 3D map of Kaohsiung harbour now has the Kaohsiung Music Center.",
                    chinese: "3D 地圖的高雄港多了高雄流行音樂中心。"
                ),
            ],
            fixes: [
                Line(
                    english: "Fixed crashes when adding a line or a station, and when drawing track.",
                    chinese: "修正新增路線、車站與畫軌道時可能閃退的問題。"
                ),
                Line(
                    english: "Fixed a crash that could happen while moving around the 3D map.",
                    chinese: "修正在 3D 地圖移動時可能閃退的問題。"
                ),
            ]
        ),
        // 113.1.
        Entry(
            id: "2026-11-05-113-1",
            items: [
                Line(
                    english: "The Bus button is now Transit, with Bus and Ferry inside. Lay a ferry route between two piers; the demo has Tamsui to Bali and Gushan to Cijin.",
                    chinese: "「公車」鈕改叫「接駁」，裡面分公車、渡輪；可以開渡輪航線，示範有淡水—八里、鼓山—旗津。"
                ),
                Line(
                    english: "Settings' Garage is now the Collection, with a page for trains and a page for ferries.",
                    chinese: "設定的「車庫」改叫「圖鑑」，分列車、渡輪兩頁。"
                ),
                Line(
                    english: "Tourists ride ferries, buses and cable cars to sights no station reaches. Bali has a new sight, the Bali Ferry Pier old street, and the Maokong Gondola meets MRT Taipei Zoo.",
                    chinese: "觀光客會搭渡輪、公車、纜車去車站走不到的景點；八里多了「八里渡船頭老街」，貓空纜車接捷運動物園。"
                ),
                Line(
                    english: "On the 3D map you can follow a cable car cabin: out of its window, from behind and above, or from the side.",
                    chinese: "3D 地圖可以跟隨纜車吊廂：窗外、上後方、旁邊三種視角。"
                ),
                Line(
                    english: "On the 3D map, ferries sail between Tamsui and Bali and between Gushan and Cijin on their timetable, and the piers have a waiting shelter and a gangway.",
                    chinese: "3D 地圖上，淡水—八里、鼓山—旗津的渡輪依班次往返；碼頭有候船棚與跳板。"
                ),
                Line(
                    english: "The 3D map of Kaohsiung harbour now has the Great Harbor Bridge and the Gushan and Cijin ferry terminals.",
                    chinese: "3D 地圖的高雄港多了大港橋與鼓山、旗津輪渡站。"
                ),
                Line(
                    english: "Following a bus, its window view looks out the right side. Following a train or bus at a stop, you can switch to the view from the station.",
                    chinese: "跟隨公車的「車窗」視角改看右側；跟隨列車或公車停站時，可以直接切到「從車站看」。"
                ),
                Line(
                    english: "Following a cable car cabin, buildings in the way of the camera turn see-through.",
                    chinese: "跟隨纜車吊廂時，擋住鏡頭的建築會變半透明。"
                ),
                Line(
                    english: "Placing a train, you choose its platform; if it does not fit, you are told why and what to change. With no station chosen, the button asks you to tap one first.",
                    chinese: "放車時可以選月台；放不下會說出原因和怎麼改；還沒選車站時，按鈕會請你先點地圖上的車站。"
                ),
                Line(
                    english: "A train waiting at a station with no line can be assigned to the line from its page.",
                    chinese: "停在站上、沒有路線的車，可以從路線頁配屬給這條線。"
                ),
                Line(
                    english: "On an iPhone held sideways, a details card keeps its main button in view, and the car count and platform sit just above Place Here.",
                    chinese: "iPhone 橫放時，詳細卡片的主要按鈕一直看得到；放車的車廂數和月台就在「放在這裡」上面。"
                ),
                Line(
                    english: "The Network tool's mode row scrolls sideways and keeps the chosen mode in view.",
                    chinese: "「路網」工具的模式列可以左右滑，選中的模式會留在畫面內。"
                ),
            ],
            fixes: [
                Line(
                    english: "City bus routes no longer link to a depot, so riders do not pile up at the Muzha depot.",
                    chinese: "市區公車的轉乘不再接到機廠，木柵機廠不會多出一堆乘客。"
                ),
                Line(
                    english: "Fixed a crash when picking a new line's second station.",
                    chinese: "修正新增路線時選第二個車站就閃退的問題。"
                ),
                Line(
                    english: "A train between runs can take a free berth, so trains no longer wait on each other at a terminal.",
                    chinese: "兩趟之間的列車可以先進空著的股道，終點站不再互相等。"
                ),
            ]
        ),
        // 112.1.
        Entry(
            id: "2026-11-04-112-1",
            items: [
                Line(
                    english: "New stations are named after nearby schools, hospitals, parks and shopping areas. Under the name box, tap a suggestion such as a bus stop, a junction or a road to use it.",
                    chinese: "新車站會用附近的學校、醫院、公園、商圈取名；取名欄下還有公車站牌、路口、路名可以一點就換。"
                ),
                Line(
                    english: "Drawing a new line on the map is less cluttered: the buttons and reminders that were in the way fold away, and the line summary shows once.",
                    chinese: "在地圖上畫新路線時畫面清爽了：礙事的按鈕和提醒會收起，路線摘要只出現一次。"
                ),
                Line(
                    english: "A depot you build joins the line it connects to; with several lines nearby, buttons let you choose.",
                    chinese: "鋪好的機廠會自動接上相連的路線；附近有好幾條線時，會給按鈕讓你選。"
                ),
                Line(
                    english: "Station pages can add a crossover between the two tracks of an old double-track station, and Make double track adds crossovers beside the stations. A third train now fits.",
                    chinese: "舊的複線車站，車站面板可以加渡線；「升級為複線」也會在車站旁加渡線，第三列車放得進去。"
                ),
                Line(
                    english: "Bought metro and light rail lines, such as the Wenhu Line, now run on the right, on the track of their own direction.",
                    chinese: "買下文湖線等捷運、輕軌後，列車改走自己方向那條軌道，靠右行駛。"
                ),
                Line(
                    english: "Taiwan's named festivals are on the real maps: Dajia Mazu, the Pingxi lanterns, New Year's Eve at Taipei 101 and the Mid-Autumn Festival bring extra riders to nearby stations. Mazu, the lanterns and Mid-Autumn follow the lunar calendar.",
                    chinese: "實景地圖有了台灣節慶：大甲媽祖、平溪天燈、101 跨年、中秋讓附近車站多出乘客；媽祖、天燈、中秋依農曆。"
                ),
                Line(
                    english: "On the 3D map you can follow a bus: tap a bus, or use Follow a Bus on a line card or a stop. Buses are drawn even with street scenes off.",
                    chinese: "3D 地圖可以跟隨公車：點公車，或用路線卡、站牌的「跟隨公車」；街景關著也看得到公車。"
                ),
                Line(
                    english: "Following a train has a window view: look out of a side window from the middle of the train.",
                    chinese: "跟隨列車多了「車窗」視角：坐在車廂中段，從側邊車窗往外看。"
                ),
                Line(
                    english: "Cable cars and their stations are on the 3D map, with cabins riding the ropes.",
                    chinese: "3D 地圖有纜車、塔柱和站房，吊廂沿著纜線行駛。"
                ),
                Line(
                    english: "The 3D map has the Changhua Roundhouse beside its turntable.",
                    chinese: "3D 地圖的彰化扇形車庫上線了，連著轉車台。"
                ),
                Line(
                    english: "The Network tool has a cable car mode: lay a cable, set its stops and read each cable car's card. The real Taipei map has a Maokong Gondola demo.",
                    chinese: "「路網」工具多了纜車模式：拉纜線、設站，每條纜車有自己的卡片；真實台北有貓空纜車示範。"
                ),
                Line(
                    english: "The Report a Problem page says where to send your report.",
                    chinese: "「回報問題」頁寫清楚了要寄到哪裡。"
                ),
            ],
            fixes: [
                Line(
                    english: "Trains stop inside the platform instead of poking half a car past its end. If a train is longer than a platform, you are told which station and how to fix it.",
                    chinese: "列車停站時整列停在月台內，不再伸出半節；列車比月台長時會告訴你是哪一站。"
                ),
                Line(
                    english: "The \"train stuck\" warning no longer flashes on the Xinbeitou and Liujia lines when nothing is stuck.",
                    chinese: "新北投、六家線不再無端閃出「列車卡住」。"
                ),
                Line(
                    english: "Trains stuck facing each other at the end of a double track now get through, instead of waiting all day.",
                    chinese: "複線終點兩列車互相卡住時會自己解開，不再整天不動。"
                ),
                Line(
                    english: "With Reduce Motion on, panels fold and scroll without animation, and VoiceOver can pick a train in the fleet list.",
                    chinese: "開「減少動態效果」時，面板收合與捲動不再有動畫；VoiceOver 可以選到車隊裡的列車。"
                ),
                Line(
                    english: "On iOS 26, floating panels over the map follow the screen's rounded corners.",
                    chinese: "iOS 26 上，浮在地圖上的面板角落更貼合螢幕圓角。"
                ),
            ]
        ),
        // 111.1, with what 108.1, 109.1 and 110.1 brought: none had an entry
        // here when it was released.
        Entry(
            id: "2026-11-04-111-1",
            items: [
                Line(
                    english: "The first time you buy a model of train, a card shows its first set coming ashore in Taiwan.",
                    chinese: "第一次買到某一款車時，會跳出一張卡片，看它的第一批車在港口上岸。"
                ),
                Line(
                    english: "Following a diesel train, you hear its engine idle at stations, roar as it pulls away and settle as it coasts.",
                    chinese: "跟隨柴油車時聽得到引擎聲：停站時怠轉，起步時加速變大聲，滑行時回到怠轉。"
                ),
                Line(
                    english: "The Wenhu Line can be bought on the real maps of Taipei, New Taipei and Taoyuan, with the Muzha depot by the zoo.",
                    chinese: "台北、新北、桃園的真實地圖可以收購捷運文湖線，連同動物園旁的木柵機廠。"
                ),
                Line(
                    english: "On the 3D map, Wenhu Line trains are the real VAL256 and Type 370 cars.",
                    chinese: "3D 地圖的文湖線換成真車的樣子：VAL256 和 370 型兩款都會跑。"
                ),
                Line(
                    english: "On the 3D map, Taoyuan Airport MRT commuter trains are the blue Type 1000 and express trains the purple Type 2000.",
                    chinese: "3D 地圖的機場捷運：普通車是藍色 1000 型，直達車是紫色 2000 型。"
                ),
                Line(
                    english: "TRA local trains now include the eight-car EMU700.",
                    chinese: "台鐵區間車多了八節的 EMU700。"
                ),
                Line(
                    english: "The Sea Breeze and Mountain Mist trains have their own rebuilt look on the 3D map.",
                    chinese: "3D 地圖的海風號、山嵐號換成專屬的改造車外觀。"
                ),
                Line(
                    english: "Drag up with two fingers on the 3D map to tilt the camera further, up to 60 degrees.",
                    chinese: "3D 地圖兩指往上拖，鏡頭可以再斜下去看街景，最多到 60 度。"
                ),
                Line(
                    english: "The 3D map has the Shin Kong Life Tower in Taipei and the 85 Sky Tower in Kaohsiung.",
                    chinese: "3D 地圖放上台北新光摩天大樓和高雄 85 大樓。"
                ),
                Line(
                    english: "Shadows on the 3D map have softer, finer edges.",
                    chinese: "3D 地圖的影子邊緣更柔、更細。"
                ),
                Line(
                    english: "A line bought before its depot came with it can add the real depot under Depot on the Lines page.",
                    chinese: "舊存檔裡早就買下、沒有機廠的路線，可以在路線頁的「所屬機廠」加建真實機廠。"
                ),
                Line(
                    english: "A slow train waits in a passing loop to let a faster one overtake it.",
                    chinese: "快車追上慢車時，慢車會開進待避線讓快車先走。"
                ),
                Line(
                    english: "Sights count their visitors for yesterday, this year and last year, including riders of lines that run only mornings or evenings.",
                    chinese: "觀光景點的昨天、今年、去年人次有數字了，只開早晚的線載的人也算進去。"
                ),
            ],
            fixes: [
                Line(
                    english: "The Wenhu Line can be bought in the high-speed rail demo.",
                    chinese: "高鐵示範開局可以收購文湖線了。"
                ),
                Line(
                    english: "On lines run to a real timetable, trains leaving the depot go round parked ones and no trips are missed.",
                    chinese: "照真實時刻表開的線，從機廠出來的列車會繞開停著的車，不再漏掉班次。"
                ),
                Line(
                    english: "Zoomed in, bubbles, fare labels and station cards no longer cover station names.",
                    chinese: "放大地圖時，對話泡泡、票價標籤和站牌卡片不再蓋住站名。"
                ),
                Line(
                    english: "On the 3D map, train labels follow their trains.",
                    chinese: "3D 地圖的列車標籤會跟著列車，不再停在畫面左上角。"
                ),
                Line(
                    english: "Coming back from another app no longer pauses the game for a moment.",
                    chinese: "從別的 App 切回遊戲時，不再停頓一下。"
                ),
                Line(
                    english: "More places where the game could close during an animation are fixed.",
                    chinese: "修掉更多畫面在動畫進行中可能讓遊戲閃退的地方。"
                ),
                Line(
                    english: "Day passes are paid in every midnight, and amusement parks and the other businesses get their pass holders too.",
                    chinese: "一日券每天午夜都會入帳了，遊樂園等子公司也有一日券客人。"
                ),
                Line(
                    english: "Trains leaving a depot no longer run through parked trains, and a slow train on a timetable also lets a faster one overtake it.",
                    chinese: "出機廠的列車不再穿過停著的車；照班次開的慢車也會讓快車越行。"
                ),
                Line(
                    english: "The Lines page says when a depot's sidings are all too short for the line's trains.",
                    chinese: "機廠的停車線都比列車短時，路線頁會提醒。"
                ),
                Line(
                    english: "With traffic control off, a train no longer waits for a platform held for a train that cannot reach it.",
                    chinese: "行車控制關閉時，列車不再為了一列過不來的車空等月台。"
                ),
                Line(
                    english: "Adding a depot charges the price shown when you add it.",
                    chinese: "加建機廠照按下那一刻的價格收費。"
                ),
                Line(
                    english: "Platforms set on both tracks of a double track get crossovers beside them, so trains in each direction can pass instead of meeting head-on.",
                    chinese: "在複線兩條都設月台時，旁邊會自動加渡線，兩個方向的車能錯開，不再頂住。"
                ),
            ]
        ),
        Entry(
            id: "2026-11-02-105-1",
            items: [
                Line(
                    english: "The Breezy Blue train now has two blue R100 locomotives pulling its blue coaches.",
                    chinese: "藍皮解憂號換成兩台藍色 R100 機車重連，拉著藍皮客車。"
                ),
                Line(
                    english: "Freight trains on the 3D map are an R200 locomotive pulling container wagons, with a diesel horn.",
                    chinese: "貨運線的列車在 3D 地圖上是 R200 機車拉貨櫃車，汽笛也換成柴油機車的。"
                ),
                Line(
                    english: "Chu-Kuang trains behind an R100 have a new orange R100 locomotive.",
                    chinese: "R100 牽引的莒光號換上新的橘色 R100 機車。"
                ),
                Line(
                    english: "The R200 now hauls freight, so R200 Chu-Kuang trains are no longer sold; the ones you have keep running.",
                    chinese: "R200 改拉貨運，買車時不再有 R200 莒光號；已經有的照常行駛。"
                ),
                Line(
                    english: "The Ankeng light rail comes with its real depot, where its trains rest overnight.",
                    chinese: "收購安坑輕軌時一起拿到真實的安坑機廠，晚上列車回機廠休息。"
                ),
            ],
            fixes: [
                Line(
                    english: "On the 3D map, sloping ground no longer shows sharp spikes.",
                    chinese: "3D 地圖上，坡地的地面不再冒出尖尖的三角形。"
                ),
                Line(
                    english: "On the 3D map, a train at a curved platform keeps its front and back cars on the track.",
                    chinese: "3D 地圖上，停在彎道月台的列車，頭尾不再甩出軌道外。"
                ),
                Line(
                    english: "On the 2D map, a crowded station's ring no longer covers its name.",
                    chinese: "2D 地圖上，擁擠車站的圓環不再蓋住站名。"
                ),
            ]
        ),
        Entry(
            id: "2026-11-01-104-1",
            items: [
                Line(
                    english: "Schools and hospitals you build bring students and patients by train, shown on the station card.",
                    chinese: "蓋好的學校、醫院會帶學生和看病的旅客搭車來，車站卡上看得到人數。"
                ),
                Line(
                    english: "A real line you buy keeps its own trains, such as the DR1000 on branch lines and the Danhai light rail.",
                    chinese: "收購的真實路線保留自己的車：支線是 DR1000，淡海是淡海輕軌列車。"
                ),
                Line(
                    english: "The Ankeng light rail can now be bought as a real line.",
                    chinese: "安坑輕軌開放收購。"
                ),
                Line(
                    english: "On the 2D map, an expanded station shows a small station mark beside its name.",
                    chinese: "2D 地圖上，擴建過的車站在站名旁會多一個小站房記號。"
                ),
                Line(
                    english: "A station can be expanded once it was full on 4 of the last 7 days; its card counts the days so far.",
                    chinese: "最近 7 天裡有 4 天客滿的車站才能擴建，車站卡會寫目前幾天。"
                ),
                Line(
                    english: "Taiwan Railway trains on the real map run to the real train-by-train timetable.",
                    chinese: "實景地圖的台鐵列車，照真實的逐班時刻表行駛。"
                ),
                Line(
                    english: "The Alishan line runs DL-38 diesel locomotives with Alishan coaches, and Chu-Kuang trains have a new R200 locomotive.",
                    chinese: "阿里山線換成 DL-38 柴油機車與阿里山客車；莒光號換上新的 R200 機車。"
                ),
                Line(
                    english: "An expanded station grows on the 3D map too, and tapping a station there shows its name board.",
                    chinese: "擴建過的車站在 3D 地圖上也會變大；點 3D 地圖上的車站會出現站名牌。"
                ),
                Line(
                    english: "The economy panel shows the whole company's punctuality over the last 7 days.",
                    chinese: "經營面板多了全公司最近 7 天的準點率。"
                ),
                Line(
                    english: "A real line you bought and then removed can be bought again.",
                    chinese: "收購來的真實路線拆掉之後，可以再買回來。"
                ),
                Line(
                    english: "A train that stops because it finds no route, or because the depot is full, tells you why.",
                    chinese: "找不到路、或機廠停滿而停著的列車，會說出原因。"
                ),
                Line(
                    english: "Switching to free mode lets you turn on unlimited money.",
                    chinese: "轉成自由模式時，可以打開無限資金。"
                ),
                Line(
                    english: "The train roster writes large amounts of money the same short way as the rest of the game.",
                    chinese: "車隊表的金額也改用萬、億來寫。"
                ),
            ],
            fixes: [
                Line(
                    english: "Tracing a long line on a big network previews much faster.",
                    chinese: "路網大的時候，長距離描線的預覽快了很多。"
                ),
                Line(
                    english: "On a large network, the pause at 6 a.m. while the day's runs are planned is much shorter.",
                    chinese: "路網大的時候，每天早上 6 點排班時的停頓短了很多。"
                ),
                Line(
                    english: "The total in the middle of the economy pie chart now fits inside the ring.",
                    chinese: "經營圓餅圖中間的總金額完整放進圓環裡，不再被切掉。"
                ),
                Line(
                    english: "Tapping in the mountains on the 3D map lands where your finger is, and hidden track behind a hill is not picked.",
                    chinese: "在 3D 地圖的山區點選，會落在手指下的地方，山後看不到的軌道不會被點到。"
                ),
                Line(
                    english: "Tracing from the end of a track shows one preview line, no longer two on top of each other.",
                    chinese: "從軌道端點描線時，預覽只畫一條，不再重疊。"
                ),
                Line(
                    english: "On iPad, tapping Finish in step 8 of tutorial lesson 5 no longer can close the app.",
                    chinese: "修好 iPad 入門第 5 課第 8 步按「完成建立」時可能閃退的問題。"
                ),
            ]
        ),
        Entry(
            id: "2026-11-01-102-1",
            items: [
                Line(
                    english: "A crowded station can be expanded, from 4,000 to 8,000 to 16,000 waiting passengers.",
                    chinese: "人潮擠滿的車站可以擴建，候車人數從 4,000 加到 8,000，再到 16,000。"
                ),
                Line(
                    english: "The line card shows how punctual the line was over the last 7 days, beside Taiwan Railway's year.",
                    chinese: "路線卡多了最近 7 天的準點率，括號裡是台鐵近一年的數字。"
                ),
                Line(
                    english: "Money is shown in New Taiwan dollars, with a rough figure in US dollars beside large amounts.",
                    chinese: "金額改用新台幣，大金額用萬、億來寫。"
                ),
                Line(
                    english: "The real-map, high-speed and Taiwan Railway demos have tourists and real transfers.",
                    chinese: "實景、高鐵與台鐵示範有觀光客，也能照真實車站轉乘。"
                ),
                Line(
                    english: "At a station with a passing loop, trains running through keep to the straight main line.",
                    chinese: "有待避線的車站，通過的車走直的正線，等候的車進外側股道。"
                ),
                Line(
                    english: "When a train waits and will not move off by itself, you are told which train it waits for.",
                    chinese: "列車一直等著不走時，會說出它在等哪一班車。"
                ),
            ],
            fixes: [
                Line(
                    english: "Trains on the Sanying line no longer all stop when an empty train heads back to the depot.",
                    chinese: "三鶯線不會再因為回送車擋住對向而整條停住。"
                ),
                Line(
                    english: "Placing or rerouting a train checks that it can climb a mountain line.",
                    chinese: "放車或改路線時，會先檢查列車爬不爬得上山線。"
                ),
                Line(
                    english: "Skipping the night and giving orders no longer make the screen stall.",
                    chinese: "跳過夜晚、下指令時，畫面不會再停頓。"
                ),
                Line(
                    english: "If saving fails as you go back to the start screen, you can leave without saving.",
                    chinese: "回開始畫面時存檔失敗，可以選擇不存檔離開。"
                ),
                Line(
                    english: "Dragging a zone fills it in a clearer colour, so shops and offices are easy to tell apart.",
                    chinese: "拖曳分區時的顏色更清楚，商業區和辦公區一眼分得出來。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-31-101-1",
            items: [
                Line(
                    english: "Build has a Zoning tool of its own; the station master points out empty land to zone, and you hear when the first building goes up.",
                    chinese: "建設多了「分區」工具；站長會指出可以劃分區的空地，第一棟建物蓋好時會通知。"
                ),
                Line(
                    english: "Building a station, you pick its layout first and the whole station is built at once.",
                    chinese: "蓋車站時先選排法，整個車站一次蓋好。"
                ),
                Line(
                    english: "The train roster opens from the line page and the train card, and you arrange trains by dragging them.",
                    chinese: "列車運用表可以從路線頁和列車卡直接打開，拖拉就能排班。"
                ),
                Line(
                    english: "When track can't be laid, you are told which condition stops it; tunnels can go down to 1,024 m.",
                    chinese: "鋪軌被擋時會說出是哪個條件；隧道最深可到地下 1,024 公尺。"
                ),
                Line(
                    english: "The zoning layer says for each square whether it will build, waits for the station, is too far away or is not needed yet.",
                    chinese: "分區圖層會標出每一格是會蓋、等車站成長、離車站太遠，還是目前不缺。"
                ),
                Line(
                    english: "Track you lay beside a station's platforms joins that station, and a missing-materials note says what to do next.",
                    chinese: "自己拉的軌道旁有車站月台，就加成那站的月台；缺建材時會說下一步。"
                ),
                Line(
                    english: "Each game takes one row in the save list, keeps its last three versions, and several rows can be deleted at once.",
                    chinese: "同一局存檔只佔一列，列內留最近 3 版，也可以多選刪除。"
                ),
                Line(
                    english: "The DR3100 diesel express runs four times a day on the real map.",
                    chinese: "真實地圖每天多跑四班 DR3100 柴聯自強號。"
                ),
                Line(
                    english: "Dragging a zone greys out the squares no station reaches, and the Zoning tool opens on the use the city needs most.",
                    chinese: "拖曳分區時，車站搆不到的格子先變灰；分區工具打開時先選城市最缺的用途。"
                ),
                Line(
                    english: "Trains that stop wait on the passing loop, leaving the main line to trains running through.",
                    chinese: "停站的列車改停待避線，正線留給通過的車。"
                ),
            ],
            fixes: [
                Line(
                    english: "Starting a lesson from the goals panel saves the game you are playing first.",
                    chinese: "從目標面板開始關卡前，會先存好目前這局。"
                ),
                Line(
                    english: "Laying track from the 3D view, Expand Map no longer sends you back to 3D.",
                    chinese: "從 3D 進來鋪軌時，按「擴建地圖」不會再跳回 3D。"
                ),
                Line(
                    english: "Dragging a new line from the end of a track no longer freezes the map.",
                    chinese: "從軌道端點拖曳描線時，畫面不再卡住。"
                ),
                Line(
                    english: "On an iPhone held sideways, a side panel's station or line name shows whole above it, and no empty mini map sits on the right.",
                    chinese: "iPhone 橫拿時，側邊面板的站名與路線名完整顯示，右側不再有空的小地圖框。"
                ),
                Line(
                    english: "Sights fold away as you zoom out, a station's warnings share one badge, and taps go to stations and track first.",
                    chinese: "景點依縮放收起、同一站的警告合成一顆徽章，點擊先給車站與軌道。"
                ),
                Line(
                    english: "Pressing Build from the 3D map brings you back to the same 3D view when you finish.",
                    chinese: "從 3D 按「建設」，蓋完會回到 3D 原本的視角。"
                ),
                Line(
                    english: "Taking up your own road no longer holds up the next tap.",
                    chinese: "拆自己的路不再讓下一次點按卡住。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-31-100",
            items: [
                Line(
                    english: "Money is now counted in New Taiwan dollars: fares, prices and costs are about three times what they were, and old saves convert on their own.",
                    chinese: "金額改用新台幣：票價、價錢與成本約是原來的三倍，舊存檔會自動換算。"
                ),
                Line(
                    english: "The high-speed demo's fares follow the official fare table, and the default distance fares are whole dollars.",
                    chinese: "高鐵示範的票價照官方票價表，預設的分段票價都是整數元。"
                ),
            ],
            fixes: []
        ),
        Entry(
            id: "2026-10-31-99",
            items: [
                Line(
                    english: "At 4 a.m. each day, people still waiting at a station go home, so stations no longer stay full overnight.",
                    chinese: "每天凌晨 4 點，還在車站等的人會先回家，車站不會整夜一直滿著。"
                ),
                Line(
                    english: "The DR1000 diesel railcar on the 3D map looks like the real one.",
                    chinese: "3D 地圖裡的 DR1000 柴油客車，照實車的樣子畫。"
                ),
                Line(
                    english: "When a stretch of track can't be built, the build card names the one reason why.",
                    chinese: "軌道蓋不了時，建造卡會直接說是什麼原因。"
                ),
                Line(
                    english: "With no line yet, the Lines panel says what is missing and takes you to Build, and the station master offers the tutorial.",
                    chinese: "還沒有路線時，路線面板會說缺什麼並帶你去建設，站長也會先問要不要教學。"
                ),
                Line(
                    english: "Tracing a real line you can buy says what it costs, and Build has a Buy Line button.",
                    chinese: "描線經過可收購的真實路線時會提示價格，建設裡也多了「收購路線」。"
                ),
            ],
            fixes: [
                Line(
                    english: "Buses keep a one-way street's direction on a road laid along it.",
                    chinese: "沿著單行道鋪的路，公車照樣照單行的方向走。"
                ),
                Line(
                    english: "Undo lets go of the road stretch you picked to take up.",
                    chinese: "按復原會放掉剛選要拆的那段路。"
                ),
                Line(
                    english: "A station's name tag moved off a bubble no longer covers the station next to it.",
                    chinese: "車站名牌避開泡泡時，不再蓋到旁邊的車站。"
                ),
                Line(
                    english: "On an iPhone held sideways, the loading screen fits, the whole spending ring shows in the economy panel, and the map legend sits low while you build.",
                    chinese: "iPhone 橫拿時，載入畫面完整、經濟的支出圓環不再被切，建設時圖例移到下方不擋地圖。"
                ),
                Line(
                    english: "The game menu shows labels beside its buttons on iPad and on an iPhone held upright.",
                    chinese: "iPad 與直拿的 iPhone，遊戲選單的按鈕旁有文字。"
                ),
                Line(
                    english: "On an iPhone held sideways, the Lines panel shows your lines first, panel titles wrap instead of being cut, and the four building tools fit without scrolling.",
                    chinese: "iPhone 橫拿時，路線面板先列出你的路線，面板標題不再被切，四個建設工具不用捲。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-30-98",
            items: [
                Line(
                    english: "The Danhai, Ankeng and Kaohsiung light rail trains look like the real ones on the 3D map.",
                    chinese: "3D 地圖裡淡海、安坑、高雄輕軌的列車，照實車的樣子畫。"
                ),
                Line(
                    english: "A road laid along an existing street shows on the 3D map at once, and buses redraw onto a new road right away.",
                    chinese: "沿著地圖上現有街道鋪的路，3D 立刻看得到，公車改走新路也立刻重畫。"
                ),
            ],
            fixes: [
                Line(
                    english: "With many saves, going back to the start screen and opening the save list are much faster.",
                    chinese: "存檔多時，回開始畫面與存檔清單變快。"
                ),
                Line(
                    english: "The card for buying a real line shows the total in bold, and a line bought before 4 a.m. says it starts with today's first train.",
                    chinese: "收購真實路線的卡片，合計用粗體；凌晨 4 點前收購，寫今天首班車起開。"
                ),
                Line(
                    english: "Going back to the start screen from the menu no longer freezes, even with many saves.",
                    chinese: "從選單回開始畫面不再凍住，存檔多也一樣。"
                ),
                Line(
                    english: "Tapping a missing-materials bubble on the map jumps to the station panel's materials row every time, not just the first.",
                    chinese: "點地圖上缺建材的泡泡，每次都會跳到車站面板的建材列，不只第一次。"
                ),
                Line(
                    english: "On an iPhone held sideways, a tutorial card's text stops at the end of a whole line instead of cutting a line in half.",
                    chinese: "iPhone 橫拿時，教學卡的說明停在整行，不再切掉半行字。"
                ),
                Line(
                    english: "On the real-world map, a road a bus route uses can no longer be taken up.",
                    chinese: "實景地圖上，公車線在用的路不能拆。"
                ),
                Line(
                    english: "The quote card for buying a real line is prepared in the background and no longer freezes the screen.",
                    chinese: "收購真實路線的報價卡改在背景準備，不再卡住畫面。"
                ),
            ]
        ),
        Entry(
            id: "2026-10-30-96",
            items: [
                Line(
                    english: "You can buy the Danhai LRT Green Mountain Line; the Danhai depot past Kanding is built with it, and its trains rest there overnight.",
                    chinese: "淡海輕軌綠山線可以買了，崁頂後面的淡海機廠一起蓋，車晚上收在機廠。"
                ),
                Line(
                    english: "The Danhai LRT's two lines can be bought in either order: after the Blue Coast Line, the Green Mountain Line is laid beside it.",
                    chinese: "淡海輕軌兩條線先買哪條都可以：先買藍海線，綠山線會鋪在它旁邊。"
                ),
                Line(
                    english: "Settings has a new Garage, where everyone can look at the trains.",
                    chinese: "設定裡多了「車庫」，每個人都能看列車展示。"
                ),
                Line(
                    english: "The tutorial's step to see who rides opens the station's Riders group at once.",
                    chinese: "教學「點車站看誰在搭車」那一步，直接打開車站的「旅客與運量」。"
                ),
            ],
            fixes: [
                Line(
                    english: "Following a train on the 3D map at 10x speed is smoother.",
                    chinese: "3D 地圖跟著列車、開 10 倍速時更順。"
                ),
                Line(
                    english: "The 3D garbage and recycling trucks no longer have holes, and no black triangles show through at night.",
                    chinese: "3D 的垃圾車和資源回收車不再破洞，晚上不再透出黑色三角。"
                ),
                Line(
                    english: "In the bus tool, stop names no longer pile up with your own stops or a same-named stop across the road, and zooming out is smoother.",
                    chinese: "公車工具的站名不再和你的站牌、對面同名站疊在一起；拉遠看也更順。"
                ),
                Line(
                    english: "Dragging a building to find its place is smoother.",
                    chinese: "拖著建築找位置時更順。"
                ),
                Line(
                    english: "A line bought in the daytime starts with the next morning's first train, and riders no longer wait all day for it, so trains no longer stall at Zhuzhong.",
                    chinese: "白天買的線隔天首班車才開，開之前旅客不再先去等，列車不再卡在竹中。"
                ),
                Line(
                    english: "Holding an iPad or phone upright while adding a line, the two-station card sits above the corner buttons and no longer runs off the screen.",
                    chinese: "iPad 與手機直拿新增路線時，兩站比較卡移到角落按鈕上方，不再超出螢幕。"
                ),
                Line(
                    english: "Jumping to a group from a station panel's menu stops at the start of that group.",
                    chinese: "車站面板從選單跳組，會停在那一組的開頭。"
                ),
                Line(
                    english: "Rain on the maps is redrawn less often, saving battery and running smoother.",
                    chinese: "下雨時地圖少重畫，更省電也更順。"
                ),
                Line(
                    english: "Last month's report can be opened again from Data after it is closed.",
                    chinese: "月報關掉之後，在「資料」還能再打開上個月的那一份。"
                ),
            ]
        ),
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
