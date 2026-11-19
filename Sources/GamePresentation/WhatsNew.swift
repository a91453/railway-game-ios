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
        // 142.
        Entry(
            id: "2026-11-20-142",
            items: [
                Line(
                    english: "Fukuoka opens: fly there from Taoyuan or Kaohsiung, download its map, and run its three subway lines.",
                    chinese: "福岡開放：從桃園或高雄飛福岡，下載地圖後經營市營地鐵三條線。"
                ),
                Line(
                    english: "Fukuoka's 3D map has Japanese streets and buildings, Fukuoka Tower, the Dome and Hakata Station.",
                    chinese: "福岡的 3D 地圖有日本的街道與建築、福岡塔、巨蛋與博多站。"
                ),
                Line(
                    english: "Hong Kong's Sunny Bay and Tsing Yi each have one island where two lines meet.",
                    chinese: "香港欣澳、青衣兩站照真實收成一座島，兩條線同島轉乘。"
                ),
            ],
            fixes: [
                Line(
                    english: "Sanying Line's early train at Yingtao Fude leaves on time instead of waiting behind an empty train.",
                    chinese: "三鶯線鶯桃福德的早班車不再被空車擋住，準時發車。"
                ),
            ]
        ),
        // 141.
        Entry(
            id: "2026-11-19-141",
            items: [
                Line(
                    english: "A track you draw across another at the same height makes a level crossing where they meet.",
                    chinese: "畫線越過同一高度的軌道時，交會處自動做成平面交叉。"
                ),
                Line(
                    english: "Write your own departure melody in the melody workshop and give it to any station.",
                    chinese: "在旋律工作坊寫自己的發車旋律，指定給想要的車站。"
                ),
                Line(
                    english: "Platforms have station name boards along their backs.",
                    chinese: "平面、高架、地下月台的背面立起站名牌。"
                ),
                Line(
                    english: "Rovaniemi's streets have Finnish bus shelters, street lights, give-way signs, roundabout lines and street name signs.",
                    chinese: "羅瓦涅米多了芬蘭的候車亭、路燈、讓路標誌、圓環讓路線與路名牌。"
                ),
                Line(
                    english: "Remove a downloaded map's data in Settings, or download it again.",
                    chinese: "設定裡可以刪除已下載的地圖資料，或重新下載。"
                ),
                Line(
                    english: "Zhuzhong has side platforms with an island between the two lines, all on one viaduct.",
                    chinese: "竹中站照真實配成兩側月台加一座島，兩條線同在高架一層。"
                ),
                Line(
                    english: "Hong Kong's 3D blocks draw faster, and saves with many Taiwan lines run more smoothly.",
                    chinese: "香港 3D 街區畫得更快，台灣買很多線的存檔跑得更順。"
                ),
            ],
            fixes: [
                Line(
                    english: "The last train gets into its terminus even when trains done for the day fill a platform there.",
                    chinese: "收班車占著終點月台時，末班車改進另一個空月台。"
                ),
                Line(
                    english: "The rebuilt Taoyuan Airport MRT no longer jams.",
                    chinese: "機場捷運改建線不再卡死。"
                ),
                Line(
                    english: "Official departure melody 2 plays its first, highest note.",
                    chinese: "官方發車旋律二開頭最高的那個音會響出來。"
                ),
                Line(
                    english: "Binhai Shalun has one island platform, and the Blue Coast Line runs through from Hongshulin.",
                    chinese: "濱海沙崙站照真實只剩一座島，藍海線從紅樹林直通，不用在沙崙轉車。"
                ),
            ]
        ),
        // 140.
        Entry(
            id: "2026-11-19-140",
            items: [
                Line(
                    english: "Real lines that share a station are sold together, so you buy the whole group at once.",
                    chinese: "共用車站的真實路線改成一起收購，一次買下整組。"
                ),
                Line(
                    english: "Cable car mode can lay the real Sun Moon Lake, Wulai and Ngong Ping cable cars, and visitors nearby ride them.",
                    chinese: "纜車模式可以照真實路線拉日月潭、烏來、昂坪纜車，附近景點的遊客會來搭。"
                ),
                Line(
                    english: "Tsing Ma Bridge has its towers and cables, and Danjiang Bridge its tower and stay cables.",
                    chinese: "青馬大橋有了橋塔與主纜，淡江大橋有了橋塔與斜拉索。"
                ),
                Line(
                    english: "Sun Moon Lake has its pier, boats, Wenwu Temple and pavilion.",
                    chinese: "日月潭多了碼頭、遊艇、文武廟與涼亭。"
                ),
                Line(
                    english: "Underground stations show their platforms, and bought underground stations lie in tunnels.",
                    chinese: "地下車站畫出月台，收購的真實地下站照真實鋪進隧道。"
                ),
                Line(
                    english: "Every platform has the same benches, vending machines and signs.",
                    chinese: "平面、高架、地下月台都放上同一套長椅、販賣機與看板。"
                ),
                Line(
                    english: "Choose each station's arrival chime and departure melody; there are now six melodies.",
                    chinese: "可以替每一站選到站鈴與發車旋律，發車旋律加到六首。"
                ),
                Line(
                    english: "Rovaniemi's trains are Finland's Sr2 locomotives with double-deck coaches.",
                    chinese: "羅瓦涅米的列車換成芬蘭 Sr2 電力機車與雙層客車。"
                ),
                Line(
                    english: "Elevated roads stand higher, and new parts of the 3D map appear faster.",
                    chinese: "高架道路蓋得更高，3D 地圖補畫新地方更快。"
                ),
            ],
            fixes: [
                Line(
                    english: "A line you remove and buy back returns to its old place.",
                    chinese: "刪掉再買回來的路線會回到原本的位置。"
                ),
                Line(
                    english: "Lines sharing a station always have platforms side by side at one height.",
                    chinese: "共用車站的路線，月台一律並排在同一高度。"
                ),
                Line(
                    english: "Tsing Ma Bridge's road no longer sinks to the sea, and Hong Kong's hillside roads lie level.",
                    chinese: "青馬大橋公路不再沉到海面，香港山坡路不再傾斜。"
                ),
                Line(
                    english: "Screen doors, queue lines and stop signs match where trains really stop.",
                    chinese: "月台門、排隊線與停車位置牌照列車實際停的位置排。"
                ),
                Line(
                    english: "A game plays out the same at normal and ten-times speed.",
                    chinese: "一倍速和十倍速玩出來的結果一樣。"
                ),
            ]
        ),
        // 139.
        Entry(
            id: "2026-11-18-139",
            items: [
                Line(
                    english: "Hong Kong's East Rail, South Island and Disneyland Resort lines run their own real trains.",
                    chinese: "香港東鐵綫、南港島綫、迪士尼綫換上自己的真實列車。"
                ),
                Line(
                    english: "At night only the windows of Hong Kong's trains light up, not their doors and frames.",
                    chinese: "港鐵列車夜裡只有窗戶亮，門與窗框不再跟著發光。"
                ),
                Line(
                    english: "Following or driving a train, each line plays its own departure melody as the doors close.",
                    chinese: "跟著列車或駕駛時，關門前會響那條路線自己的發車旋律。"
                ),
                Line(
                    english: "Real lines you buy have platform screen doors where the real stations do, full or half height.",
                    chinese: "收購的真實路線，月台照真實裝上全高或半高的月台門。"
                ),
                Line(
                    english: "A station's card shows the real station's name in its other language under its name.",
                    chinese: "車站卡片的站名下面，多一行真實車站的原文名字。"
                ),
                Line(
                    english: "Rovaniemi's streets have Finland's own signals, street lights and bus stops, and no traffic lights at roundabouts.",
                    chinese: "羅瓦涅米街上換成芬蘭的號誌、路燈與站牌，圓環不再裝紅綠燈。"
                ),
                Line(
                    english: "Ballast trains are made of Taiwan Railway's hopper wagons.",
                    chinese: "砂石列車換成台鐵的石斗車。"
                ),
            ],
            fixes: [
                Line(
                    english: "Two lines sharing a station now have their platforms side by side at one height, not one stacked above the other.",
                    chinese: "兩條線共用車站時，月台並排在同一高度，不再一座疊在另一座上方。"
                ),
                Line(
                    english: "Hong Kong's South Island line no longer misses trains at the peaks.",
                    chinese: "香港南港島綫尖峰不再漏發班次。"
                ),
                Line(
                    english: "Roads crossing on one bridge deck stand at their own levels, and ramp edges no longer show under the main road.",
                    chinese: "同一座橋上交叉的道路照各自樓層分高度，引道邊緣不再畫進主線底下。"
                ),
                Line(
                    english: "The Hong Kong map fetches its new version itself instead of staying on the built-in data.",
                    chinese: "香港地圖遇到舊版會自己要新版，不再停在「使用內建資料」。"
                ),
            ]
        ),
        // 138.
        Entry(
            id: "2026-11-18-138",
            items: [
                Line(
                    english: "Rovaniemi opens: pick it from the new-game list from the start.",
                    chinese: "羅瓦涅米開放：新遊戲的地圖清單一開始就能選。"
                ),
                Line(
                    english: "Rovaniemi's track belongs to the state: buying a line costs nothing for the track.",
                    chinese: "羅瓦涅米的軌道屬於國家，買線不用付鋪軌的錢。"
                ),
                Line(
                    english: "Rovaniemi has snowy trees, frozen rivers, the northern lights on clear nights, and reindeer by Santa Claus Village.",
                    chinese: "羅瓦涅米樹帶雪、河結冰，晴夜有極光，聖誕老人村旁有馴鹿。"
                ),
                Line(
                    english: "Buying Hong Kong's South Island or Tung Chung line builds its real depot, where trains spend the night.",
                    chinese: "香港新買南港島綫、東涌綫時會蓋出真實車廠，收班後列車回廠。"
                ),
                Line(
                    english: "Hong Kong's Tuen Ma line has its own eight-car train.",
                    chinese: "香港屯馬綫有自己的 8 節列車。"
                ),
                Line(
                    english: "Hong Kong's countryside in 3D is coloured from real land use, and woods grow trees.",
                    chinese: "香港 3D 地圖的鄉間照真實土地上色，林地會長樹。"
                ),
                Line(
                    english: "Cars on Taiwan's streets are saloons, SUVs, vans and yellow taxis instead of boxes.",
                    chinese: "台灣街上的汽車換成轎車、休旅車、廂型車與黃色計程車。"
                ),
                Line(
                    english: "Freight trains show what they carry, and stations with a freight yard show it beside the track.",
                    chinese: "貨運列車看得出載了什麼，有貨運場的車站旁邊有貨場。"
                ),
                Line(
                    english: "High-speed, metro and Wenhu line trains are as long as the real ones.",
                    chinese: "高鐵、捷運與文湖線的列車照真車的長度排。"
                ),
                Line(
                    english: "Motorways no longer ride over every hill, and ramps come down to the ground inside their bridges.",
                    chinese: "國道不再跟著山起伏，匝道與引道在橋裡就下到地面。"
                ),
                Line(
                    english: "The theme is now a minuet for piano and strings, and in December it takes turns with the winter music.",
                    chinese: "主題曲換成鋼琴與弦樂的小步舞曲，12 月起與冬季曲輪流播放。"
                ),
            ],
            fixes: [
                Line(
                    english: "Real trains on the map no longer have a double-width gap between cars.",
                    chinese: "地圖上真實列車的車廂之間，縫隙不再是兩倍寬。"
                ),
                Line(
                    english: "Laying track, the end no longer snaps to a spot beside another track.",
                    chinese: "鋪軌時終點不會再停在另一條軌道旁邊。"
                ),
                Line(
                    english: "Zuoying's roof frame no longer shows as white stripes across the trains.",
                    chinese: "左營站屋頂骨架不再像一排白條橫過列車。"
                ),
            ]
        ),
        // 137.
        Entry(
            id: "2026-11-17-137",
            items: [
                Line(
                    english: "The 3D map opens faster the first time.",
                    chinese: "第一次打開 3D 地圖變快了。"
                ),
                Line(
                    english: "The E200 electric locomotive is rebuilt, its roof and sides closer to the real one.",
                    chinese: "台鐵 E200 電力機車重做，車頂與車身側面更像真車。"
                ),
                Line(
                    english: "Tall buildings in 3D have five kinds of windows, and balconies, sunshades and bay windows up close.",
                    chinese: "3D 高樓多了五種窗戶，近看有陽台、遮陽板與凸窗。"
                ),
                Line(
                    english: "Hong Kong's buildings look like Hong Kong: residential towers, tong lau and glass towers.",
                    chinese: "香港的建物換成香港的樣子：住宅塔、唐樓與玻璃帷幕。"
                ),
                Line(
                    english: "Taiwan's countryside in 3D is coloured from real land cover, and forests grow trees.",
                    chinese: "台灣 3D 地圖的鄉間照真實土地上色，森林會長樹。"
                ),
                Line(
                    english: "Sunrise and sunset in 3D follow the place and the game's date.",
                    chinese: "3D 地圖的日出日落照所在地與遊戲日期。"
                ),
                Line(
                    english: "The theme has a new melody, and winter music plays from 1 December to 6 January.",
                    chinese: "主題曲改版；12 月 1 日到 1 月 6 日換成冬季曲。"
                ),
                Line(
                    english: "Laying track colours the preview by how fast a curve can be run, and the end snaps to track beside it.",
                    chinese: "鋪軌預覽依彎道能跑多快上色，拖到旁邊的軌道時終點會對齊。"
                ),
                Line(
                    english: "Roads you draw run straight and smooth, and join the streets they meet.",
                    chinese: "自己畫的路又直又順，接到街道時路口會接起來。"
                ),
                Line(
                    english: "Shifen can be rebuilt with an island platform after you buy it.",
                    chinese: "買下的十分可以改成島式月台。"
                ),
            ],
            fixes: [
                Line(
                    english: "Settings now use the Hong Kong map you downloaded.",
                    chinese: "設定的香港地圖下載後，現在會真的用上。"
                ),
                Line(
                    english: "On Hong Kong's South Island and Tung Chung lines, idle trains blocking a full end run empty to the other end.",
                    chinese: "香港南港島綫與東涌綫收班後一端停滿時，擋路的空車會開去另一端。"
                ),
                Line(
                    english: "A train no longer waits behind a spare train on its platform; it takes an empty one on the way.",
                    chinese: "備用車占著月台時，後面的車在路上就改進空的月台。"
                ),
                Line(
                    english: "A Christmas livery picked in a game never saved by hand stays after the app restarts.",
                    chinese: "沒手動存過的新遊戲，選的聖誕塗裝重開 App 不再不見。"
                ),
            ]
        ),
        // 136.
        Entry(
            id: "2026-11-17-136",
            items: [
                Line(
                    english: "Hong Kong has the Hong Kong Convention and Exhibition Centre in 3D.",
                    chinese: "香港 3D 地圖多了香港會議展覽中心。"
                ),
                Line(
                    english: "From 1 December to 6 January, a Christmas livery for a passenger line adds a snowy roof, wreaths and lights, and a ribbon on the lead car.",
                    chinese: "12 月 1 日到 1 月 6 日，聖誕塗裝會替列車加上雪頂、花環與燈，頭車繫緞帶。"
                ),
            ],
            fixes: [
                Line(
                    english: "On an iPhone held sideways with large text, the ✕ ✓ buttons for double track and platform spots no longer squeeze off the screen.",
                    chinese: "iPhone 橫拿、字級調大時，鋪雙線與選月台的 ✕ ✓ 不再擠出畫面。"
                ),
                Line(
                    english: "With signalling on, trains that only stop at a terminal no longer cut in front of trains that still have to go on, so fewer trains wait on one another.",
                    chinese: "管制開著時，只是進終點停著的列車不再搶在還要往前開的車前面，互相等的情況變少。"
                ),
            ]
        ),
        // 135.
        Entry(
            id: "2026-11-17-135",
            items: [
                Line(
                    english: "Laying track shows a cleaner screen: what has nothing to do with the track is put away, and a stretch that cannot be built says why and what would work.",
                    chinese: "鋪軌時畫面更乾淨：和這段軌道無關的東西先收起，不能鋪時才說原因與建議。"
                ),
                Line(
                    english: "Hong Kong has the HSBC Main Building in 3D.",
                    chinese: "香港 3D 地圖多了滙豐總行大廈。"
                ),
                Line(
                    english: "Settings, under Map, say whether the Hong Kong map is downloaded, downloading or using the built-in data.",
                    chinese: "設定的「地圖」多一列，看得到香港地圖是已下載、下載中，還是使用內建資料。"
                ),
                Line(
                    english: "From 1 December to 6 January, stations and their entrances hang Christmas lights, and big stations have a Christmas tree in front.",
                    chinese: "12 月 1 日到 1 月 6 日，站房與出入口掛上聖誕燈串，大站站前有聖誕樹，晚上會亮。"
                ),
                Line(
                    english: "In those weeks a passenger line's settings can give its trains a Christmas livery.",
                    chinese: "同一段期間，客運路線的設定可以替列車換上聖誕塗裝。"
                ),
            ],
            fixes: [
                Line(
                    english: "With signalling off, trains in a depot no longer wait on one another until most of the next day's trains never leave.",
                    chinese: "關掉行車管制後，機廠裡的列車不再互相等到第二天大半班次發不出去。"
                ),
                Line(
                    english: "With signalling off, trains that block one another are marked on the map, and one is let through each minute.",
                    chinese: "行車管制關著時，互相擋住的列車會在地圖上標出來，每分鐘放一列先走。"
                ),
                Line(
                    english: "On an iPhone held sideways, the card no longer covers the reason a stretch of track cannot be built.",
                    chinese: "iPhone 橫拿鋪軌時，卡片不再蓋住不能鋪的原因。"
                ),
                Line(
                    english: "Eight of Hong Kong's landmarks no longer flicker as the camera moves.",
                    chinese: "香港八棟地標在鏡頭移動時不再閃爍。"
                ),
            ]
        ),
        // 134.
        Entry(
            id: "2026-11-16-134",
            items: [
                Line(
                    english: "Hong Kong has eight landmarks in 3D: ICC, Two IFC, Central Plaza, the Bank of China Tower, Cheung Kong Center, The Center, the Clock Tower and the Cultural Centre.",
                    chinese: "香港 3D 地圖多了八棟地標：環球貿易廣場、國金二期、中環廣場、中銀大廈、長江中心、中環中心、尖沙咀鐘樓、文化中心。"
                ),
                Line(
                    english: "Hong Kong's Airport Express, Tung Chung line and urban line trains have finer doors and windows, a light grey roof and air-conditioning units.",
                    chinese: "機場快綫、東涌綫、市區綫的列車門窗分得更細，車頂改淺灰，加上冷氣機。"
                ),
                Line(
                    english: "A depot's shed and stabling shelter have a silver-grey metal roof.",
                    chinese: "機廠的檢修庫與駐車棚換上銀灰色的鐵皮屋頂。"
                ),
            ],
            fixes: [
                Line(
                    english: "The Taoyuan Airport MRT and the Wenhu line no longer leave out a few of the day's trains.",
                    chinese: "機場捷運與文湖線一天裡不再少發幾班車。"
                ),
                Line(
                    english: "With an iPhone held sideways, the roster's Arrange page is no longer hidden under the notch.",
                    chinese: "iPhone 橫拿時，運用表「編排」頁的車名不再被瀏海擋住。"
                ),
                Line(
                    english: "A building that was drawn twice in the 3D map is drawn once, so its outline no longer doubles.",
                    chinese: "3D 地圖裡同一棟被畫兩次的建物只畫一次，輪廓不再重疊。"
                ),
                Line(
                    english: "The Pingxi and Neiwan lines are bought with their real island platforms, and the island list no longer names light rail stops.",
                    chinese: "收購平溪線、內灣線時，十分、竹東等站直接鋪成島式月台；島式站清單不再列出輕軌的站。"
                ),
            ]
        ),
        // 133.
        Entry(
            id: "2026-11-15-133",
            items: [
                Line(
                    english: "Hong Kong's Airport Express and Tung Chung line run their own trains, and four urban lines run the urban line train.",
                    chinese: "機場快綫、東涌綫換上自己的列車；荃灣、港島、觀塘、將軍澳綫跑市區綫列車。"
                ),
                Line(
                    english: "Commuter trains of four or more cars with no model set are drawn as a red commuter car with doors, windows and lamps.",
                    chinese: "沒有指定車型的 4 節以上通勤車，3D 地圖畫成有門窗、車燈的紅色通勤車。"
                ),
                Line(
                    english: "A depot's shed is as long as its sidings, with their tracks, and as tall as the trains kept there.",
                    chinese: "機廠的檢修庫照股道長度與股數蓋，高度配合停在這裡的列車。"
                ),
                Line(
                    english: "Up close, people on platforms, forecourts, streets and bus stops are commuters; further away they stay as before.",
                    chinese: "近看月台、站前、街上與公車站，行人換成通勤乘客；遠處照舊。"
                ),
                Line(
                    english: "Fishing harbours and wharves are harbours now, busy at lunch and sunset and quieter in the rain, with Longfeng and Budai added.",
                    chinese: "漁港與漁人碼頭獨立成港口碼頭：中午、傍晚兩波人潮，雨天少更多；多了龍鳳、布袋漁港。"
                ),
                Line(
                    english: "A line's own page has four tabs, Overview, Trains, Stops and Settings, and two columns on a wide screen.",
                    chinese: "路線詳情分成總覽、列車、停靠站、設定四頁；寬畫面分兩欄。"
                ),
                Line(
                    english: "The train roster has an Arrange page: drag unplanned trains in and see the gaps between two runs.",
                    chinese: "列車運用表多一頁「編排」：拖入還沒排的列車，兩趟之間畫出空檔。"
                ),
                Line(
                    english: "The follow cameras behind and above a train look further ahead along the line.",
                    chinese: "跟車的後方、上後方鏡頭視角縮窄，往行駛方向多看一段。"
                ),
            ],
            fixes: [
                Line(
                    english: "Hong Kong's trains are no longer drawn as three boxes, and have their real number of cars.",
                    chinese: "港鐵各綫的列車不再畫成三節方塊，節數照真實。"
                ),
                Line(
                    english: "The real-world demo no longer opens with an island rebuild card it cannot carry out.",
                    chinese: "實景示範一開局不再跳出改不了的島式站改建卡。"
                ),
                Line(
                    english: "The high-speed demo's Banqiao, already an island, is no longer listed for an island rebuild.",
                    chinese: "高鐵示範的板橋本來就是島式，不再列進改建清單。"
                ),
                Line(
                    english: "Signalling and laying track find their way faster, so big maps such as Hong Kong run more smoothly.",
                    chinese: "行車控制排路與鋪線變快，香港等大地圖比較不卡。"
                ),
            ]
        ),
        // 132.
        Entry(
            id: "2026-11-15-132",
            items: [
                Line(
                    english: "You can buy real air routes from the lines panel, choose flights and aircraft, and see them on the map.",
                    chinese: "路線面板可以收購機場真實的航線，選班數與飛機大小，2D 地圖畫出航線。"
                ),
                Line(
                    english: "Buying an air route to Hong Kong opens the Hong Kong map too.",
                    chinese: "收購一條飛香港的航線，也會開放香港地圖。"
                ),
                Line(
                    english: "Your routes' aircraft take off and land on their timetable on the 3D map, and you can follow one up to cruise.",
                    chinese: "買下的航線，飛機在 3D 地圖照時刻起降，可以跟著飛到巡航高度。"
                ),
                Line(
                    english: "Concerts and games are held at stadiums and arenas, exhibitions at exhibition halls.",
                    chinese: "演唱會、球賽辦在體育場與巨蛋，展覽在展覽館。"
                ),
                Line(
                    english: "Night markets fill in the evening; landmarks, museums and temples each draw visitors at their own times.",
                    chinese: "夜市傍晚熱鬧；地標、博物館、廟宇各有自己的人潮時段。"
                ),
                Line(
                    english: "Buying a real station lays its real platforms: an island where it has one, two sides where it has two.",
                    chinese: "收購真實車站時照真實月台型式鋪：島式站中間一座島，岸式站兩側各一座。"
                ),
                Line(
                    english: "A double-track station with two side platforms can be rebuilt as an island, one by one or all at once.",
                    chinese: "雙線岸式站可以改成島式月台；舊存檔的真實島式站可以一次改建。"
                ),
                Line(
                    english: "After each year's accounts, a year-end appraisal grades five things, with two new achievements.",
                    chinese: "每年結算後有年終考核，五項各給等第；另有兩個新成就。"
                ),
                Line(
                    english: "A leg of a line can have its own list of platforms, and switches can take time to throw.",
                    chinese: "路線的一段可以排月台清單；交通控制多「道岔扳轉要時間」。"
                ),
                Line(
                    english: "City buildings have more roof and wall colours, and the industrial yards have a coal bunker.",
                    chinese: "城市建築多幾種屋頂與牆色；工業區的空地多了儲煤台。"
                ),
            ],
            fixes: [
                Line(
                    english: "A bought real station's platforms can be lengthened, and high-speed platforms fit a whole train.",
                    chinese: "收購的真實車站月台可以加長、加月台軌道；高鐵月台停得下整列車。"
                ),
                Line(
                    english: "Stations on real viaducts, such as Qiyan, can be built when you trace a real line.",
                    chinese: "沿真實鐵路描線經過高架車站（奇岩等）時，蓋得了站與月台軌道。"
                ),
                Line(
                    english: "Hong Kong's island stations have island platforms, and its airport lines can be bought in any order.",
                    chinese: "香港真實島式站是島式月台；機場快綫、東涌綫、迪士尼綫任何順序都能收購。"
                ),
                Line(
                    english: "Stadiums, big sheds, huts and round walls no longer get windows they do not have.",
                    chinese: "體育館、大型廠房、小屋與圓牆不再畫出真實沒有的窗戶。"
                ),
                Line(
                    english: "A failed save when going back to the main screen no longer loses your game.",
                    chinese: "回主畫面時存檔失敗，不再丟掉原本那一局。"
                ),
                Line(
                    english: "The 3D map uses less memory.",
                    chinese: "3D 地圖用的記憶體比較少。"
                ),
            ]
        ),
        // 131.
        Entry(
            id: "2026-11-14-131",
            items: [
                Line(
                    english: "In a new game on realistic rules, passengers who wait too long leave; the station panel shows how many did.",
                    chinese: "寫實規則的新遊戲：乘客等太久會離開，車站面板寫著有多少人等太久走了。"
                ),
                Line(
                    english: "In a new game on realistic rules, taxes are settled once a year as in Taiwan, with a reminder a month before they are due.",
                    chinese: "寫實規則的新遊戲：稅照台灣的方式一年結算，繳稅前一個月站長會提醒。"
                ),
                Line(
                    english: "In a new game on realistic rules, when two trains want the same platform, the one that waited first goes in first.",
                    chinese: "寫實規則的新遊戲：兩列車要進同一座月台時，先等的先進。"
                ),
                Line(
                    english: "Crowds for concerts and games come before the start and after the end, and the news says when the event ends.",
                    chinese: "演唱會、球賽的人潮集中在開場前與散場後；消息卡寫著散場時間。"
                ),
                Line(
                    english: "A line's page and a station's page fill the screen; the list of lines stays beside the map.",
                    chinese: "路線詳情與車站詳情改成全螢幕；路線清單照舊在地圖旁。"
                ),
                Line(
                    english: "On the Hong Kong map, traffic keeps left, with Hong Kong's lights, double-decker buses, minibuses and taxis.",
                    chinese: "香港地圖的街上車靠左，有香港的紅綠燈、雙層巴士、小巴與計程車。"
                ),
                Line(
                    english: "Hong Kong International Airport is on the 3D map, and Hong Kong's buildings have their surveyed shapes and heights.",
                    chinese: "香港國際機場上了 3D 地圖；香港的建物改用政府測量的外形與高度。"
                ),
                Line(
                    english: "Ten of Taipei's temples, Lungshan Temple and Hsing Tian Kong among them, stand on the 3D map in their real shapes.",
                    chinese: "臺北十座寺廟（艋舺龍山寺、行天宮等）照真實外形出現在 3D 地圖。"
                ),
                Line(
                    english: "Stations that have island platforms in real life have them on the demo lines too.",
                    chinese: "示範路線上真實是島式月台的站，現在有島式月台。"
                ),
                Line(
                    english: "On the 3D map the real ground is smoothed first, so roads no longer rise and fall square by square.",
                    chinese: "3D 地圖的實景地面先整平，道路不再一格一格起伏。"
                ),
            ],
            fixes: [
                Line(
                    english: "After you buy a station, the real tracks and trains along that line make way, instead of doubling yours.",
                    chinese: "收購車站後，真實的軌道和列車整條讓開，不再疊成兩套。"
                ),
                Line(
                    english: "Hong Kong's Disneyland Resort Line, the Tseung Kwan O Line to LOHAS Park and the East Rail Line's Lok Ma Chau branch no longer jam.",
                    chinese: "香港迪士尼綫、將軍澳綫（康城）與東鐵綫落馬洲支線不再卡死。"
                ),
                Line(
                    english: "Trains no longer stop for good at a platform they cannot leave, and a stopped train says why.",
                    chinese: "列車不再開進走不下去的月台後一直停著；停住的列車寫得出原因。"
                ),
                Line(
                    english: "Placing a station levels the ground without a word when it can; when it cannot, it says what to do.",
                    chinese: "設站時能整平就直接整平，不再說坡度；整平不了只說一句該怎麼做。"
                ),
                Line(
                    english: "When you place a station the confirm box keeps clear of the line, and the build card no longer shows the price twice.",
                    chinese: "設站時確認框讓開路線；鋪軌的施工卡不再重複金額。"
                ),
                Line(
                    english: "When the list of lines is narrow, its filter and sort show as icons instead of cut-off words.",
                    chinese: "路線清單的工具列放不下字時，篩選與排序改成圖示。"
                ),
                Line(
                    english: "Long names on the build cards are no longer cut off in English.",
                    chinese: "英文的建造卡片，長名稱不再被截斷。"
                ),
                Line(
                    english: "Saving, loading and going back to the main screen are quicker, and large networks run smoother.",
                    chinese: "存檔、讀檔、回主畫面比較快；大路網跑起來比較順。"
                ),
            ]
        ),
        // 130.
        Entry(
            id: "2026-11-14-130",
            items: [
                Line(
                    english: "Hong Kong is a new map, with its buildings in 3D and the MTR’s lines to buy. Start on Taiwan or on Hong Kong; the other opens once an airport that flies there has 500 passengers on your trains in one day.",
                    chinese: "新地圖「香港」，3D 有建物、可收購港鐵。台灣、香港選一張開始；飛另一邊的機場一天有 500 人搭你的列車，另一張就開。"
                ),
                Line(
                    english: "Tap a stretch of track with the select tool to close it: trains take another way or wait. If a train is on it, it closes once the train has passed; you can cancel that, or open the track again.",
                    chinese: "選取工具點一段軌道可以封閉：列車改走別條路或等候；上面有車就等它通過再封，可取消，也能再開放。"
                ),
                Line(
                    english: "In management mode you can take term loans of 1 to 10 years: the rate is fixed when you sign, and you pay it all back when due, or early.",
                    chinese: "經營模式可以借定期貸款：1 到 10 年，利率簽約時固定，到期一次還本付息，也能提前還。"
                ),
                Line(
                    english: "The economy view fills the screen, in four pages: Overview, Loans, Fares and Reports.",
                    chinese: "經濟明細改成全螢幕，分總覽、借款、票價、報表四頁。"
                ),
                Line(
                    english: "A sight's card shows about how many visitors it has in a year, from the Tourism Administration's figures.",
                    chinese: "景點卡片寫著這個景點一年約有多少遊客（交通部觀光署的統計）。"
                ),
                Line(
                    english: "At night on the 3D map the city goes dark: windows, street lights, stations and your tracks and trains are lit.",
                    chinese: "3D 地圖的夜晚：城市暗下來，亮著的是窗戶、路燈、車站，以及你的軌道與列車。"
                ),
                Line(
                    english: "By day the 3D map's roofs are a shade darker and blocks are tinted by what they are used for; station buildings stand out more.",
                    chinese: "3D 地圖白天的屋頂深一些，街廓的地面依用途帶點顏色；站房在地圖上比較清楚。"
                ),
                Line(
                    english: "On real-world maps, blocks with few real buildings get houses along their streets, and the blocks beside Kaohsiung Station are no longer empty.",
                    chinese: "實景地圖上真實建物稀疏的街廓，沿街補上房子；高雄車站旁的街廓不再是空地。"
                ),
                Line(
                    english: "When trains wait at both ends of a single track, the one that waited first goes first, and the other says which train it is letting go first.",
                    chinese: "單線兩端都有列車在等時，先等的先走；讓路的列車會寫「讓某某先走」。"
                ),
                Line(
                    english: "Hong Kong's map has its hills and sea: the 2D map shades the hills, and on the 3D map the ground rises and falls as it really does.",
                    chinese: "香港地圖有了山和海：2D 地圖看得到山影，3D 地圖的地面照真實的高低起伏。"
                ),
                Line(
                    english: "Your company's land now rises with the city round it, and what you build lifts the land nearby: shops lift homes, offices lift shops.",
                    chinese: "公司建物的地會跟著周圍漲；你蓋的東西也帶動附近地價，例如商店讓住宅漲、辦公讓商店漲。"
                ),
                Line(
                    english: "Adding a train to a line also shows about what that train would make a day.",
                    chinese: "加開一列車時，也看得到這列車大約一天賺多少。"
                ),
                Line(
                    english: "A city whose sights your railway brings many visitors to can be titled mostly tourism.",
                    chinese: "鐵道載很多遊客去景點的城市，稱號會是「以觀光為主」。"
                ),
            ],
            fixes: [
                Line(
                    english: "Driving by hand, when you come in too fast for the stopping assist, the stopping bar says so: brake first.",
                    chinese: "手動駕駛進站太快、輔助停車接不了手時，停車條會寫「太快，先煞車」。"
                ),
                Line(
                    english: "With unlimited funds on, loans are paused: you cannot borrow or pay back until you turn it off.",
                    chinese: "資金無限開著時貸款暫停，不能借也不能還，關掉後照常。"
                ),
                Line(
                    english: "Zoomed far out on the 3D map, station buildings no longer disappear, and the outer city no longer comes and goes as you pan.",
                    chinese: "3D 地圖拉遠時，車站的站房不再消失；平移時外圈的城市不會一下有一下沒有。"
                ),
                Line(
                    english: "High speeds run smoother on a network with many trains.",
                    chinese: "列車多的路網，高倍速時比較順。"
                ),
                Line(
                    english: "On double track, a train takes a free platform as it leaves, and no longer flashes deadlocked on every run.",
                    chinese: "複線上的列車發車時就換到空的月台，不再每趟閃一下「互相卡住」。"
                ),
                Line(
                    english: "The 3D map no longer stalls for a moment at midnight, when the day's flights change.",
                    chinese: "3D 地圖過午夜換日時，不再因為換當天航班卡一下。"
                ),
                Line(
                    english: "On real-world maps, the 3D map no longer shows sandy squares beside stations or scattered blue specks on the ground.",
                    chinese: "實景地圖的 3D 地圖上，車站旁不再有土黃色方塊，地上也沒有零星的藍色碎塊。"
                ),
            ]
        ),
        // 129.
        Entry(
            id: "2026-11-13-129",
            items: [
                Line(
                    english: "On real-world maps, the 3D map now shows intercity coaches driving their routes on their timetables, and a coach station at each coach stop.",
                    chinese: "實景地圖的 3D 地圖上，看得到長途客運照班次沿路線行駛，客運站的位置也有一座客運站。"
                ),
                Line(
                    english: "Driving by hand has a stopping assist: slow down first and it brakes the last metres onto the stopping point. A run it helps earns at most half the bonus; turn it off in the view menu.",
                    chinese: "手動駕駛多了輔助停車：先把速度降下來，最後幾公尺幫你停準。用了輔助獎金最多一半，可在視角選單關掉。"
                ),
            ],
            fixes: [
                Line(
                    english: "After a run driven by hand stops, the look from the side stands nearer the train.",
                    chinese: "手動駕駛停穩後從旁邊看成績時，鏡頭離列車近一些。"
                ),
                Line(
                    english: "Opening the 3D map no longer freezes for a moment on a big network.",
                    chinese: "路網大的存檔，開 3D 地圖時不再卡住一下。"
                ),
                Line(
                    english: "Zoomed all the way out, the 3D map fills in everything you can see instead of leaving bare ground, and the view stops at the map's edge.",
                    chinese: "3D 地圖拉到最遠時，看得到的地方都會補上地面與道路，不再留一大片空地；鏡頭也不會拖出地圖外。"
                ),
                Line(
                    english: "The 3D map runs smoother zoomed far out: distant small streets and buildings are left out, main roads, rivers and railways stay.",
                    chinese: "3D 地圖拉遠時比較順：很遠的小路與小建築不畫，幹道、河流、鐵路照舊。"
                ),
            ]
        ),
        // 128.
        Entry(
            id: "2026-11-13-128",
            items: [
                Line(
                    english: "Intercity coaches now run on real-world maps, on their real timetables. Between two stations with a direct coach, some passengers take the coach instead; where a coach stop is beside your station, people getting off change to your trains.",
                    chinese: "實景地圖上，真實的長途客運照班次自己跑：有直達客運的兩站，部分旅客改搭客運；客運站旁有你的車站，下車的人轉搭你的車。"
                ),
                Line(
                    english: "A station that serves a coach stop has an Intercity Coaches section: today's coaches and passengers, and how many changed to or from your trains.",
                    chinese: "服務到客運站的車站，面板多了「長途客運」一節：今天的班次、旅客，以及有多少人和你的列車轉乘。"
                ),
                Line(
                    english: "Jiji and Bao'an station buildings: a station you renamed no longer shows the real station's name on its board.",
                    chinese: "集集、保安站房：你改過名字的車站，站名牌不再寫真實的站名。"
                ),
                Line(
                    english: "Driving by hand: over the last 200 m a stopping bar shows how far the stopping point is and whether you passed it, a marker stands beside the track, and once stopped you see the train from the side with your result.",
                    chinese: "手動駕駛進站最後 200 公尺有停車條，看離停車點多遠、有沒有過頭；軌道旁有停車標，停穩後從旁邊看成績。"
                ),
                Line(
                    english: "Laying track now tells you once that holding the height figure and sliding raises or lowers that end. The station master's advice shows when a tap takes you there, and the train diagram says how to zoom.",
                    chinese: "鋪軌時會提示一次：按住高度那一格上下滑可架高或挖低。站長的建議能點的有記號；運行圖寫了怎麼縮放。"
                ),
            ],
            fixes: [
                Line(
                    english: "The 3D map draws far less on a large network with many bought real lines: it uses about a third less memory and runs smoother.",
                    chinese: "路網大、買了很多真實路線時，3D 地圖畫的東西少很多：記憶體少用約三分之一，也比較順。"
                ),
                Line(
                    english: "A high-speed line laid with Lay the real lines here now runs high-speed trains at high-speed line speeds; metro, light rail and the Alishan line run their own trains too. Lines laid earlier change when laid again.",
                    chinese: "用「鋪好這一帶的真實路線」鋪的高鐵現在是高鐵車與高鐵的速度；捷運、輕軌、林鐵也是自己的車。舊的線要重鋪才換。"
                ),
                Line(
                    english: "The Airport MRT can be bought wherever your map starts, and Kaohsiung's metro runs trains when laid with Lay the real lines here.",
                    chinese: "機場捷運不論開局選哪裡都買得成；用「鋪好這一帶的真實路線」鋪的高雄捷運有車在跑了。"
                ),
                Line(
                    english: "Aircraft no longer jump to new places at midnight.",
                    chinese: "午夜時飛機不再突然換位置。"
                ),
                Line(
                    english: "The collection's Aircraft page and the Attractions panel open faster, and tapping an aircraft opens that one.",
                    chinese: "圖鑑飛機頁與觀光景點面板開得比較快；點哪一架飛機就開哪一架。"
                ),
                Line(
                    english: "The driving lever no longer jumps after a drag is interrupted.",
                    chinese: "駕駛拉桿拖到一半被打斷後不會亂跳。"
                ),
                Line(
                    english: "Tapping a station with an aircraft taxiing nearby selects the station.",
                    chinese: "車站旁有飛機滑行時，點車站就是選車站。"
                ),
            ]
        ),
        // 127 (and 124 to 126, which went out without an entry).
        Entry(
            id: "2026-11-12-127",
            items: [
                Line(
                    english: "On the 3D map, airports have runways, aprons and terminals; aircraft park at the stands and take off and land with the day's flights, and the runway lights come on at night.",
                    chinese: "3D 地圖看得到機場：跑道、停機坪、航廈，飛機停在機位上，也照當天航班起降，晚上跑道有燈。"
                ),
                Line(
                    english: "Real-world maps have 12 airports. Build a station where trains call within 800 m of a terminal and its passengers ride your trains.",
                    chinese: "實景地圖共有 12 座機場。在航廈 800 公尺內蓋一座有列車停靠的車站，旅客就搭你的車。"
                ),
                Line(
                    english: "Tap an airport on the map to see today's flights, domestic and international passengers, and where the flights go.",
                    chinese: "點地圖上的機場，看今天的航班、國內線與國際線旅客，還有飛往哪裡各幾班。"
                ),
                Line(
                    english: "Tap an aircraft that is moving on the 3D map to follow it: from behind, from the side or from a cabin window. At night its lights are on.",
                    chinese: "在 3D 地圖點一架在動的飛機就能跟著看：後方、旁邊、機艙窗；晚上機身有燈。"
                ),
                Line(
                    english: "The collection has an Aircraft page: four aircraft and two airports to look at in 3D, and the airports of your map.",
                    chinese: "圖鑑多了「飛機」頁：四種飛機和兩座機場可以近看 3D，還有這張地圖的機場。"
                ),
                Line(
                    english: "Drive a train yourself: follow one on the 3D map, tap Drive and bring it to a stop at the next station. A good stop on time earns a bonus.",
                    chinese: "手動駕駛：在 3D 地圖跟著一列車按「駕駛」，開到下一站停好；停得準又準點有獎金。"
                ),
                Line(
                    english: "While you drive, the next station is in a bar at the top and the speed and the lever are at the edge, so the track ahead stays clear.",
                    chinese: "駕駛時下一站在上方一條，速度與拉桿在邊上，前方的軌道不再被擋住。"
                ),
                Line(
                    english: "Jiji and Bao'an stations have their real wooden station buildings on the 3D map.",
                    chinese: "集集、保安車站在 3D 地圖換成真的木造站房。"
                ),
                Line(
                    english: "A new building, the Railway Museum: its red-brick hall shows the trains your company has owned, and you can walk through the exhibits.",
                    chinese: "新建物「鐵道博物館」：紅磚館舍展示公司擁有過的車，可以進館一件一件看。"
                ),
                Line(
                    english: "A station's platforms can be made longer without removing them first, and so can a track added with Platform Track.",
                    chinese: "車站的月台可以直接加長，不用先拆；用「月台軌道」加的那一股也可以。"
                ),
                Line(
                    english: "Before you buy trains, you are told about how much they will earn a day.",
                    chinese: "買車時先告訴你這些車大約一天賺多少。"
                ),
                Line(
                    english: "A building's card shows what you paid and what it is worth now.",
                    chinese: "建物卡看得到當初花多少、現在值多少。"
                ),
                Line(
                    english: "Cities have a size title and a type, at the bottom of Goals, and you are told when a city moves up.",
                    chinese: "城市有規模稱號與類型，在「目標」最下面；城市升級時會告訴你。"
                ),
                Line(
                    english: "The 3D map shows underground lines: trains in tunnels with their headlights on the walls.",
                    chinese: "3D 地圖看得到地下：隧道裡的列車，車頭燈照在牆上。"
                ),
                Line(
                    english: "Buttons and panels have sounds, and reaching a goal plays a short tune.",
                    chinese: "按鈕與面板有聲音，達成目標時有一段短音樂。"
                ),
                Line(
                    english: "The app icon and the map's floating buttons have the new glass look.",
                    chinese: "App 圖示與地圖上的浮動按鈕換成新的玻璃樣式。"
                ),
            ],
            fixes: [
                Line(
                    english: "A large network with many trains runs more smoothly.",
                    chinese: "路網大、列車多的時候比較順。"
                ),
                Line(
                    english: "The 3D map runs more smoothly in rain.",
                    chinese: "3D 地圖下雨時比較順。"
                ),
                Line(
                    english: "Selling a building and rebuilding it every year no longer makes money.",
                    chinese: "每年把建物賣掉再重蓋，不再穩賺。"
                ),
                Line(
                    english: "Attractions you can reach by building a station are no longer folded away as outside the map.",
                    chinese: "自己蓋車站到得了的景點，不再收進地圖外。"
                ),
                Line(
                    english: "On the Neiwan Line, the stationmaster's advice now matches the goals.",
                    chinese: "內灣線站長的建議和目標一致了。"
                ),
                Line(
                    english: "In the museum, a train type bought today is listed as not yet on show instead of not yet owned.",
                    chinese: "博物館裡今天剛買的車種寫「還沒展出」，不再寫「還沒擁有」。"
                ),
            ]
        ),
        // 123.
        Entry(
            id: "2026-11-09-123",
            items: [
                Line(
                    english: "The 3D map has nine more real station buildings: Keelung, Chiayi, Tainan, Beimen, Fenqihu, Alishan, Wushulin, Xihu and Qiaotou.",
                    chinese: "3D 地圖多了 9 座真實站房：基隆、嘉義、臺南、北門、奮起湖、阿里山、烏樹林、溪湖、橋頭。"
                ),
                Line(
                    english: "A new challenge, Neiwan Line: Into the Hakka Hills, with three new characters: Granny Peng, Uncle Luo and Xiaoyu.",
                    chinese: "新挑戰「內灣線：駛進客家山城」，有三個新角色：彭阿婆、阿羅伯、小宇。"
                ),
                Line(
                    english: "On the 3D map, temples, courtyard houses and old shophouses have Chinese roofs and red-brick fronts, and Keelung South station's canopy has its roof frame and skylights.",
                    chinese: "3D 地圖的廟宇、三合院、老街屋有中式屋頂與紅磚立面；基隆南站雨棚有屋頂結構與天窗。"
                ),
                Line(
                    english: "Electric trains hum as they speed up and brake, and go quiet when coasting.",
                    chinese: "電車加速和煞車時有馬達聲，惰行時安靜。"
                ),
                Line(
                    english: "When you cannot afford a building, the message says where nearby it costs less.",
                    chinese: "錢不夠蓋建物時，說明會指出附近哪裡蓋得起。"
                ),
                Line(
                    english: "The tourism page says what attractions do, and the ones outside your map are folded away.",
                    chinese: "觀光頁只說景點做什麼，地圖外的景點收起來。"
                ),
                Line(
                    english: "On the high-speed demo, the fares page shows the high-speed fares passengers pay.",
                    chinese: "高鐵示範的票價頁寫出旅客實際付的高鐵票價。"
                ),
                Line(
                    english: "When the tutorial ends, you are told how to pass the first lesson.",
                    chinese: "教學結束時告訴你第 1 關怎麼過關。"
                ),
                Line(
                    english: "On iPad in Split View or Slide Over, sheets open at half height so the map stays in view.",
                    chinese: "iPad 分割畫面或 Slide Over 時，下半卡開半高，看得到地圖。"
                ),
            ],
            fixes: [
                Line(
                    english: "The Taoyuan Airport MRT can be rebuilt right after the first night's last train, a day sooner.",
                    chinese: "機場捷運第一晚收班後就能改建，早一天。"
                ),
                Line(
                    english: "On the Taoyuan Airport MRT, trains between Huanbei and Airport Terminal 1 now run on the second afternoon, and far fewer trips are missed all day.",
                    chinese: "機場捷運第 2 天下午環北到機場第一航廈不再停開，全天沒發的班次少很多。"
                ),
                Line(
                    english: "From the second lesson on, platform mode can remove platforms again.",
                    chinese: "教學第 2 課起，月台模式又能拆月台。"
                ),
                Line(
                    english: "The speed hint no longer closes a route map or other window you have open.",
                    chinese: "倍速提示不會再把開著的路線圖等畫面關掉。"
                ),
                Line(
                    english: "Opening the map and laying track leave the screen less busy, so it answers sooner.",
                    chinese: "開地圖和鋪軌後背景少算很多，畫面比較快有反應。"
                ),
                Line(
                    english: "On a Mac, settings say Mac.",
                    chinese: "在 Mac 上，設定寫 Mac。"
                ),
                Line(
                    english: "Correction to the last build: tapping a station is no quicker; what got faster are the passenger arcs of stations and lines on the map.",
                    chinese: "更正上一版：點車站本身沒有變快；變快的是地圖上車站和路線的旅客去向弧線。"
                ),
                Line(
                    english: "Correction to the last build: only the Taoyuan Airport MRT can be rebuilt as the real railway, at Chang Gung Hospital.",
                    chinese: "更正上一版：照真實改建只有機場捷運的長庚醫院站一段。"
                ),
                Line(
                    english: "Correction to the last build: the Taoyuan Airport MRT jams much less, not never; the extra trips are under simple rules, and a few evening trips still do not run.",
                    chinese: "更正上一版：機場捷運卡住少很多，但沒有完全不卡；多開的班次是簡單規則下的，傍晚仍有幾班沒開。"
                ),
                Line(
                    english: "Correction to an earlier build: the cab window view glides at 10× and 60×; 1× is unchanged.",
                    chinese: "更正之前的版本：車窗視角滑行連貫的是 10 倍速和 60 倍速，1 倍速沒有改。"
                ),
                Line(
                    english: "Correction to an earlier build: on the Kaohsiung Circular Light Rail, empty trains run shorter distances, not fewer trips.",
                    chinese: "更正之前的版本：高雄環狀輕軌的空車是跑得比較短，趟數沒有變少。"
                ),
            ]
        ),
        // 122.
        Entry(
            id: "2026-11-08",
            items: [
                Line(
                    english: "Track height is now set right on the preview bar: press and drag the ↕ cell up or down to change the end height in metres.",
                    chinese: "鋪軌時按住上方預覽列的「↕」格上下滑，就能調終點高度（公尺）。"
                ),
                Line(
                    english: "The real lines for sale are listed nearest first, and the ones you cannot buy yet are greyed out with how far away they are.",
                    chinese: "可買的真實路線依距離由近到遠排，買不到的灰掉，並寫約幾公里外。"
                ),
                Line(
                    english: "The Taoyuan Airport MRT you already bought can be rebuilt as the real railway at Chang Gung Hospital; if something is in the way, the card says where.",
                    chinese: "已收購的機場捷運可選擇照真實改建長庚醫院站一段，被擋住時會說哪裡。"
                ),
                Line(
                    english: "The 3D map opens on the nearest track when you open it with the whole island in view, shows the game clock in the corner, and distant windows now light up at night.",
                    chinese: "從全台進 3D 會開在最近的軌道上；角落有遊戲時鐘，遠處夜窗也會亮。"
                ),
                Line(
                    english: "Taiwan Railway has the new timetable, and Tainan station and its tracks are now drawn underground, as they have been since the line moved underground.",
                    chinese: "臺鐵換上台南地下化後的新時刻表，臺南站與鄰近軌道改畫成地下。"
                ),
                Line(
                    english: "Track numbers also keep clear of station circles and waiting-passenger bubbles.",
                    chinese: "軌道編號也避開站點圓圈和候車人數泡泡。"
                ),
                Line(
                    english: "The train card has Follow beside its title, and the game menu has a Trains and 3D City entry.",
                    chinese: "列車卡的「跟隨」移到標題旁；☰ 選單新增「列車與 3D 城市」。"
                ),
                Line(
                    english: "On iPad, the tutorial frames both towns, sheets use the full height, settings say iPad, and the start screen has two columns.",
                    chinese: "iPad 上教學框住兩座城鎮、下半卡開成全高、設定寫對裝置、開始畫面分兩欄。"
                ),
            ],
            fixes: [
                Line(
                    english: "The passenger arcs of a station or a line appear on the map much sooner.",
                    chinese: "地圖上車站和路線的旅客去向弧線出現得快很多。"
                ),
                Line(
                    english: "After you buy a large line such as the Wenhu line, fast speeds keep up again.",
                    chinese: "收購文湖線這類大路線後，高倍速又跑得動了。"
                ),
                Line(
                    english: "The map library is upgraded, which fixes a possible crash while labels are drawn.",
                    chinese: "地圖套件升級，修掉一個畫站名時可能的當機。"
                ),
                Line(
                    english: "The line page no longer zooms out to the whole island, and the first message of a new line counts trains and stops correctly.",
                    chinese: "路線頁不再縮到整個台灣；開線訊息照實際列數和站數寫。"
                ),
                Line(
                    english: "A bought line shows its first-day loss correctly, and a waiting train's label names the blocking train only once.",
                    chinese: "收購當天的虧損算對了；等進路標籤只在最近一列寫擋住的車名。"
                ),
                Line(
                    english: "A train following another no longer stops on track the line only uses the other way, so the Taoyuan Airport MRT jams much less.",
                    chinese: "跟著前車走的列車不再停在逆向軌道上，機場捷運互等卡死少很多。"
                ),
                Line(
                    english: "A newly bought Taoyuan Airport MRT now runs about fourteen more trips a day, because trains ending at Airport Terminal 1 can wait at another platform and mostly no longer block the express.",
                    chinese: "現在買下機場捷運，每天多開約十四班；在第一航廈站結束的車停到另一個月台，大多不再卡住直達車。"
                ),
            ]
        ),
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
                    english: "On the high-speed demo, Liujia Depot now sits north of the Touqian River instead of over the water.",
                    chinese: "高鐵示範的六家基地收在頭前溪北岸，不再蓋在河上。"
                ),
            ]
        ),
        // 120.
        Entry(
            id: "2026-11-07-120",
            items: [
                Line(
                    english: "The tracks into a depot you build now fan out like a real train yard.",
                    chinese: "自己蓋的機廠，進出的分岔改成像真實車場的扇形。"
                ),
                Line(
                    english: "The high-speed demo's northern end now has Nangang Sidings and Liujia Depot beside Hsinchu, laid out as in real life.",
                    chinese: "高鐵示範北端：南港留置線和新竹旁的六家基地，照真實配置。"
                ),
                Line(
                    english: "On the Kaohsiung Circular Light Rail, the depot's tracks now run in a strip along the line like the real Light Rail Depot, so empty trains run shorter distances.",
                    chinese: "高雄環狀輕軌的機廠照真實輕軌機廠沿線排成一條帶，空車跑得比較短。"
                ),
                Line(
                    english: "The 3D map shows road tunnel mouths, and lights glow at night.",
                    chinese: "3D 地圖多了公路隧道口，晚上的燈有光暈。"
                ),
            ],
            fixes: [
                Line(
                    english: "At 10× speed game time keeps up, even with trains waiting at stations to depart.",
                    chinese: "10 倍速時遊戲時間跟得上，有車在站上等出發也不再拖慢。"
                ),
                Line(
                    english: "Correction to the last build: the cab window view only now glides smoothly instead of jerking, at 10× and 60×.",
                    chinese: "更正上一版：車窗視角走走停停，這一版才真的改好，10 倍速和 60 倍速都滑行連貫。"
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
                    english: "The Changhua Roundhouse now has locomotives parked in its stalls.",
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
                    english: "The Taoyuan Airport MRT joins the real-world maps: you can buy it and run its timetable.",
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
                    english: "Taiwan's named festivals are on the real-world maps: Dajia Mazu, the Pingxi lanterns, New Year's Eve at Taipei 101 and the Mid-Autumn Festival bring extra riders to nearby stations. Mazu, the lanterns and Mid-Autumn follow the lunar calendar.",
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
                    english: "The Wenhu Line can be bought on the real-world maps of Taipei, New Taipei and Taoyuan, with the Muzha depot by the zoo.",
                    chinese: "台北、新北、桃園的實景地圖可以收購捷運文湖線，連同動物園旁的木柵機廠。"
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
                    english: "Taiwan Railway trains on the real-world map run to the real train-by-train timetable.",
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
                    english: "The DR3100 diesel express runs four times a day on the real-world map.",
                    chinese: "實景地圖每天多跑四班 DR3100 柴聯自強號。"
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
                    english: "Following a train on the 3D map at 10× speed is smoother.",
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
                    english: "Bubbles, fares, prices and place names on the map no longer cover each other, and the whole of Taiwan comes first when you pick a real-world map.",
                    chinese: "地圖上的泡泡、票價、價錢和地名不再互相蓋住；選實景地圖時，「整個臺灣」排在第一個。"
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
                    english: "3D depots have maintenance sheds, and the Changhua Roundhouse has its turntable.",
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
