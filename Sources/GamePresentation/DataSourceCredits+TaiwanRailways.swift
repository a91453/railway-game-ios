// The data sources page: Taiwan's railways and the railway data behind them.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// Taiwan's railways, each system on its own.
    /// What the real railways on the map are, and where each
    /// system's data comes from (`RealRailways.System.all`).
    static func taiwanRailwaysSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "railways",
            title: language.text("Taiwan’s Railways", "台灣的鐵道"),
            credits: [
                DataSourceCredit(
                    id: "realRailways",
                    title: language.text("The real railways on the map", "地圖上的真實鐵道"),
                    detail: language.text(
                        "Real-world maps of Taiwan show the lines and stations of the railways below; Real Railways in the map style menu fades or hides them. With Real Trains on in Settings, their trains run on the map to their timetables.",
                        "台灣的實景地圖畫出下面各家鐵道的路線與車站，地圖樣式選單的「真實鐵道」可以調淡或隱藏。打開設定的「真實列車」，它們的列車會照時刻表在地圖上跑。"
                    ),
                    notice: language.text(
                        "Every line’s track and station positions follow OpenStreetMap’s track, and the platforms of the stations you can buy its platforms (© OpenStreetMap contributors, ODbL 1.0); the few stretches where OpenStreetMap is out of date or has no track follow MOTC TDX. Where each line’s station order, names, colours and times come from is under its operator below.",
                        "每條線的軌道走向與車站位置照 OpenStreetMap 的軌道畫，可以買的車站的月台照 OpenStreetMap 的月台（© OpenStreetMap 貢獻者，ODbL 1.0），少數 OpenStreetMap 過時或沒有軌道的路段照交通部 TDX。各線的站序、站名、路線色與時刻從哪裡來，寫在下面各營運機構。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "tra",
                    title: language.text("TRA", "台鐵"),
                    detail: language.text(
                        "The Western Trunk, Mountain, Coast, Chengzhui, Pingtung, South-Link, Taitung, North-Link and Yilan Lines, and six branch lines: Pingxi, Shenao, Neiwan, Liujia, Jiji and Shalun, all in TRA blue. On a real-world map you can buy the six branch lines, and their trains keep TRA’s real times.",
                        "縱貫線、山線、海線、成追線、屏東線、南迴線、台東線、北迴線、宜蘭線，以及平溪、深澳、內灣、六家、集集、沙崙六條支線，全部畫成台鐵藍。實景地圖上可以買下這六條支線，列車照台鐵的真實時刻開。"
                    ),
                    notice: language.text(
                        "Station order and names: TRA’s published station order. Colour: the blue of TRA’s logo. Branch line times: TRA open data.",
                        "站序與站名：台鐵公布的站序。路線色：台鐵標誌的藍色。支線時刻：台鐵開放資料。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "thsr",
                    title: language.text("High Speed Rail", "高鐵"),
                    detail: language.text(
                        "The line from Nangang to Zuoying and its 12 stations, in the High Speed Rail’s orange. The High-Speed Rail Demo and Real Trains run to its real timetable of 29 September 2026, and the demo charges its real fares.",
                        "南港到左營的高鐵線與 12 個車站，畫成高鐵橘。高鐵示範與真實列車照 2026 年 9 月 29 日的真實班表開，示範的票價也是高鐵的票價。"
                    ),
                    notice: language.text(
                        "Station order, names, timetable and fares: MOTC TDX. Colour: the orange of the High Speed Rail’s logo.",
                        "站序、站名、班表與票價：交通部 TDX。路線色：高鐵標誌的橘色。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "afr",
                    title: language.text("Alishan Forest Railway", "阿里山林鐵"),
                    detail: language.text(
                        "The Main Line from Chiayi to Alishan and the Shenmu, Zhaoping and Zhushan Lines, in the Alishan Forest Railway’s red.",
                        "本線（嘉義到阿里山）、神木線、沼平線與祝山線，畫成阿里山林鐵紅。"
                    ),
                    notice: language.text(
                        "Station order and names: MOTC TDX. Colour: the red of the Alishan Forest Railway’s logo.",
                        "站序與站名：交通部 TDX。路線色：阿里山林鐵標誌的紅色。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "taipeiMetro",
                    title: language.text("Taipei Metro", "台北捷運"),
                    detail: language.text(
                        "The Wenhu, Tamsui–Xinyi (with the Xinbeitou branch), Songshan–Xindian (with the Xiaobitan branch), Zhonghe–Xinlu and Bannan Lines, each in its own colour.",
                        "文湖線、淡水信義線（含新北投支線）、松山新店線（含小碧潭支線）、中和新蘆線與板南線，每條線用自己的路線色。"
                    ),
                    notice: language.text(
                        "Station order and names: MOTC TDX. Colours: Taipei Metro’s website. Times: MOTC TDX’s station timetables; the Wenhu Line’s are set from its official headways and first and last trains.",
                        "站序與站名：交通部 TDX。路線色：台北捷運官網。時刻：交通部 TDX 的各站時刻表；文湖線照官方班距與首末班車排出。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "newTaipeiMetro",
                    title: language.text("New Taipei Metro", "新北捷運"),
                    detail: language.text(
                        "All four of its lines: the Circular Line, the Danhai Light Rail (Green Mountain and Blue Coast Lines), the Ankeng Light Rail and the Sanying Line, each in its own colour. On the map the Circular Line is grouped with Taipei Metro’s lines.",
                        "四條線都有：環狀線、淡海輕軌（綠山線與藍海線）、安坑輕軌與三鶯線，每條線用自己的路線色。地圖上環狀線跟台北捷運的路線歸在一起。"
                    ),
                    notice: language.text(
                        "Station order and names: MOTC TDX; the Sanying Line’s from New Taipei Metro’s website. Colours: the Circular Line’s from Taipei Metro’s website, the other three from MOTC TDX. Times: MOTC TDX’s station timetables; the Sanying Line’s are set from New Taipei Metro’s announced headways and TDX’s times between stations.",
                        "站序與站名：交通部 TDX；三鶯線取自新北捷運官網。路線色：環狀線取自台北捷運官網，其他三線取自交通部 TDX。時刻：交通部 TDX 的各站時刻表；三鶯線照新北捷運公告的班距與 TDX 的站間時間排出。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "taoyuanMetro",
                    title: language.text("Taoyuan Airport MRT", "桃園機捷"),
                    detail: language.text(
                        "The Airport MRT from Taipei Main Station to Laojie River, with its commuter and express trains at their real times.",
                        "台北車站到老街溪的機場捷運，普通車與直達車都照真實時刻跑。"
                    ),
                    notice: language.text(
                        "Station order, names and times: MOTC TDX. Colour: MOTC TDX.",
                        "站序、站名與時刻：交通部 TDX。路線色：交通部 TDX。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "taichungMetro",
                    title: language.text("Taichung Metro", "台中捷運"),
                    detail: language.text(
                        "The Green Line (Wuri–Wenxin–Beitun) from Beitun Main Station to HSR Taichung Station.",
                        "綠線（烏日文心北屯線），北屯總站到高鐵台中站。"
                    ),
                    notice: language.text(
                        "Station order and names: MOTC TDX. Colour: MOTC TDX. Times: set from TDX’s official headways and first and last trains.",
                        "站序與站名：交通部 TDX。路線色：交通部 TDX。時刻：照 TDX 的官方班距與首末班車排出。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "kaohsiungMetro",
                    title: language.text("Kaohsiung Metro", "高雄捷運"),
                    detail: language.text(
                        "The Red Line, the Orange Line and the Circular Light Rail, each in its own colour.",
                        "紅線、橘線與環狀輕軌，每條線用自己的路線色。"
                    ),
                    notice: language.text(
                        "Station order and names: MOTC TDX. Colours: Kaohsiung Metro’s website. Times: MOTC TDX’s station timetables.",
                        "站序與站名：交通部 TDX。路線色：高雄捷運官網。時刻：交通部 TDX 的各站時刻表。"
                    ),
                    links: []
                ),
                DataSourceCredit(
                    id: "operators",
                    title: language.text("Names and operators", "名稱與營運機構"),
                    detail: language.text(
                        "The English line and station names are compiled by \(GameBrand.current.english).",
                        "英文的路線名與站名由《\(GameBrand.current.chinese)》整理。"
                    ),
                    notice: language.text(
                        "The game is not affiliated with any of the operators above.",
                        "本遊戲與上列各營運機構沒有任何關係。"
                    ),
                    links: []
                ),
            ]
        )
    }

    /// The datasets behind the railways above, each with the notice
    /// its licence asks for.
    static func railwayDataSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "railwayData",
            title: language.text("Railway Data", "鐵道資料"),
            credits: [
                DataSourceCredit(
                    id: "tdx",
                    title: language.text(
                        "MOTC Transport Data eXchange (TDX)",
                        "交通部運輸資料流通服務平臺（TDX）"
                    ),
                    detail: language.text(
                        "Most of the station order, station names, station codes and addresses above; the High Speed Rail’s, the metros’ and the light rails’ timetables; the High-Speed Rail Demo’s fares; some lines’ colours; and Taiwan Railway’s on-time rate over the past year, shown beside a line’s.",
                        "上面大部分路線的站序、站名、車站代碼與地址，高鐵、捷運與輕軌的時刻表，高鐵示範的票價，部分路線的路線色，以及路線卡上台鐵近一年的準點率。"
                    ),
                    notice: language.text(
                        "Ministry of Transportation and Communications, Transport Data eXchange (TDX), 2026: rail stations, lines, station order of lines, line shapes, travel times between stations, headways, station timetables, the High Speed Rail’s daily timetable and its origin–destination fares; Taiwan Railway’s live train delays, 20 November 2025 to 26 October 2026. ",
                        "交通部運輸資料流通服務平臺（TDX）2026 年軌道車站、路線、路線站序、路線線型、站間行駛時間、班距、車站時刻表、高鐵每日時刻表與高鐵起訖站票價；臺鐵列車即時誤點（2025 年 11 月 20 日至 2026 年 10 月 26 日）"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: "TDX", url: tdxURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 400 (10i-3): the real bus routes
                // (`tools/real-buses/`), TDX's through the owner's
                // reference and, for Taipei City and Pingtung County,
                // straight from TDX.
                DataSourceCredit(
                    id: "realBuses",
                    title: language.text("Bus routes", "公車路線"),
                    detail: language.text(
                        "Taiwan’s real city and county bus routes: their stops in order, the roads they take and how often they run. Where a route has no timetable, its headway is an estimate and says so.",
                        "台灣真實的市區與縣市公車路線：依序的站牌、走的路線與班距。沒有班表的路線，班距是估計的，會寫出來。"
                    ),
                    notice: language.text(
                        "Ministry of Transportation and Communications, Transport Data eXchange (TDX), 2026: city and county bus routes, stops of routes, route shapes and schedules. ",
                        "交通部運輸資料流通服務平臺（TDX）2026 年市區與縣市公車路線、路線站序、路線線型與班表"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: "TDX", url: tdxURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 706: the real intercity coaches
                // (`tools/real-coaches/`), straight from TDX.
                DataSourceCredit(
                    id: "realCoaches",
                    title: language.text("Intercity coach routes", "長途客運路線"),
                    detail: language.text(
                        "Taiwan’s real freeway coaches and long highway buses between cities: their stops in order, the roads they take, when they leave and their fares.",
                        "台灣真實的國道客運與跨縣市的公路客運：依序的站牌、走的路線、發車時刻與票價。"
                    ),
                    notice: language.text(
                        "Ministry of Transportation and Communications, Transport Data eXchange (TDX), 2026: highway bus routes, stops of routes, route shapes, schedules and fares. ",
                        "交通部運輸資料流通服務平臺（TDX）2026 年公路客運路線、路線站序、路線線型、班表與票價"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: "TDX", url: tdxURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "traOpenData",
                    title: language.text("TRA open data", "台鐵開放資料"),
                    detail: language.text(
                        "The real times of TRA’s trains: every TRA train of a week on a real-world map and the next trains on its station cards, the Pingxi Line in the Real-World Demo, the Yilan Line in the TRA Demo, and the six branch lines you can buy on a real-world map.",
                        "台鐵列車的真實時刻：實景地圖上一週的每一班台鐵列車與車站卡的下一班、實景示範的平溪線、台鐵示範的宜蘭線，以及實景地圖上可以買下的六條支線。"
                    ),
                    notice: language.text(
                        "Taiwan Railway Corporation, 2026: train timetables, from TRA open data (ods.railway.gov.tw). ",
                        "國營臺灣鐵路股份有限公司 2026 年列車時刻表，取自臺鐵開放資料 ods.railway.gov.tw"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: language.text("TRA open data", "臺鐵開放資料"), url: traOpenDataURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 279: through the reference's
                // `level-profiles.json`, the official railway,
                // high-speed railway and metro geometry that fills in
                // OpenStreetMap's bridges and tunnels.
                DataSourceCredit(
                    id: "nlsc",
                    title: language.text("National Land Surveying and Mapping Center", "內政部國土測繪中心"),
                    detail: language.text(
                        "Which stretches of the TRA, the High Speed Rail, the metros and the light rails are on bridges and viaducts or in tunnels: the demos’ track and the track you trace along a real railway rise and dip to match.",
                        "台鐵、高鐵、捷運與輕軌哪些路段在橋上、高架上或隧道裡：示範地圖的軌道，以及你沿真實鐵路描的軌道，照著蓋高架與隧道。"
                    ),
                    notice: language.text(
                        "National Land Surveying and Mapping Center, Ministry of the Interior, 2026: Taiwan Railway, High Speed Railway and Mass Rapid Transit. ",
                        "內政部國土測繪中心 2026 年臺灣鐵路、高速鐵路、捷運"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: language.text("Taiwan Railway (data.gov.tw)", "臺灣鐵路（政府資料開放平臺）"), url: nlscRailwayURL),
                        DataSourceCredit.Link(title: language.text("High Speed Railway (data.gov.tw)", "高速鐵路（政府資料開放平臺）"), url: nlscHighSpeedRailURL),
                        DataSourceCredit.Link(title: language.text("Mass Rapid Transit (data.gov.tw)", "捷運（政府資料開放平臺）"), url: nlscMetroURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "openStreetMap",
                    title: "OpenStreetMap",
                    detail: language.text(
                        "Railways: the track, where stations and platforms stand, single or double track, bridges and tunnels. Real-world maps: the settlements, villages, townships, landmarks and roads new stations are named after, industrial land, parks, farmland, rivers, lakes and the coast, tourist sights, and the shops, schools and other places round new stations. Demos: the High-Speed Rail Demo’s depots and end-station tracks, and the TRA Demo’s Yilan and Su'aoxin sidings. The 3D city preview’s roads, parks and shop names. The 3D map’s real station buildings: the outline of each.",
                        "鐵道：軌道走向、車站與月台的位置、單線或雙線、橋與隧道。實景地圖：新車站取名用的聚落、村里、鄉鎮、地標與道路，工業區、公園、農地、河川、湖泊與海岸線，觀光景點，以及新車站附近的商店、學校等地點。示範地圖：高鐵示範的機廠與端點站股道、台鐵示範的宜蘭、蘇澳新側線。3D 城市預覽的道路、公園與店名。3D 地圖裡真實車站站房的外形。"
                    ),
                    // The ODbL asks for the derived files to be offered
                    // under the same licence: they ship in the app and
                    // the mailbox below is the written offer (decision 503).
                    notice: language.text(
                        "© OpenStreetMap contributors, under the Open Database License (ODbL) 1.0. The data files the game derives from it come with the app, and a complete machine-readable copy under the same licence is available by writing to \(mailbox.english).",
                        "© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用。遊戲據此整理的資料檔隨 App 提供，也可來信\(mailbox.chinese)索取以相同授權提供的完整機器可讀檔案。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                        DataSourceCredit.Link(title: "ODbL 1.0", url: odblURL),
                    ]
                ),
            ]
        )
    }
}
