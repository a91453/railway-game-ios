// The data sources page: Fukuoka's map (Japan).
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// Decision 854: Fukuoka's map (`MapPacks/fukuoka`, made by
    /// `tools/fukuoka-map/`), credited once it is open.
    static func fukuokaSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "fukuokaRailways",
            title: language.text("Fukuoka’s Railways", "福岡的鐵道"),
            credits: [
                DataSourceCredit(
                    id: "fukuokaSubway",
                    title: language.text("Fukuoka City Subway", "福岡市地鐵"),
                    detail: language.text(
                        "The Fukuoka City Subway’s three lines, the Kuko, Hakozaki and Nanakuma lines, with their stations’ names in Chinese, English and Japanese. There is no published timetable, so their trains run at estimated intervals.",
                        "福岡市地鐵的空港線、箱崎線與七隈線三條路線，車站有中文、英文與日文站名。沒有公開的時刻表，所以列車照估計的班距行駛。"
                    ),
                    notice: language.text(
                        "Stations and their Japanese names: made by processing “National Land Numerical Information (Railway Data)” (Ministry of Land, Infrastructure, Transport and Tourism), CC BY 4.0 (「国土数値情報（鉄道データ）」（国土交通省）を加工して作成). Track, tunnels, viaducts and line colours: © OpenStreetMap contributors, ODbL 1.0. The game is not affiliated with the Fukuoka City Transportation Bureau or the Government of Japan.",
                        "車站與日文站名：「国土数値情報（鉄道データ）」（国土交通省）を加工して作成，CC BY 4.0。軌道、隧道、高架與路線色：© OpenStreetMap 貢獻者，ODbL 1.0。本遊戲與福岡市交通局、日本政府沒有任何關係。"
                    ),
                    links: [
                        landNumericalRailwayData(in: language),
                        ccByLicense,
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // SHINKANSEN-SALE (decision 975): the Kyushu Shinkansen,
                // Hakata to Kumamoto (`MapPacks/fukuoka/kyushushinkansen.json`).
                DataSourceCredit(
                    id: "kyushuShinkansen",
                    title: language.text("Kyushu Shinkansen", "九州新幹線"),
                    detail: language.text(
                        "The Kyushu Shinkansen from Hakata to Kumamoto, with its seven stations’ names in Chinese, English and Japanese. Its trains call at every station, at estimated times.",
                        "九州新幹線博多到熊本這一段，七個車站有中文、英文與日文站名。列車每站都停，照估計的時刻行駛。"
                    ),
                    notice: language.text(
                        "Stations and their Japanese names: made by processing “National Land Numerical Information (Railway Data)” (Ministry of Land, Infrastructure, Transport and Tourism), CC BY 4.0 (「国土数値情報（鉄道データ）」（国土交通省）を加工して作成). Track, tunnels and viaducts: © OpenStreetMap contributors, ODbL 1.0. The game is not affiliated with Kyushu Railway Company or the Government of Japan.",
                        "車站與日文站名：「国土数値情報（鉄道データ）」（国土交通省）を加工して作成，CC BY 4.0。軌道、隧道與高架：© OpenStreetMap 貢獻者，ODbL 1.0。本遊戲與九州旅客鐵道、日本政府沒有任何關係。"
                    ),
                    links: [
                        landNumericalRailwayData(in: language),
                        ccByLicense,
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // Decision 1028: the Relay Kamome, Hakata to Takeo-Onsen
                // (`MapPacks/fukuoka/jrkyushu.json`).
                DataSourceCredit(
                    id: "relayKamome",
                    title: language.text("Relay Kamome", "海鷗接力號"),
                    detail: language.text(
                        "JR Kyushu’s Relay Kamome from Hakata to Takeo-Onsen, with its six stations’ names in Chinese, English and Japanese. Its trains meet the Nishi-Kyushu Shinkansen across the platform at Takeo-Onsen, at estimated times.",
                        "JR九州海鷗接力號博多到武雄溫泉，六個車站有中文、英文與日文站名。列車在武雄溫泉和西九州新幹線對面接續，照估計的時刻行駛。"
                    ),
                    notice: language.text(
                        "Stations and their Japanese names: made by processing “National Land Numerical Information (Railway Data)” (Ministry of Land, Infrastructure, Transport and Tourism), CC BY 4.0 (「国土数値情報（鉄道データ）」（国土交通省）を加工して作成). Track, viaducts and the line colour: © OpenStreetMap contributors, ODbL 1.0. The game is not affiliated with Kyushu Railway Company or the Government of Japan.",
                        "車站與日文站名：「国土数値情報（鉄道データ）」（国土交通省）を加工して作成，CC BY 4.0。軌道、高架與路線色：© OpenStreetMap 貢獻者，ODbL 1.0。本遊戲與九州旅客鐵道、日本政府沒有任何關係。"
                    ),
                    links: [
                        landNumericalRailwayData(in: language),
                        ccByLicense,
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // FUKUOKA-GROUND: the pack's base map, buildings, heights and people.
                DataSourceCredit(
                    id: "fukuokaMap",
                    title: language.text("Fukuoka’s map", "福岡的地圖"),
                    detail: language.text(
                        "On Fukuoka’s map, the sea and rivers, roads, parks, the airport and place names, on the flat map and the 3D map.",
                        "福岡地圖上的海與河川、道路、公園、機場與地名，平面地圖與 3D 地圖都用。"
                    ),
                    notice: language.text(
                        "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026. The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0).",
                        "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月。圖層照 OpenMapTiles 的格式（CC BY 4.0）。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "fukuokaBuildings",
                    title: language.text("Fukuoka’s buildings", "福岡的建物"),
                    detail: language.text(
                        "On Fukuoka’s map, the outlines and uses of the buildings on the 3D map, and their storeys where they are recorded or measured.",
                        "福岡地圖上，3D 地圖裡建物的外形與用途，有記錄或實測的還有樓層數。"
                    ),
                    notice: language.text(
                        "© OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026. Where OpenStreetMap has no building: Overture Maps Foundation (overturemaps.org), buildings, release 2026-11-18.0 (ODbL 1.0), its outlines from Microsoft ML Building Footprints (ODbL 1.0) and Qian Shi et al., East Asian buildings, Zenodo, 2023 (CC BY 4.0). Heights measured by MLIT’s 3D city models: 「3D都市モデル（Project PLATEAU）」（国土交通省）を加工して作成. Storeys that are neither recorded nor measured are this game’s estimate.",
                        "© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月。OpenStreetMap 沒有的建物：Overture Maps Foundation（overturemaps.org）建物，2026-11-18.0 版（ODbL 1.0），外形來自 Microsoft ML Building Footprints（ODbL 1.0）與 Qian Shi 等人的東亞建物資料，Zenodo，2023（CC BY 4.0）。實測樓高：「3D都市モデル（Project PLATEAU）」（国土交通省）を加工して作成（以日本國土交通省 3D 都市模型加工製作）。沒有記錄也沒有實測的樓層數是本遊戲的估計。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                        DataSourceCredit.Link(title: "Overture Maps", url: overtureURL),
                        DataSourceCredit.Link(title: language.text("East Asian buildings", "東亞建物資料"), url: eastAsianBuildingsURL),
                        DataSourceCredit.Link(title: "Project PLATEAU", url: "https://www.mlit.go.jp/plateau/site-policy/"),
                    ]
                ),
                DataSourceCredit(
                    id: "fukuokaTerrain",
                    title: language.text("Fukuoka’s terrain", "福岡的地形"),
                    detail: language.text(
                        "Fukuoka’s hills and plains: how high the ground is where track is laid, and the hill shading of the map.",
                        "福岡的山丘與平原：軌道鋪設處地面多高，以及地圖上山的陰影。"
                    ),
                    notice: language.text(
                        "Made by processing the Geospatial Information Authority of Japan’s elevation tiles (国土地理院の標高タイルを加工して作成).",
                        "国土地理院の標高タイルを加工して作成（以日本國土地理院的標高圖磚加工製作）。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("GSI terms of use", "國土地理院使用條款"), url: "https://www.gsi.go.jp/kikakuchousei/kikakuchousei40182.html"),
                    ]
                ),
                DataSourceCredit(
                    id: "fukuokaPopulation",
                    title: language.text("Fukuoka’s people", "福岡的人口"),
                    detail: language.text(
                        "Where people live and where they work on Fukuoka’s map, for how many ride from each station and where they go.",
                        "福岡地圖上的人住在哪裡、在哪裡上班，用來算每一站有多少人搭車、要去哪裡。"
                    ),
                    notice: language.text(
                        "Made by processing the 2020 Population Census and the 2021 Economic Census for Business Activity, 500 m grids (Statistics Bureau, Ministry of Internal Affairs and Communications), from e-Stat, the portal site of official statistics of Japan (「令和2年国勢調査」「令和3年経済センサス‐活動調査」（総務省統計局）（政府統計の総合窓口（e-Stat））を加工して作成). Each 500 m cell’s people and workers are spread evenly over it.",
                        "「令和2年国勢調査」「令和3年経済センサス‐活動調査」（総務省統計局）（政府統計の総合窓口（e-Stat））を加工して作成（以日本總務省統計局 2020 年國勢調查與 2021 年經濟普查的 500 公尺網格加工製作，資料取自政府統計入口網站 e-Stat）。每個 500 公尺格的人與上班的人平均分在格內。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("e-Stat terms of use", "e-Stat 使用條款"), url: "https://www.e-stat.go.jp/terms-of-use"),
                    ]
                ),
                // Decision 1003: the months' rain and thunder
                // (`Disruptions.countryRain`).
                DataSourceCredit(
                    id: "fukuokaWeather",
                    title: language.text("Kyushu’s weather", "九州的天氣"),
                    detail: language.text(
                        "How often it rains or thunders in each month in each part of Kyushu’s map.",
                        "九州地圖上各地每個月多常下雨、打雷。"
                    ),
                    notice: language.text(
                        "Japan Meteorological Agency, normals of 1991–2020 at Fukuoka, Saga, Nagasaki and Kumamoto: days with 1.0 mm of precipitation or more and days with thunder (edited).",
                        "日本氣象廳 1991–2020 年平年值（福岡、佐賀、長崎、熊本）：日降水量 1.0 毫米以上日數與雷日數（經加工）。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Japan Meteorological Agency: normals", "日本氣象廳：平年值"), url: "https://www.data.jma.go.jp/obd/stats/data/mdrr/normal/index.html"),
                    ]
                ),
                // FUKUOKA-OPEN: Fukuoka Airport on Fukuoka's map
                // (`AirportCatalog.overseasPlaces`).
                DataSourceCredit(
                    id: "fukuokaAirport",
                    title: language.text("Fukuoka Airport", "福岡機場"),
                    detail: language.text(
                        "On Fukuoka’s map, how many passengers and flights the airport has in a day, and its flights to Taiwan.",
                        "福岡地圖上機場一天有多少旅客與航班，以及飛台灣的航線。"
                    ),
                    notice: language.text(
                        "Passengers of 2025 and flights of the year to March 2026: Fukuoka City, from the Ministry of Land, Infrastructure, Transport and Tourism’s airport figures. Flights to Taiwan: Civil Aviation Administration, Ministry of Transportation and Communications (Taiwan), Civil Aviation Statistics annual report 2025. Position: OpenStreetMap contributors. The game is not affiliated with Fukuoka International Airport.",
                        "2025 年的旅客與 2025 年度（到 2026 年 3 月）的航班：福岡市整理的日本國土交通省機場統計。飛台灣的航線：交通部民用航空局《民航統計年報》2025 年。位置：OpenStreetMap 貢獻者。本遊戲與福岡國際機場沒有任何關係。"
                    ),
                    links: [
                        civilAviation(in: language),
                        DataSourceCredit.Link(title: language.text("Fukuoka City: Fukuoka Airport", "福岡市：福岡空港について"), url: "https://www.city.fukuoka.lg.jp/shisei/kotsu-toshiseibi/kukouchosa.html"),
                    ]
                ),
                // Decision 991: the map's other airports
                // (`AirportCatalog.overseasPlaces`).
                DataSourceCredit(
                    id: "kyushuAirports",
                    title: language.text("Kumamoto, Saga, Kitakyushu, Amakusa, Nagasaki and Iki Airports", "熊本、佐賀、北九州、天草、長崎、壹岐機場"),
                    detail: language.text(
                        "On Fukuoka’s map, how many passengers and flights each of these airports has in a day.",
                        "福岡地圖上這六座機場一天各有多少旅客與航班。"
                    ),
                    notice: language.text(
                        "Passengers and flights of 2025: the Ministry of Land, Infrastructure, Transport and Tourism (Japan), airport survey 2025. Positions: OpenStreetMap contributors. The game is not affiliated with the airports.",
                        "2025 年的旅客與航班：日本國土交通省《令和 7 年空港管理狀況調書》。位置：OpenStreetMap 貢獻者。本遊戲與這六座機場沒有任何關係。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("MLIT: airport figures", "國土交通省：空港管理狀況"), url: "https://www.mlit.go.jp/koku/15_bf_000185.html"),
                    ]
                ),
            ]
        )
    }

    /// National Land Numerical Information's railway data (MLIT).
    private static func landNumericalRailwayData(in language: DisplayLanguage) -> DataSourceCredit.Link {
        DataSourceCredit.Link(title: language.text("National Land Numerical Information: Railway Data", "国土数値情報 鉄道データ"), url: "https://nlftp.mlit.go.jp/ksj/gml/datalist/KsjTmplt-N02-2025.html")
    }
}
