// The data sources page: people, riders, weather and buildings' footprints.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// People and riders: where the population, the ridership, the
    /// weather and the buildings' footprints come from.
    static func peopleSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "population",
            title: language.text("People and Riders", "人口與旅客"),
            credits: [
                // Decision 1002 (TAIWAN-CENSUS-GRID): the government's
                // own counts of where people live and work, in place of
                // WorldPop's estimate (`tools/census-grid/`).
                DataSourceCredit(
                    id: "taiwanCensus",
                    title: language.text("Where Taiwan lives and works", "台灣住與上班的人"),
                    detail: language.text(
                        "How many people live and work round a station you build on a real-world map of Taiwan, and so how many riders it gets and whether they come in the morning or go home in the evening. The population grid layer shows the same people.",
                        "在台灣實景地圖上蓋車站時，車站周圍住多少人、多少人在那裡上班，因此有多少旅客、早上來還是傍晚回家。人口網格圖層畫的也是這些人。"
                    ),
                    notice: language.text(
                        "Ministry of the Interior, Department of Statistics: population of the basic statistical areas (December 2024) and the basic statistical areas’ boundaries; Ministry of the Interior, Department of Household Registration: households and population by village (December 2020); Directorate-General of Budget, Accounting and Statistics: the 2020 Population and Housing Census (residents by township) and the 2021 Industry, Commerce and Service Census (persons engaged by township). Used under the Open Government Data License, version 1.0. The game spreads each area’s people over its buildings, and each township’s jobs over OpenStreetMap’s shops, offices, schools, sights and industrial land (© OpenStreetMap contributors, ODbL 1.0), on cells of about 230 m.",
                        "內政部統計處「統計區人口統計_最小統計區」（113 年 12 月）與「最小統計區圖」、內政部戶政司「村里戶數、單一年齡人口」（109 年 12 月）、行政院主計總處「109 年人口及住宅普查」（各鄉鎮市區常住人口）與「110 年工業及服務業普查」（各鄉鎮市區從業員工），依「政府資料開放授權條款第 1 版」使用。遊戲把每區的人分到區內的建物，每個鄉鎮市區的上班人數分到 OpenStreetMap 的店家、辦公室、學校、景點與工業區（© OpenStreetMap 貢獻者，ODbL 1.0），每格約 230 公尺。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Statistical areas’ population", "統計區人口統計"), url: "https://data.gov.tw/dataset/18681"),
                        DataSourceCredit.Link(title: language.text("Statistical areas’ boundaries", "最小統計區圖"), url: "https://data.gov.tw/dataset/25128"),
                        DataSourceCredit.Link(title: language.text("Population by village", "村里戶數、單一年齡人口"), url: "https://data.gov.tw/dataset/77132"),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 298: the real stations' riders a day, which
                // the transfers of a station by one follow
                // (`tools/real-ridership/`).
                DataSourceCredit(
                    id: "ridership",
                    title: language.text("Riders by station", "各站運量"),
                    detail: language.text(
                        "How many people use each station of the TRA, the High Speed Rail, Taipei Metro, New Taipei Metro’s four lines, the Taoyuan Airport MRT, Taichung Metro and Kaohsiung Metro’s Red and Orange Lines a day: build a station beside one, and riders change to it in proportion.",
                        "台鐵、高鐵、台北捷運、新北捷運四條線、桃園機捷、台中捷運與高雄捷運紅橘線各站每天進出多少人：你的車站蓋在真實車站旁，轉乘過來的旅客照它的人數多寡。"
                    ),
                    notice: language.text(
                        "Taiwan Railway Corporation, daily entries and exits by station; Taipei Rapid Transit Corporation, hourly entries and exits by station; Taichung Mass Rapid Transit Corporation, riders by station; Kaohsiung City Government, entries and exits by station of the Kaohsiung Metro: used under the Open Government Data License, version 1.0. Taiwan High Speed Rail Corporation, passengers entering and leaving each station; New Taipei Metro Corporation, daily riders by station; Taoyuan Metro Corporation, riders by station: from their published operating statistics.",
                        "國營臺灣鐵路股份有限公司「臺鐵每日各站點進出站人數」、臺北大眾捷運股份有限公司「臺北捷運各站分時進出量統計」、臺中捷運股份有限公司「臺中捷運股份有限公司捷運各站旅運量」、高雄市政府「高雄都會區大眾捷運系統各站旅運量入站、出站」，依「政府資料開放授權條款第 1 版」使用；台灣高速鐵路股份有限公司「客運運輸情形：各站進出旅客人數」、新北大眾捷運股份有限公司「營運統計數據：每日全線各站運量統計表」、桃園大眾捷運股份有限公司「各站旅運量統計」，取自其公布的營運統計。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("TRA entries and exits", "臺鐵各站進出站人數"), url: "https://data.gov.tw/dataset/8792"),
                        DataSourceCredit.Link(title: language.text("Taipei Metro entries and exits", "臺北捷運各站進出量"), url: "https://data.gov.tw/dataset/128506"),
                        DataSourceCredit.Link(title: language.text("Taichung Metro riders by station", "臺中捷運各站旅運量"), url: "https://data.gov.tw/dataset/175718"),
                        DataSourceCredit.Link(title: language.text("Kaohsiung Metro entries and exits", "高雄捷運各站旅運量"), url: "https://data.gov.tw/dataset/159641"),
                        DataSourceCredit.Link(title: language.text("High Speed Rail operating statistics", "高鐵客運運輸情形"), url: "https://www.thsrc.com.tw/corp/9571df11-8524-4935-8a46-0d5a72e6bc7c"),
                        DataSourceCredit.Link(title: language.text("New Taipei Metro operating statistics", "新北捷運統計資料"), url: "https://www.ntmetro.com.tw/basic/?node=10145"),
                        DataSourceCredit.Link(title: language.text("Taoyuan Metro operating statistics", "桃園捷運統計資料"), url: "https://www.tymetro.com.tw/tymetro-new/tw/_pages/about/statistics.html"),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 332: the private motor vehicles' share of
                // trips by county, the most riders who take a scooter
                // or a car instead on a real-world map (table 4).
                DataSourceCredit(
                    id: "travelSurvey",
                    title: language.text("National Travel Survey", "民眾日常使用運具狀況調查"),
                    detail: language.text(
                        "How many trips in each county and city of Taiwan are made by scooter or car: on a real-world map, when your trains are slower, at most that share of your riders ride or drive instead.",
                        "台灣各縣市有多少行程騎機車或開車：在實景地圖上，你的列車比較慢時，最多這個比例的旅客改騎機車或開車。"
                    ),
                    notice: language.text(
                        "Source: Ministry of Transportation and Communications, Department of Statistics, National Travel Survey, 2024 (table 4, the private motor vehicles' share of trips by county and city). Used under the Open Government Data License, version 1.0.",
                        "資料來源：交通部統計處民眾日常使用運具狀況調查，113 年（表 4，各縣市運具次數之私人機動運具市占率）。依「政府資料開放授權條款第 1 版」使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Dataset (data.gov.tw)", "資料集（政府資料開放平臺）"), url: travelSurveyURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 724: each sight's visitors in a year, by the
                // Tourism Administration's count, shown on its card in
                // the sights panel (`tools/tourism-spots/`).
                DataSourceCredit(
                    id: "sightVisitors",
                    title: language.text("Visitors by sight", "景點遊客人次"),
                    detail: language.text(
                        "How many visitors each of Taiwan's main sights has in a year, shown on its card in the sights panel.",
                        "台灣各主要景點一年有多少遊客，寫在景點清單裡那個景點的卡片上。"
                    ),
                    notice: language.text(
                        "Source: Tourism Administration, Ministry of Transportation and Communications, monthly visitors to the principal scenic spots in Taiwan, 2024. Used under the Open Government Data License, version 1.0. Which sight matches which official spot is this game's own work.",
                        "資料來源：交通部觀光署「歷年國內主要觀光遊憩據點遊客人數月別統計」，2024 年。依「政府資料開放授權條款第 1 版」使用。景點與官方據點的對應由本遊戲整理。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Dataset (data.gov.tw)", "資料集（政府資料開放平臺）"), url: sightVisitorsURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decisions 695 and 700: each airport's passengers and
                // flights of a year and where they go, which set its
                // flights and how many of its passengers ride the
                // company's trains.
                DataSourceCredit(
                    id: "airports",
                    title: language.text("Airport passengers, flights and destinations", "機場旅客、航班架次與航點"),
                    detail: language.text(
                        "How many passengers and flights each of Taiwan's airports has in a year, and where they fly: on a real-world map, they set each airport's flights, its domestic and international passengers, and how many of them ride your trains.",
                        "台灣各機場一年的旅客、航班架次與飛往哪裡：在實景地圖上，決定每座機場的航班數、國內與國際旅客，以及有多少旅客搭你的車。"
                    ),
                    notice: language.text(
                        "Source: Civil Aviation Administration, Ministry of Transportation and Communications, Civil Aviation Statistics annual report 2025 and its timetable of scheduled domestic flights. Terminal positions: OpenStreetMap contributors.",
                        "資料來源：交通部民用航空局「民航統計年報」114 年與「國內定期航線班機時刻表」。航廈位置：OpenStreetMap 貢獻者。"
                    ),
                    links: [
                        civilAviation(in: language),
                    ]
                ),
                // Decision 1004: how often it rains in each part of
                // Taiwan, from the weather station nearest each place;
                // decision 1013: days of 1 mm and of thunder. CWA open
                // data is under the Open Government Data License 1.0
                // (attribution); NOAA's summaries are public domain.
                DataSourceCredit(
                    id: "taiwanWeather",
                    title: language.text("Taiwan’s weather", "台灣的天氣"),
                    detail: language.text(
                        "On a map of Taiwan, how often it rains and thunders in each month in each part of the island: the north’s wet winters, the south’s dry ones and summer thunderstorms.",
                        "台灣地圖上各地每個月多常下雨、打雷：北部冬天多雨、南部冬天少雨，夏天午後雷陣雨。"
                    ),
                    notice: language.text(
                        "Central Weather Administration open data: daily rainfall at 19 stations, 2017–2025, counted as days with 1 mm or more (edited; Open Government Data License, version 1.0). Thunder: airport weather reports of 2015–2024 from the Iowa Environmental Mesonet, Iowa State University, and the Global Summary of the Day of NOAA National Centers for Environmental Information (edited). Station positions: NOAA NCEI.",
                        "中央氣象署氣象資料開放平臺：19 個氣象站 2017–2025 年的每日雨量，數成 1 毫米以上的日數（經加工；政府資料開放授權條款第 1 版）。雷暴：美國愛荷華州立大學 Iowa Environmental Mesonet 的 2015–2024 年機場天氣報告，與美國國家海洋暨大氣總署國家環境資訊中心（NOAA NCEI）的每日摘要（經加工）。測站位置：NOAA NCEI。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Central Weather Administration: open data", "中央氣象署：氣象資料開放平臺"), url: "https://opendata.cwa.gov.tw/"),
                        DataSourceCredit.Link(title: "Iowa Environmental Mesonet", url: "https://mesonet.agron.iastate.edu/request/download.phtml"),
                        DataSourceCredit.Link(title: language.text("NOAA NCEI: Global Summary of the Day", "NOAA NCEI：每日摘要"), url: "https://www.ncei.noaa.gov/access/metadata/landing-page/bin/iso?id=gov.noaa.ncdc:C00516"),
                    ]
                ),
                // Decision 147: how much of the ground real buildings
                // cover, which sets what buying out a city building
                // costs. Overture's buildings theme is ODbL 1.0; in
                // Taiwan its footprints are OpenStreetMap's and Shi et
                // al.'s (CC BY 4.0), each credited as it asks. Decision
                // 239: the 3D map's real buildings are its footprints;
                // decision 389: everywhere in Taiwan.
                DataSourceCredit(
                    id: "overtureBuildings",
                    title: language.text("Overture Maps buildings", "Overture Maps 建物"),
                    detail: language.text(
                        "How much of the ground real buildings cover on real-world maps of Taiwan and Penghu, which sets what buying out the city’s buildings costs: a car park costs little, a dense block a lot. The buildings of 3D maps in Taiwan, Penghu, Kinmen and Matsu, and of the 3D city preview round Kaohsiung and Taichung Stations, are its too, but in Taichung City, where the city’s own building map draws them.",
                        "台灣與澎湖實景地圖上真實建物佔地多少，決定收購城市建物的價錢：停車場便宜，密集的街區貴。台灣、澎湖、金門、馬祖實景 3D 地圖上的建物，以及 3D 城市預覽裡高雄車站、台中車站周圍的建物，也是它的（台中市改用臺中市建物圖）。"
                    ),
                    notice: language.text(
                        "Overture Maps Foundation (overturemaps.org), buildings, release 2026-09-23.1, under the Open Database License (ODbL) 1.0. Its footprints in Taiwan are © OpenStreetMap contributors (ODbL 1.0) and, where OpenStreetMap has none, from Qian Shi et al., “A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework”, Zenodo, 2023 (CC BY 4.0). The coverage file, the city tiles and the footprint tiles the game derives from them come with the app, and a complete machine-readable copy under the same licence is available by writing to \(mailbox.english).",
                        "Overture Maps Foundation（overturemaps.org）建物，2026-09-23.1 版，依開放資料庫授權（ODbL）1.0 使用。台灣的足跡來自 © OpenStreetMap 貢獻者（ODbL 1.0），OpenStreetMap 沒有的地方來自 Qian Shi 等人〈A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework〉，Zenodo，2023（CC BY 4.0）。遊戲據此整理的建蔽率檔、城市圖塊與足跡圖塊隨 App 提供，也可來信\(mailbox.chinese)索取以相同授權提供的完整機器可讀檔案。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Overture Maps", url: overtureURL),
                        DataSourceCredit.Link(title: language.text("Attribution", "出處"), url: overtureAttributionURL),
                        DataSourceCredit.Link(title: language.text("East Asian buildings", "東亞建物資料"), url: eastAsianBuildingsURL),
                        DataSourceCredit.Link(title: "ODbL 1.0", url: odblURL),
                        ccByLicense,
                    ]
                ),
            ]
        )
    }
}
