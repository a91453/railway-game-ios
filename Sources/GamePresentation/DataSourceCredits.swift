// Where the game's real-world data comes from, and the licences it is used
// under: the data sources screen and the credit on the map.
//
// After the owner's `Railway/` site's own data sources page
// (`Railway/site_archive_clean/data-sources/index.html`) and the notes in
// its data files (`source_notes` of `data/tra.json`, `thsr_track.json`,
// `afr.json`, `trtc.json` and the other systems'): the Ministry of
// Transportation and Communications' TDX under the Open Government Data
// License, version 1.0, and OpenStreetMap under the Open Database License.
// The population that sets a real-world station's ridership is WorldPop's,
// under CC BY 4.0 (PopulationGrid.swift).
//
// The website's credits page (a91453/railway-reference-private,
// `Website/site/credits.html`) says the same in both languages: when a
// source here is added, removed or reworded, change that page in the same
// round, keeping its own notes on which screenshots use which base map and
// the website's typeface, and with no links to the source repository.

/// One source of the game's data.
public struct DataSourceCredit: Identifiable, Hashable, Sendable {
    /// A link to the source or its licence.
    public struct Link: Hashable, Sendable {
        public let title: String
        public let url: String
    }

    public let id: String
    public let title: String
    /// What the game takes from it.
    public let detail: String
    /// The licence or notice it asks for.
    public let notice: String
    public let links: [Link]
}

/// The sources of one part of the game.
public struct DataSourceSection: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let credits: [DataSourceCredit]
}

public enum DataSourceCredits {
    static let tdxURL = "https://tdx.transportdata.tw"
    static let traOpenDataURL = "https://ods.railway.gov.tw"
    static let openGovernmentLicenseURL = "https://data.gov.tw/license"
    static let openStreetMapCopyrightURL = "https://www.openstreetmap.org/copyright"
    static let nlscRailwayURL = "https://data.gov.tw/dataset/73220"
    static let nlscHighSpeedRailURL = "https://data.gov.tw/dataset/73221"
    static let nlscMetroURL = "https://data.gov.tw/dataset/73222"
    static let odblURL = "https://opendatacommons.org/licenses/odbl/1-0/"
    static let repositoryURL = "https://github.com/a91453/railway-game-ios"
    static let worldPopURL = "https://www.worldpop.org"
    static let copernicusDEMURL = "https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM"
    static let worldPopDatasetURL = "https://doi.org/10.5258/SOTON/WP00840"
    static let travelSurveyURL = "https://data.gov.tw/dataset/6248"
    static let ccByURL = "https://creativecommons.org/licenses/by/4.0/"
    static let overtureURL = "https://overturemaps.org"
    static let overtureAttributionURL = "https://docs.overturemaps.org/attribution/"
    static let eastAsianBuildingsURL = "https://doi.org/10.5281/zenodo.8174931"
    static let openFreeMapURL = "https://openfreemap.org"
    static let openMapTilesURL = "https://openmaptiles.org"
    static let mapLibreURL = "https://github.com/maplibre/maplibre-native"
    static let openMapTilesSchemaURL = "https://openmaptiles.org/schema/"
    static let notoSansURL = "https://notofonts.github.io"
    /// Noto Sans's licence, as the app bundles it (`Resources/Licenses/`).
    static let notoSansLicenseURL = "https://github.com/a91453/railway-game-ios/blob/main/RailwayGameApp/Resources/Licenses/NotoSans-OFL.txt"
    static let baseMapToolURL = "https://github.com/a91453/railway-game-ios/tree/main/tools/basemap"
    /// MapLibre Native's licence and its third-party notices, as the app
    /// bundles them (`Resources/Licenses/`).
    static let mapLibreLicenseURL = "https://github.com/a91453/railway-game-ios/blob/main/RailwayGameApp/Resources/Licenses/MapLibre-iOS-LICENSE.md"
    static let proceduralTokyoURL = "https://github.com/jeantimex/tokyo"
    /// The notices of the 3D city view's page and the libraries it bundles
    /// (decision 152), next to the page on the game's website (decision 163).
    static let cityViewNoticesURL = "https://www.alongthelinegame.com/city/NOTICES.txt"
    static let polyHavenURL = "https://polyhaven.com"
    static let meshyURL = "https://www.meshy.ai"
    static let busPhotoURL = "https://commons.wikimedia.org/wiki/File:Capital_Bus_735-FW_right_side_and_TWTC_ITB_(46106172592).jpg"
    static let earcutURL = "https://github.com/mapbox/earcut"
    static let puffURL = "https://github.com/madler/zlib/tree/develop/contrib/puff"
    /// The ISC License's permission notice, which must come with every copy
    /// of earcut (decision 234).
    static let iscPermission = """
        Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby \
        granted, provided that the above copyright notice and this permission notice appear in all copies. THE SOFTWARE \
        IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED \
        WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, \
        INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER \
        IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR \
        PERFORMANCE OF THIS SOFTWARE.
        """
    static let cc0URL = "https://creativecommons.org/publicdomain/zero/1.0/"
    static let wikidataURL = "https://www.wikidata.org"
    static let worldUrbanizationProspectsURL = "https://population.un.org/wup/"
    static let ccByIGOURL = "https://creativecommons.org/licenses/by/3.0/igo/"
    static let ccBy3URL = "https://creativecommons.org/licenses/by/3.0/"
    /// Decision 343: the recordings the running sounds are made to, on
    /// radio aporee ::: maps at the Internet Archive.
    static let banqiaoRecordingURL = "https://archive.org/details/aporee_34085_39187"
    static let guishanRecordingURL = "https://archive.org/details/aporee_17319_20158"
    static let ktxRecordingURL = "https://archive.org/details/aporee_65051_75140"
    /// Decision 346: the recordings the rain, the typhoon and the thunder
    /// are made to, by Wu, Tsan-Cheng, on radio aporee ::: maps.
    static let weatherRecordings: [(title: String, place: (english: String, chinese: String), id: String)] = [
        ("富陽自然生態公園, 大安區,Taipei City - Rain and Thunder", ("Fuyang Park", "富陽公園"), "aporee_28503_32842"),
        ("Taipei Railway Workshop, Taiwan - Thunderstorm", ("Taipei Railway Workshop", "臺北機廠"), "aporee_24967_28963"),
        ("大仁街, Tamsui District - Rain and Thunder", ("Tamsui rain", "淡水雨聲"), "aporee_27593_31908"),
        ("No.20, Daren St., Tamsui Dist., New Taipei City - typhoon", ("Tamsui typhoon", "淡水颱風"), "aporee_29264_34673"),
        ("敦安公園, 大安區, Taipei City - Thunder sound", ("Dun'an Park", "敦安公園"), "aporee_28950_33339"),
        ("松山文創園區,Taipei City - Thunder", ("Songshan Cultural Park", "松山文創園區"), "aporee_33407_38419"),
    ]

    /// The short credit shown on a real-world map while Taiwan's railways
    /// are drawn on it.
    public static func railwaysOnMap(in language: DisplayLanguage) -> String {
        language.text("Railways: MOTC TDX, © OpenStreetMap contributors", "鐵道：交通部 TDX、© OpenStreetMap 貢獻者")
    }

    /// The short credit always shown in the corner of a real-world map
    /// (decision 191), tapped for the data sources page: OpenMapTiles and
    /// OpenStreetMap while the base map is OpenStreetMap's (in Taiwan the
    /// bundled tiles, elsewhere OpenFreeMap's, both after the OpenMapTiles
    /// schema, whose licence asks for its credit in the map's corner), and
    /// TDX while Taiwan's railways are drawn. Apple's map credits itself;
    /// on it only the railways'. Empty when the map shows neither.
    /// OpenFreeMap's own words are in the map's attribution button.
    public static func mapCorner(baseMap: Bool, railways: Bool, in language: DisplayLanguage) -> String {
        let openStreetMap = "© OpenMapTiles © OpenStreetMap"
        let tdx = language.text("MOTC TDX", "交通部 TDX")
        switch (baseMap, railways) {
        case (true, false): return openStreetMap
        case (true, true): return "\(openStreetMap) · \(tdx)"
        case (false, true): return language.text("Railways: © OpenStreetMap · \(tdx)", "鐵道：© OpenStreetMap · \(tdx)")
        case (false, false): return ""
        }
    }

    /// Decision 403 (續二): the credit written on a photo of the 3D map, or
    /// empty for the player's own map. A real-world map's 3D view draws
    /// the railways (OpenStreetMap, TDX), the buildings' footprints
    /// (Overture Maps, OpenStreetMap's under the ODbL) and the ground's
    /// heights (Copernicus DEM): the photo, shared away from the game's
    /// data sources page, names them all.
    public static func map3DPhoto(realWorld: Bool, in language: DisplayLanguage) -> String {
        guard realWorld else { return "" }
        return "© OpenStreetMap · Overture Maps · Copernicus DEM · \(language.text("MOTC TDX", "交通部 TDX"))"
    }

    /// The Open Government Data License, linked from every source under it.
    static func openGovernmentLicense(in language: DisplayLanguage) -> DataSourceCredit.Link {
        DataSourceCredit.Link(title: language.text("Open Government Data License", "政府資料開放授權條款"), url: openGovernmentLicenseURL)
    }

    /// The attribution the Open Government Data License, version 1.0, asks
    /// for after the provider, the year and the datasets (its annex).
    static func openGovernmentAttribution(in language: DisplayLanguage) -> String {
        language.text(
            "This open data is released to the public under the Open Government Data License, version 1.0; users may use it provided they comply with the terms of the licence.",
            "（此開放資料依政府資料開放授權條款（Open Government Data License）第 1 版進行公眾釋出，使用者於遵守本條款各項規定之前提下，得利用之。）"
        )
    }

    /// Every source, by what the player sees of it (rewritten 2026-10-23 at
    /// the owner's request: each railway system on its own, where its
    /// station order, colours and times come from, checked against
    /// `tools/real-railways/README.md` and each data file's `source_notes`).
    public static func sections(in language: DisplayLanguage) -> [DataSourceSection] {
        [
            // What the real railways on the map are, and where each
            // system's data comes from (`RealRailways.System.all`).
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
                            "Every line’s track and station positions follow OpenStreetMap’s track (© OpenStreetMap contributors, ODbL 1.0); the few stretches where OpenStreetMap is out of date or has no track follow MOTC TDX. Where each line’s station order, names, colours and times come from is under its operator below.",
                            "每條線的軌道走向與車站位置照 OpenStreetMap 的軌道畫（© OpenStreetMap 貢獻者，ODbL 1.0），少數 OpenStreetMap 過時或沒有軌道的路段照交通部 TDX。各線的站序、站名、路線色與時刻從哪裡來，寫在下面各營運機構。"
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
                            "The English line and station names are compiled by Along the Line.",
                            "英文的路線名與站名由《沿線》整理。"
                        ),
                        notice: language.text(
                            "The game is not affiliated with any of the operators above.",
                            "本遊戲與上列各營運機構沒有任何關係。"
                        ),
                        links: []
                    ),
                ]
            ),
            // The datasets behind the railways above, each with the notice
            // its licence asks for.
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
                            "Most of the station order, station names, station codes and addresses above; the High Speed Rail’s, the metros’ and the light rails’ timetables; the High-Speed Rail Demo’s fares; and some lines’ colours.",
                            "上面大部分路線的站序、站名、車站代碼與地址，高鐵、捷運與輕軌的時刻表，高鐵示範的票價，以及部分路線的路線色。"
                        ),
                        notice: language.text(
                            "Ministry of Transportation and Communications, Transport Data eXchange (TDX), 2026: rail stations, lines, station order of lines, line shapes, travel times between stations, headways, station timetables, the High Speed Rail’s daily timetable and its origin–destination fares. ",
                            "交通部運輸資料流通服務平臺（TDX）2026 年軌道車站、路線、路線站序、路線線型、站間行駛時間、班距、車站時刻表、高鐵每日時刻表與高鐵起訖站票價"
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
                            "The real times of TRA’s trains: the Pingxi Line in the Real-World Demo, the Yilan Line in the TRA Demo, and the six branch lines you can buy on a real-world map.",
                            "台鐵列車的真實時刻：實景示範的平溪線、台鐵示範的宜蘭線，以及實景地圖上可以買下的六條支線。"
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
                            "Railways: the track, where stations and platforms stand, single or double track, bridges and tunnels. Real-world maps: the settlements, villages and townships new stations are named after, industrial land, parks, farmland, rivers, lakes and the coast, tourist sights, and the shops, schools and other places round new stations. Demos: the High-Speed Rail Demo’s depots and end-station tracks, and the TRA Demo’s Yilan and Su'aoxin sidings. The 3D city preview’s roads, parks and shop names.",
                            "鐵道：軌道走向、車站與月台的位置、單線或雙線、橋與隧道。實景地圖：新車站取名用的聚落、村里與鄉鎮，工業區、公園、農地、河川、湖泊與海岸線，觀光景點，以及新車站附近的商店、學校等地點。示範地圖：高鐵示範的機廠與端點站股道、台鐵示範的宜蘭、蘇澳新側線。3D 城市預覽的道路、公園與店名。"
                        ),
                        // The ODbL asks for the derived files to be offered
                        // under the same licence: the source repository link
                        // below is where they are.
                        notice: language.text(
                            "© OpenStreetMap contributors, under the Open Database License (ODbL) 1.0. The data files the game derives from it are available under the same licence from the source repository below.",
                            "© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用。遊戲據此整理的資料檔以相同授權提供，可從下方的原始碼儲存庫取得。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("OpenStreetMap copyright", "OpenStreetMap 版權"), url: openStreetMapCopyrightURL),
                            DataSourceCredit.Link(title: "ODbL 1.0", url: odblURL),
                            DataSourceCredit.Link(title: language.text("Source repository", "原始碼儲存庫"), url: repositoryURL),
                        ]
                    ),
                ]
            ),
            DataSourceSection(
                id: "population",
                title: language.text("People and Riders", "人口與旅客"),
                credits: [
                    DataSourceCredit(
                        id: "worldPop",
                        title: "WorldPop",
                        detail: language.text(
                            "How many people live round a station you build on a real-world map of Taiwan, and so how many riders it gets. The population grid layer shows the same data.",
                            "在台灣實景地圖上蓋車站時，車站周圍住多少人、因此有多少旅客。人口網格圖層畫的也是這份資料。"
                        ),
                        notice: language.text(
                            "WorldPop (www.worldpop.org), University of Southampton: population estimates per square kilometre, 2025 (R2025A), DOI 10.5258/SOTON/WP00840, under the Creative Commons Attribution 4.0 International licence (CC BY 4.0). The game rounds each square to whole people.",
                            "WorldPop（www.worldpop.org），英國南安普敦大學：2025 年每平方公里人口估計（R2025A），DOI 10.5258/SOTON/WP00840，依創用 CC 姓名標示 4.0 國際授權（CC BY 4.0）使用。遊戲將每格人數四捨五入為整數。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "WorldPop", url: worldPopURL),
                            DataSourceCredit.Link(title: language.text("Dataset", "資料集"), url: worldPopDatasetURL),
                            DataSourceCredit.Link(title: "CC BY 4.0", url: ccByURL),
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
                            "How much of the ground real buildings cover on real-world maps of Taiwan and Penghu, which sets what buying out the city’s buildings costs: a car park costs little, a dense block a lot. The buildings of 3D maps in Taiwan, Penghu, Kinmen and Matsu, and of the 3D city preview round Kaohsiung and Taichung Stations, are its too.",
                            "台灣與澎湖實景地圖上真實建物佔地多少，決定收購城市建物的價錢：停車場便宜，密集的街區貴。台灣、澎湖、金門、馬祖實景 3D 地圖上的建物，以及 3D 城市預覽裡高雄車站、台中車站周圍的建物，也是它的。"
                        ),
                        notice: language.text(
                            "Overture Maps Foundation (overturemaps.org), buildings, release 2026-09-23.1, under the Open Database License (ODbL) 1.0. Its footprints in Taiwan are © OpenStreetMap contributors (ODbL 1.0) and, where OpenStreetMap has none, from Qian Shi et al., “A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework”, Zenodo, 2023 (CC BY 4.0). The coverage file, the city tiles and the footprint tiles the game derives from them are available under the same licence from the source repository.",
                            "Overture Maps Foundation（overturemaps.org）建物，2026-09-23.1 版，依開放資料庫授權（ODbL）1.0 使用。台灣的足跡來自 © OpenStreetMap 貢獻者（ODbL 1.0），OpenStreetMap 沒有的地方來自 Qian Shi 等人〈A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework〉，Zenodo，2023（CC BY 4.0）。遊戲據此整理的建蔽率檔、城市圖塊與足跡圖塊以相同授權提供，可從原始碼儲存庫取得。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "Overture Maps", url: overtureURL),
                            DataSourceCredit.Link(title: language.text("Attribution", "出處"), url: overtureAttributionURL),
                            DataSourceCredit.Link(title: language.text("East Asian buildings", "東亞建物資料"), url: eastAsianBuildingsURL),
                            DataSourceCredit.Link(title: "ODbL 1.0", url: odblURL),
                            DataSourceCredit.Link(title: "CC BY 4.0", url: ccByURL),
                            DataSourceCredit.Link(title: language.text("Source repository", "原始碼儲存庫"), url: repositoryURL),
                        ]
                    ),
                ]
            ),
            DataSourceSection(
                id: "map",
                title: language.text("Map", "地圖"),
                credits: [
                    DataSourceCredit(
                        id: "appleMaps",
                        title: language.text("Apple Maps", "Apple 地圖"),
                        detail: language.text(
                            "The base map and place search of real-world maps.",
                            "實景地圖的底圖與地點搜尋。"
                        ),
                        notice: language.text(
                            "See the Legal link at the bottom left of the map for its notices.",
                            "授權聲明請見地圖左下角的「法律資訊」。"
                        ),
                        links: []
                    ),
                    // Decision 151: Taiwan's base map, the app's own tiles
                    // of OpenStreetMap and their glyphs.
                    DataSourceCredit(
                        id: "taiwanBaseMap",
                        title: language.text("Taiwan’s OpenStreetMap base map", "台灣的 OpenStreetMap 底圖"),
                        detail: language.text(
                            "The OSM base map of real-world maps in Taiwan (OSM in the map style menu), which works without a network: sea, rivers, woods, parks, roads, boundaries and place names. The 3D map lays its sea, rivers, woods, parks and roads on the ground.",
                            "台灣實景地圖的 OSM 底圖（地圖樣式選單的「OSM」），不用網路也能顯示：海、河川、森林、公園、道路、行政界與地名。3D 地圖把其中的海、河川、森林、公園與道路鋪在地面上。"
                        ),
                        notice: language.text(
                            "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0; the tiles and the tool that makes them are in the game’s public repository under the same licence. The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0). Labels in Noto Sans, © The Noto Project Authors, under the SIL Open Font License 1.1, which comes with the app.",
                            "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用；圖磚與產生它的工具依同一授權放在遊戲公開的原始碼儲存庫。圖層照 OpenMapTiles 的格式（CC BY 4.0）。文字用 Noto Sans，© The Noto Project Authors，依 SIL Open Font License 1.1 使用，授權條款隨 App 提供。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("OpenStreetMap copyright", "OpenStreetMap 版權"), url: openStreetMapCopyrightURL),
                            DataSourceCredit.Link(title: language.text("OpenMapTiles schema", "OpenMapTiles 格式"), url: openMapTilesSchemaURL),
                            DataSourceCredit.Link(title: language.text("The tiles and their tool", "圖磚與工具"), url: baseMapToolURL),
                            DataSourceCredit.Link(title: "Noto Sans", url: notoSansURL),
                            DataSourceCredit.Link(title: language.text("Noto Sans licence", "Noto Sans 授權條款"), url: notoSansLicenseURL),
                        ]
                    ),
                    // Decision 97: the OpenStreetMap base map, after `Ci/`'s
                    // credit for it ("OpenFreeMap © OpenMapTiles Data from
                    // OpenStreetMap").
                    DataSourceCredit(
                        id: "openFreeMap",
                        title: "OpenFreeMap",
                        detail: language.text(
                            "The OSM base map of real-world maps outside Taiwan (OSM in the map style menu).",
                            "台灣以外實景地圖的 OSM 底圖（地圖樣式選單的「OSM」）。"
                        ),
                        notice: language.text(
                            "OpenFreeMap © OpenMapTiles Data from OpenStreetMap. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0.",
                            "OpenFreeMap © OpenMapTiles，資料來自 OpenStreetMap。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "OpenFreeMap", url: openFreeMapURL),
                            DataSourceCredit.Link(title: "OpenMapTiles", url: openMapTilesURL),
                            DataSourceCredit.Link(title: language.text("OpenStreetMap copyright", "OpenStreetMap 版權"), url: openStreetMapCopyrightURL),
                        ]
                    ),
                    DataSourceCredit(
                        id: "mapLibre",
                        title: "MapLibre Native",
                        detail: language.text(
                            "Draws the OSM base map.",
                            "繪製 OSM 底圖。"
                        ),
                        notice: language.text(
                            "Copyright (c) 2021 MapLibre contributors, (c) 2018-2021 MapTiler.com, (c) 2014-2020 Mapbox, under the BSD 2-Clause License. The licence and the notices of the software it includes come with the app and are at the link below.",
                            "Copyright (c) 2021 MapLibre contributors, (c) 2018-2021 MapTiler.com, (c) 2014-2020 Mapbox，依 BSD 2-Clause 授權使用。授權條款與它包含的其他軟體的聲明隨 App 提供，也可以從下方連結閱讀。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "MapLibre Native", url: mapLibreURL),
                            DataSourceCredit.Link(title: language.text("Licence", "授權條款"), url: mapLibreLicenseURL),
                        ]
                    ),
                    // Decision 115: the steep slopes, worked out from the
                    // Copernicus DEM, whose licence asks for this notice;
                    // decision 124: the ground's height, from the same
                    // data, and the licence's sentence on liability.
                    DataSourceCredit(
                        id: "copernicusDEM",
                        title: "Copernicus DEM",
                        detail: language.text(
                            "The lie of the land in Taiwan, Penghu, Kinmen and Matsu: how high the ground is on real-world maps, the hillsides steeper than 30 % where nothing new can be built, and the shaded hills of Taiwan’s OSM base map.",
                            "台灣、澎湖、金門與馬祖的地形：實景地圖的地面高低、坡度超過 30%、不能新蓋的山坡地，以及台灣 OSM 底圖上山的陰影。"
                        ),
                        notice: "Copernicus DEM GLO-30 (Matsu: GLO-90). Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.",
                        links: [
                            DataSourceCredit.Link(title: "Copernicus DEM", url: copernicusDEMURL),
                        ]
                    ),
                    // Decision 262: where the large cities' main stations
                    // stand, the places a real-world game can start at.
                    DataSourceCredit(
                        id: "wikidata",
                        title: "Wikidata",
                        detail: language.text(
                            "Where the main stations of many cities in the real-world map’s city list stand.",
                            "實景地圖城市清單裡許多城市主要車站的位置。"
                        ),
                        notice: language.text(
                            "Wikidata’s data is available under CC0 1.0 (public domain).",
                            "Wikidata 的資料依 CC0 1.0（公眾領域）提供。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "Wikidata", url: wikidataURL),
                            DataSourceCredit.Link(title: "CC0 1.0", url: cc0URL),
                        ]
                    ),
                    // Decision 262: which of the list's cities are largest.
                    DataSourceCredit(
                        id: "worldUrbanizationProspects",
                        title: language.text("United Nations World Urbanization Prospects 2025", "聯合國《世界都市化展望》2025"),
                        detail: language.text(
                            "How many people live in each city of the real-world map’s city list, which puts the largest first.",
                            "實景地圖城市清單裡各城市的人口，清單照它從大排到小。"
                        ),
                        notice: language.text(
                            "United Nations, Department of Economic and Social Affairs, Population Division (2025). World Urbanization Prospects: The 2025 Revision. Under the Creative Commons Attribution 3.0 IGO licence; the game rounds each city’s figure to thousands.",
                            "聯合國經濟和社會事務部人口司（2025），《世界都市化展望：2025 年修訂版》。依創用 CC 姓名標示 3.0 IGO 授權使用；遊戲把各城市的人數四捨五入到千人。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("World Urbanization Prospects", "世界都市化展望"), url: worldUrbanizationProspectsURL),
                            DataSourceCredit.Link(title: "CC BY 3.0 IGO", url: ccByIGOURL),
                        ]
                    ),
                ]
            ),
            DataSourceSection(
                id: "map3D",
                title: language.text("3D Map", "3D 地圖"),
                credits: [
                    // Decision 234: what reads the base map's tiles and cuts
                    // its shapes for the 3D map, ported into the game: ISC
                    // asks for its notice in every copy; zlib's licence
                    // asks for none in an app, but the origin is told.
                    DataSourceCredit(
                        id: "map3DGround",
                        title: "earcut, puff",
                        detail: language.text(
                            "Lay the base map’s roads, rivers, woods and parks on the 3D map’s ground.",
                            "把底圖的道路、河川、森林與公園鋪在 3D 地圖的地面上。"
                        ),
                        notice: language.text(
                            "earcut: Copyright (c) 2016, Mapbox, under the ISC License. puff: Copyright (C) 2002-2013 Mark Adler, under the zlib License. Both are altered from the originals.",
                            "earcut：Copyright (c) 2016, Mapbox，依 ISC 授權使用。puff：Copyright (C) 2002-2013 Mark Adler，依 zlib 授權使用。兩者都經過修改。"
                        ) + " " + iscPermission,
                        links: [
                            DataSourceCredit.Link(title: "earcut", url: earcutURL),
                            DataSourceCredit.Link(title: "puff", url: puffURL),
                        ]
                    ),
                    // Decision 331: where the 3D map's temples stand, from
                    // the geo-scene reference's temples file, whose points
                    // each name one of these three sources.
                    DataSourceCredit(
                        id: "temples",
                        title: language.text("Temples", "寺廟"),
                        detail: language.text(
                            "Where the temples of real-world 3D maps stand, and which are drawn larger, from the Ministry of the Interior’s register of temples, OpenStreetMap’s places of worship and the Bureau of Cultural Heritage’s monuments.",
                            "實景 3D 地圖上寺廟的位置，以及哪些畫得比較大，取自內政部的寺廟登記、OpenStreetMap 的宗教場所與文化部文化資產局的古蹟。"
                        ),
                        notice: language.text(
                            "Ministry of the Interior and Bureau of Cultural Heritage data under the Open Government Data License, version 1.0. OpenStreetMap data © OpenStreetMap contributors, under the Open Database License.",
                            "內政部與文化部文化資產局的資料依政府資料開放授權條款第 1 版使用。OpenStreetMap 資料 © OpenStreetMap 貢獻者，依開放資料庫授權條款使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("National Religion Information Network", "全國宗教資訊網"), url: "https://religion.moi.gov.tw"),
                            DataSourceCredit.Link(title: language.text("National Cultural Heritage Database", "國家文化資產網"), url: "https://nchdb.boch.gov.tw"),
                            openGovernmentLicense(in: language),
                            DataSourceCredit.Link(title: "OpenStreetMap", url: openStreetMapCopyrightURL),
                            DataSourceCredit.Link(title: "ODbL", url: odblURL),
                        ]
                    ),
                    // Decision 389: the storeys of the footprints' buildings
                    // in the 3D map, from two city maps and GHSL's heights.
                    DataSourceCredit(
                        id: "buildingStoreys",
                        title: language.text("Building storeys", "建物樓層"),
                        detail: language.text(
                            "How many storeys the real buildings of 3D maps in Taiwan have, from Taichung’s building map and Taipei’s building permit map, and elsewhere how tall the buildings round them are.",
                            "台灣實景 3D 地圖上真實建物的樓層，取自臺中市建物圖與臺北市建築執照套繪圖，其他地方參考周圍建物的高度。"
                        ),
                        notice: language.text(
                            "Taichung City Government, Taichung building map (2022, 2024 and 2025), and Taipei City Government, Taipei building permit map, used under the Open Government Data License, version 1.0. European Commission, Joint Research Centre (2023): GHS-BUILT-H R2023A, average building height, doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE, under CC BY 4.0.",
                            "臺中市政府「臺中市建物圖」（111、113、114 年）與臺北市政府「臺北市建築執照套繪圖」，依政府資料開放授權條款第 1 版使用。European Commission, Joint Research Centre (2023): GHS-BUILT-H R2023A（平均建物高度），doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE，依 CC BY 4.0 使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("Taichung building map (2022)", "臺中市建物圖（111 年）"), url: "https://data.gov.tw/dataset/162900"),
                            DataSourceCredit.Link(title: language.text("Taichung building map (2024)", "臺中市建物圖（113 年）"), url: "https://data.gov.tw/dataset/152106"),
                            DataSourceCredit.Link(title: language.text("Taichung building map (2025)", "臺中市建物圖（114 年）"), url: "https://data.gov.tw/dataset/158889"),
                            DataSourceCredit.Link(title: language.text("Taipei building permit map", "臺北市建築執照套繪圖"), url: "https://data.gov.tw/dataset/151936"),
                            openGovernmentLicense(in: language),
                            DataSourceCredit.Link(title: "GHS-BUILT-H", url: "https://doi.org/10.2905/85005901-3A49-48DD-9D19-6261354F56FE"),
                            DataSourceCredit.Link(title: "CC BY 4.0", url: ccByURL),
                        ]
                    ),
                    // Decision 385: the land the 3D map's town keeps off and
                    // the airports' buildings, from OpenStreetMap's
                    // Taiwan extract (tools/no-build-land).
                    DataSourceCredit(
                        id: "noBuildLand",
                        title: language.text("Airports and open land", "機場與空地"),
                        detail: language.text(
                            "Where real-world 3D maps keep houses off airports, military land, cemeteries, golf courses, railway land and ports, and the airports’ terminals and hangars, from OpenStreetMap.",
                            "實景 3D 地圖上機場、軍事用地、墓地、高爾夫球場、鐵路用地與港區不蓋房子的範圍，以及機場的航廈與機棚，取自 OpenStreetMap。"
                        ),
                        notice: language.text(
                            "OpenStreetMap data © OpenStreetMap contributors, under the Open Database License.",
                            "OpenStreetMap 資料 © OpenStreetMap 貢獻者，依開放資料庫授權條款使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "OpenStreetMap", url: openStreetMapCopyrightURL),
                            DataSourceCredit.Link(title: "ODbL", url: odblURL),
                        ]
                    ),
                    // Decision 391: the decks of the tallest freeway bridges
                    // (Map3DRoadBridges.tallestFreewayBridges).
                    DataSourceCredit(
                        id: "freewayBridges",
                        title: language.text("Tallest freeway bridges", "國道最高橋梁"),
                        detail: language.text(
                            "How high the tallest freeway bridges stand on real-world 3D maps.",
                            "實景 3D 地圖上最高的幾座國道橋梁有多高。"
                        ),
                        notice: language.text(
                            "Source: Freeway Bureau, Ministry of Transportation and Communications, the tallest bridges of the national freeways. Used under the Open Government Data License, version 1.0.",
                            "資料來源：交通部高速公路局「國道最高橋梁資訊」。依「政府資料開放授權條款第 1 版」使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("Dataset (data.gov.tw)", "資料集（政府資料開放平臺）"), url: "https://data.gov.tw/dataset/30616"),
                            openGovernmentLicense(in: language),
                        ]
                    ),
                    // Decision 408: the second high-speed train
                    // (Map3DN700SG), rebuilt from the author's own model in
                    // the reference repository, which the author lets the
                    // game and its public repository carry.
                    DataSourceCredit(
                        id: "highSpeedTrainModel",
                        title: language.text("White high-speed train", "白色高速列車"),
                        detail: language.text(
                            "Half the high-speed trains on the 3D map, white with a dark green line: drawn after a model the game’s author made.",
                            "3D 地圖上一半的高速列車，白色車身配深綠色線條：照遊戲作者自己做的模型畫成。"
                        ),
                        notice: language.text(
                            "Shape and colours after the game author’s own model, used with the author’s permission.",
                            "外形與配色取自遊戲作者自己做的模型，經作者同意使用。"
                        ),
                        links: []
                    ),
                    // The 3D map's city buses (Map3DCityBus): generated by
                    // the owner with Meshy on a paid plan, so the output is
                    // theirs (Meshy's terms §3.2); told as generated, as
                    // tools/meshy/README.md asks.
                    DataSourceCredit(
                        id: "meshy",
                        title: "Meshy",
                        detail: language.text(
                            "The city buses on the 3D map’s streets: a model generated with Meshy’s AI from a description and a photograph.",
                            "3D 地圖街上的公車：用 Meshy 的 AI 依描述與照片生成的模型。"
                        ),
                        notice: language.text(
                            "Generated with Meshy (meshy.ai). The reference photograph: Capital Bus 735-FW, by 玄史生, under CC0 1.0, on Wikimedia Commons.",
                            "以 Meshy（meshy.ai）生成。參考照片：首都客運 735-FW，玄史生攝，依 CC0 1.0 使用，在維基共享資源。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "Meshy", url: meshyURL),
                            DataSourceCredit.Link(title: language.text("Reference photograph", "參考照片"), url: busPhotoURL),
                        ]
                    ),
                ]
            ),
            // Decision 152: the 3D city view of the settings' preview.
            DataSourceSection(
                id: "cityView",
                title: language.text("3D City Preview", "3D 城市預覽"),
                credits: [
                    DataSourceCredit(
                        id: "proceduralTokyo",
                        title: "Procedural Tokyo",
                        detail: language.text(
                            "Draws the 3D city round Kaohsiung and Taichung Stations: buildings, street furniture, traffic, trains, sky and light.",
                            "畫出高雄車站與台中車站周圍的 3D 城市：建物、街道設施、車流、列車、天空與光線。"
                        ),
                        notice: language.text(
                            "Copyright (c) 2026 Yong Su, under the MIT License. It bundles three.js, postprocessing, N8AO, takram three-geospatial, ez-tree, lil-gui and earcut; the page is on the game's website, and their licences (MIT, Zlib, ISC) are next to it, at the link below.",
                            "Copyright (c) 2026 Yong Su，依 MIT 授權使用。內含 three.js、postprocessing、N8AO、takram three-geospatial、ez-tree、lil-gui 與 earcut；網頁放在遊戲官網，這些程式庫的授權條款（MIT、Zlib、ISC）也在官網，可以從下方連結閱讀。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "Procedural Tokyo", url: proceduralTokyoURL),
                            DataSourceCredit.Link(title: language.text("Licences", "授權條款"), url: cityViewNoticesURL),
                        ]
                    ),
                    DataSourceCredit(
                        id: "polyHaven",
                        title: "Poly Haven",
                        detail: language.text(
                            "The textures of the 3D city’s walls, roofs, roads, pavements and grass.",
                            "3D 城市的牆面、屋頂、道路、人行道與草地材質。"
                        ),
                        notice: language.text(
                            "Under CC0 1.0 (public domain dedication).",
                            "依 CC0 1.0（公眾領域貢獻宣告）使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "Poly Haven", url: polyHavenURL),
                            DataSourceCredit.Link(title: "CC0 1.0", url: cc0URL),
                        ]
                    ),
                ]
            ),
            // Decision 343: the running sounds are the game's own, made to
            // the spectra of these recordings (tools/audio/README.md); none
            // of them is bundled. CC BY 3.0 asks for the author, the title,
            // the licence and that the work was changed.
            DataSourceSection(
                id: "sounds",
                title: language.text("Sounds", "聲音"),
                credits: [
                    DataSourceCredit(
                        id: "runningSound",
                        title: language.text("Train recordings", "列車錄音"),
                        detail: language.text(
                            "The sound of a train you follow, which the game makes to sound like these recordings: a KTX in Korea and two trains in Taiwan.",
                            "跟隨列車時的行駛聲，遊戲照這些錄音自己合成：韓國的 KTX 與台灣的兩班列車。"
                        ),
                        notice: language.text(
                            "“Banqiao District, New Taipei City - In the train compartment” by Wu, Tsan-Cheng, under CC BY 3.0. “Guishan, Taoyuan - On the train” by Wu, Tsan-Cheng and “KTX high speed train to Busan” by abyssence, in the public domain. All three on radio aporee ::: maps. The game plays none of the recordings themselves: its sounds are made after them.",
                            "〈Banqiao District, New Taipei City - In the train compartment〉，吳燦政錄音，依 CC BY 3.0 使用。〈Guishan, Taoyuan - On the train〉，吳燦政錄音，與〈KTX high speed train to Busan〉，abyssence 錄音，屬公眾領域。三者都在 radio aporee ::: maps。遊戲不播放錄音本身，聲音是照它們合成的。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("Banqiao recording", "板橋錄音"), url: banqiaoRecordingURL),
                            DataSourceCredit.Link(title: language.text("Guishan recording", "龜山錄音"), url: guishanRecordingURL),
                            DataSourceCredit.Link(title: language.text("KTX recording", "KTX 錄音"), url: ktxRecordingURL),
                            DataSourceCredit.Link(title: "CC BY 3.0", url: ccBy3URL),
                        ]
                    ),
                    // Decision 346: the weather's sounds, made the same way.
                    DataSourceCredit(
                        id: "weatherSound",
                        title: language.text("Rain and thunder recordings", "雨聲與雷聲錄音"),
                        detail: language.text(
                            "The rain, the typhoon’s wind and the thunder, which the game makes to sound like these recordings in Taipei and Tamsui.",
                            "雨聲、颱風的風雨聲與雷聲，遊戲照這些在台北與淡水錄的聲音自己合成。"
                        ),
                        notice: language.text(
                            weatherRecordings.map { "“\($0.title)”" }.joined(separator: ", ") + ", all by Wu, Tsan-Cheng, under CC BY 3.0, on radio aporee ::: maps. The game plays none of the recordings themselves: its sounds are made after them.",
                            weatherRecordings.map { "〈\($0.title)〉" }.joined(separator: "、") + "，都是吳燦政錄音，依 CC BY 3.0 使用，在 radio aporee ::: maps。遊戲不播放錄音本身，聲音是照它們合成的。"
                        ),
                        links: weatherRecordings.map {
                            DataSourceCredit.Link(title: language.text($0.place.english, $0.place.chinese), url: "https://archive.org/details/\($0.id)")
                        } + [DataSourceCredit.Link(title: "CC BY 3.0", url: ccBy3URL)]
                    ),
                ]
            ),
        ]
    }
}
