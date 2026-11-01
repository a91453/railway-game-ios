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
                    english: "Money is shown as NT$, with a rough US$ figure beside large amounts.",
                    chinese: "金額寫成 NT$，大金額用萬、億來寫。"
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
