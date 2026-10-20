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
    static let odblURL = "https://opendatacommons.org/licenses/odbl/1-0/"
    static let repositoryURL = "https://github.com/a91453/railway-game-ios"
    static let worldPopURL = "https://www.worldpop.org"
    static let copernicusDEMURL = "https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM"
    static let worldPopDatasetURL = "https://doi.org/10.5258/SOTON/WP00840"
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

    /// Every source, by the part of the game that uses it. The same wording
    /// as the data sources page of the game's website.
    public static func sections(in language: DisplayLanguage) -> [DataSourceSection] {
        [
            DataSourceSection(
                id: "railways",
                title: language.text("Taiwan’s Railways", "台灣的鐵道"),
                credits: [
                    DataSourceCredit(
                        id: "tdx",
                        title: language.text(
                            "MOTC Transport Data eXchange (TDX)",
                            "交通部運輸資料流通服務平臺（TDX）"
                        ),
                        detail: language.text(
                            "Routes, station order and names of the High Speed Rail, metro, light rail and Alishan Forest Railway lines; the positions of some TRA stations; official line colours, station codes, addresses and headways.",
                            "提供高鐵、捷運、輕軌與阿里山林鐵的路線、站序與站名，部分台鐵車站的位置，各線的官方路線色、車站代碼、地址與營運班距。"
                        ),
                        notice: language.text(
                            "Ministry of Transportation and Communications, Transport Data eXchange (TDX), 2026: rail stations, lines, station order of lines, line shapes, travel times between stations, headways, station timetables and the High Speed Rail's daily timetable. This open data is released to the public under the Open Government Data License, version 1.0; users may use it provided they comply with the terms of the licence.",
                            "交通部運輸資料流通服務平臺（TDX）2026 年軌道車站、路線、路線站序、路線線型、站間行駛時間、班距、車站時刻表與高鐵每日時刻表（此開放資料依政府資料開放授權條款（Open Government Data License）第 1 版進行公眾釋出，使用者於遵守本條款各項規定之前提下，得利用之。）"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "TDX", url: tdxURL),
                            DataSourceCredit.Link(
                                title: language.text("Open Government Data License", "政府資料開放授權條款"),
                                url: openGovernmentLicenseURL
                            ),
                        ]
                    ),
                    DataSourceCredit(
                        id: "traOpenData",
                        title: language.text("Taiwan Railway open data", "臺鐵開放資料"),
                        detail: language.text(
                            "The timetables of the Pingxi Line's and the Yilan Line's trains, which the real-world demo and the TRA demo run at their real times.",
                            "平溪線與宜蘭線各班列車的時刻表，實景示範與台鐵示範照真實時刻開車。"
                        ),
                        notice: language.text(
                            "Used under the Open Government Data License, version 1.0.",
                            "依「政府資料開放授權條款第 1 版」使用。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("Taiwan Railway open data", "臺鐵開放資料"), url: traOpenDataURL),
                            DataSourceCredit.Link(
                                title: language.text("Open Government Data License", "政府資料開放授權條款"),
                                url: openGovernmentLicenseURL
                            ),
                        ]
                    ),
                    // Decision 298: the real stations' riders a day, which
                    // the transfers of a station by one follow
                    // (`tools/real-ridership/`).
                    DataSourceCredit(
                        id: "ridership",
                        title: language.text("Riders by station", "各站運量"),
                        detail: language.text(
                            "How many people use each TRA, High Speed Rail, Taipei Metro and Kaohsiung Metro station a day, in 2025: a station of yours beside one gets riders changing from the real trains in proportion.",
                            "台鐵、高鐵、台北捷運與高雄捷運各站 2025 年平均每天的進出人數：你的車站在真實車站旁，轉乘過來的旅客照它的人數多寡。"
                        ),
                        notice: language.text(
                            "Taiwan Railway Corporation, daily entries and exits by station; Taipei Rapid Transit Corporation, hourly entries and exits by station; Kaohsiung City Government, entries and exits by station of the Kaohsiung Metro: used under the Open Government Data License, version 1.0. Taiwan High Speed Rail Corporation, passengers entering and leaving each station, from its published operating statistics.",
                            "國營臺灣鐵路股份有限公司「臺鐵每日各站點進出站人數」、臺北大眾捷運股份有限公司「臺北捷運各站分時進出量統計」、高雄市政府「高雄都會區大眾捷運系統各站旅運量入站、出站」，依「政府資料開放授權條款第 1 版」使用；台灣高速鐵路股份有限公司「客運運輸情形：各站進出旅客人數」，取自其公布的營運統計。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("TRA entries and exits", "臺鐵各站進出站人數"), url: "https://data.gov.tw/dataset/8792"),
                            DataSourceCredit.Link(title: language.text("Taipei Metro entries and exits", "臺北捷運各站進出量"), url: "https://data.gov.tw/dataset/128506"),
                            DataSourceCredit.Link(title: language.text("Kaohsiung Metro entries and exits", "高雄捷運各站旅運量"), url: "https://data.gov.tw/dataset/159641"),
                            DataSourceCredit.Link(title: language.text("High Speed Rail operating statistics", "高鐵客運運輸情形"), url: "https://www.thsrc.com.tw/corp/9571df11-8524-4935-8a46-0d5a72e6bc7c"),
                            DataSourceCredit.Link(
                                title: language.text("Open Government Data License", "政府資料開放授權條款"),
                                url: openGovernmentLicenseURL
                            ),
                        ]
                    ),
                    // Decision 279: through the reference's
                    // `level-profiles.json`, the official railway and
                    // high-speed railway geometry that fills in
                    // OpenStreetMap's bridges and tunnels.
                    DataSourceCredit(
                        id: "nlsc",
                        title: language.text("National Land Surveying and Mapping Center", "內政部國土測繪中心"),
                        detail: language.text(
                            "Where the TRA's and the High Speed Rail's lines run on bridges and viaducts or through tunnels, which the demos' track and track traced along them follow.",
                            "台鐵與高鐵各線在橋梁、高架與隧道上的路段，示範的軌道與沿真實鐵路描的軌道照著蓋。"
                        ),
                        notice: language.text(
                            "National Land Surveying and Mapping Center, Ministry of the Interior, 2026: Taiwan Railway and High Speed Railway. This open data is released to the public under the Open Government Data License, version 1.0; users may use it provided they comply with the terms of the licence.",
                            "內政部國土測繪中心 2026 年臺灣鐵路、高速鐵路（此開放資料依政府資料開放授權條款（Open Government Data License）第 1 版進行公眾釋出，使用者於遵守本條款各項規定之前提下，得利用之。）"
                        ),
                        links: [
                            DataSourceCredit.Link(title: language.text("Taiwan Railway (data.gov.tw)", "臺灣鐵路（政府資料開放平臺）"), url: nlscRailwayURL),
                            DataSourceCredit.Link(
                                title: language.text("High Speed Railway (data.gov.tw)", "高速鐵路（政府資料開放平臺）"), url: nlscHighSpeedRailURL
                            ),
                            DataSourceCredit.Link(
                                title: language.text("Open Government Data License", "政府資料開放授權條款"),
                                url: openGovernmentLicenseURL
                            ),
                        ]
                    ),
                    DataSourceCredit(
                        id: "openStreetMap",
                        title: "OpenStreetMap",
                        detail: language.text(
                            "The track of every real railway line, station and platform positions, single and double track, where the TRA's, the High Speed Rail's and the Alishan Forest Railway's lines are on bridges and in tunnels; places such as shops, offices, schools and sights round new stations; the industrial land, parks, farmland, coastline, rivers and lakes of real-world maps; the names of the settlements, villages and townships new stations are named after; where the tourist sights of real-world maps stand; where the high-speed demo's depots and the TRA demo's Yilan and Su'aoxin sidings stand and how many platform tracks the high-speed demo's end stations have; the roads, parks and shop names of the 3D city preview.",
                            "提供每條真實鐵道的軌道走向、車站與月台位置、單雙線資訊、台鐵、高鐵與林鐵在橋梁與隧道上的路段；新車站周邊的商店、辦公室、學校、景點等地點；實景地圖上的工業區、公園、農地、海岸線、河川與湖泊；替新車站命名的聚落、村里與鄉鎮市區名稱；實景地圖上觀光景點的位置；高鐵示範的機廠與台鐵示範宜蘭、蘇澳新側線的位置、高鐵示範端點站的股道數；3D 城市預覽的道路、公園與店名。"
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
                    DataSourceCredit(
                        id: "operators",
                        title: language.text("Railway operators", "鐵道營運機構"),
                        detail: language.text(
                            "Station order of the TRA lines (TRA open data) and the Sanying Line (New Taipei Metro); Taipei and Kaohsiung Metro line colours from the operators’ websites; TRA, High Speed Rail and Alishan Forest Railway colours after each operator’s own colours.",
                            "台鐵與三鶯線的站序取自台鐵公開資料與新北捷運公司；台北捷運、高雄捷運的路線色取自各營運機構網站；台鐵、高鐵與阿里山林鐵的路線色參考各機構的代表色。"
                        ),
                        notice: language.text(
                            "English line and station names are compiled by Along the Line. The game is not affiliated with any operator.",
                            "路線與車站的英文名稱由《沿線》整理。本遊戲與各營運機構沒有任何關係。"
                        ),
                        links: []
                    ),
                ]
            ),
            DataSourceSection(
                id: "population",
                title: language.text("Population and Ridership", "人口與客源"),
                credits: [
                    DataSourceCredit(
                        id: "worldPop",
                        title: "WorldPop",
                        detail: language.text(
                            "When you build a station on a real-world map of Taiwan, the game uses WorldPop’s 2025 population estimates per square kilometre (R2025A) to work out the people and ridership around it. The population grid layer uses the same data.",
                            "在台灣實景地圖上蓋車站時，遊戲用 WorldPop 2025 年每平方公里的人口估計（R2025A）計算車站周邊的人口與客源。人口網格圖層也使用這份資料。"
                        ),
                        notice: language.text(
                            "WorldPop (www.worldpop.org), University of Southampton, under the Creative Commons Attribution 4.0 International licence (CC BY 4.0); DOI 10.5258/SOTON/WP00840. The game rounds each square to whole people.",
                            "WorldPop（www.worldpop.org），英國南安普敦大學，依創用 CC 姓名標示 4.0 國際授權（CC BY 4.0）使用，DOI 10.5258/SOTON/WP00840。遊戲將每格人數四捨五入為整數。"
                        ),
                        links: [
                            DataSourceCredit.Link(title: "WorldPop", url: worldPopURL),
                            DataSourceCredit.Link(title: language.text("Dataset", "資料集"), url: worldPopDatasetURL),
                            DataSourceCredit.Link(title: "CC BY 4.0", url: ccByURL),
                        ]
                    ),
                    // Decision 147: how much of the ground real buildings
                    // cover, which sets what buying out a city building
                    // costs. Overture's buildings theme is ODbL 1.0; in
                    // Taiwan its footprints are OpenStreetMap's and Shi et
                    // al.'s (CC BY 4.0), each credited as it asks. Decision
                    // 239: the 3D map's real buildings are its footprints.
                    DataSourceCredit(
                        id: "overtureBuildings",
                        title: language.text("Overture Maps buildings", "Overture Maps 建物"),
                        detail: language.text(
                            "How much of the ground real buildings cover on real-world maps of Taiwan and Penghu, from the footprints of Overture Maps’ buildings (release 2026-09-23.1): it sets what buying out the city’s buildings costs, so a car park costs little and a dense block a lot. The buildings round Kaohsiung and Taichung Stations, in the 3D city preview and the 3D map, are its footprints too.",
                            "台灣與澎湖實景地圖上真實建物佔地的比例，取自 Overture Maps 建物的足跡（2026-09-23.1 版）：決定收購城市建物的費用，停車場便宜、密集的街區貴。高雄車站與臺中車站周圍的建物（3D 城市預覽與 3D 地圖）也是它的足跡。"
                        ),
                        notice: language.text(
                            "Overture Maps Foundation (overturemaps.org), under the Open Database License (ODbL) 1.0. Its footprints in Taiwan are © OpenStreetMap contributors (ODbL 1.0) and, where OpenStreetMap has none, from Qian Shi et al., “A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework”, Zenodo, 2023 (CC BY 4.0). The coverage file and the city tiles the game derives from them are available under the same licence from the source repository.",
                            "Overture Maps Foundation（overturemaps.org），依開放資料庫授權（ODbL）1.0 使用。台灣的足跡來自 © OpenStreetMap 貢獻者（ODbL 1.0），OpenStreetMap 沒有的地方來自 Qian Shi 等人〈A first high-quality vector data of buildings in East Asian countries based on a comprehensive large-scale mapping framework〉，Zenodo，2023（CC BY 4.0）。遊戲據此整理的建蔽率檔與城市圖塊以相同授權提供，可從原始碼儲存庫取得。"
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
                            "The base map and place search for real-world maps.",
                            "實景地圖的底圖與地點搜尋。"
                        ),
                        notice: language.text(
                            "See the Legal link at the bottom left of the map for its notices.",
                            "授權聲明請見地圖左下角的「法律資訊」。"
                        ),
                        links: []
                    ),
                    // Decision 262: where the large cities' main stations
                    // stand, the places a real-world game can start at.
                    DataSourceCredit(
                        id: "wikidata",
                        title: "Wikidata",
                        detail: language.text(
                            "Where the main stations of many of the cities in the real-world map’s list stand.",
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
                            "How many people live in each city of the real-world map’s list, which puts the largest first.",
                            "實景地圖城市清單裡各城市的人口，清單依它從大排到小。"
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
                    // Decision 151: Taiwan's base map, the app's own tiles
                    // of OpenStreetMap and their glyphs.
                    DataSourceCredit(
                        id: "taiwanBaseMap",
                        title: language.text("Taiwan’s OpenStreetMap base map", "台灣的 OpenStreetMap 底圖"),
                        detail: language.text(
                            "The OpenStreetMap base map of real-world maps in Taiwan (OSM in the map style menu), which works without a network: sea, rivers, woods, parks, roads, boundaries and place names, with labels in Noto Sans. The 3D map lays its sea, rivers, woods, parks and roads on the ground.",
                            "台灣實景地圖的 OpenStreetMap 底圖（地圖樣式選單的「OSM」），不用網路也能顯示：海、河川、森林、公園、道路、行政界與地名，文字用 Noto Sans。3D 地圖把其中的海、河川、森林、公園與道路鋪在地面上。"
                        ),
                        notice: language.text(
                            "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0; the tiles and the tool that makes them are in the game’s public repository under the same licence. The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0). Noto Sans is © The Noto Project Authors, under the SIL Open Font License 1.1, which comes with the app.",
                            "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用；圖磚與產生它的工具依同一授權放在遊戲公開的原始碼儲存庫。圖層照 OpenMapTiles 的格式（CC BY 4.0）。Noto Sans © The Noto Project Authors，依 SIL Open Font License 1.1 使用，授權條款隨 App 提供。"
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
                            "The OpenStreetMap base map of real-world maps outside Taiwan (the map style menu’s OSM): OpenFreeMap’s vector tiles, in the game’s own style.",
                            "台灣以外的實景地圖的 OpenStreetMap 底圖（地圖樣式選單的「OSM」）：OpenFreeMap 的向量圖磚，用遊戲自己的樣式。"
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
                            "The software that draws the OpenStreetMap base map.",
                            "繪製 OpenStreetMap 底圖的軟體。"
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
                    // Decision 234: what reads the base map's tiles and cuts
                    // its shapes for the 3D map, ported into the game: ISC
                    // asks for its notice in every copy; zlib's licence
                    // asks for none in an app, but the origin is told.
                    DataSourceCredit(
                        id: "map3DGround",
                        title: "earcut, puff",
                        detail: language.text(
                            "The software that lays the base map's roads, rivers, woods and parks on the 3D map's ground.",
                            "把底圖的道路、河川、森林與公園鋪在 3D 地圖地面上的軟體。"
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
                    // Decision 115: the steep slopes, worked out from the
                    // Copernicus DEM, whose licence asks for this notice;
                    // decision 124: the ground's height, from the same
                    // data, and the licence's sentence on liability.
                    DataSourceCredit(
                        id: "copernicusDEM",
                        title: "Copernicus DEM",
                        detail: language.text(
                            "The heights of Taiwan, Penghu, Kinmen and Matsu (GLO-30, 30 m; Matsu GLO-90): the ground's height on real-world maps, the hillsides of more than 30 % where nothing new can be built, and the shading of the hills on Taiwan's OpenStreetMap base map.",
                            "台灣、澎湖、金門與馬祖的地形高度（GLO-30，30 公尺；馬祖為 GLO-90）：實景地圖的地面高度、坡度超過 30%、不能新蓋的山坡地，以及台灣 OpenStreetMap 底圖的山的陰影。"
                        ),
                        notice: "Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.",
                        links: [
                            DataSourceCredit.Link(title: "Copernicus DEM", url: copernicusDEMURL),
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
                            "The software that draws the 3D city round Kaohsiung and Taichung Stations from Overture Maps’ buildings and OpenStreetMap’s roads, parks and places: buildings, street furniture, traffic, trains, sky and light. With three.js, postprocessing, N8AO, takram three-geospatial, ez-tree, lil-gui and earcut bundled into it.",
                            "繪製高雄車站與臺中車站周圍 3D 城市的軟體（建物、街道設施、車流、列車、天空與光線），資料來自 Overture Maps 的建物與 OpenStreetMap 的道路、公園與地點。內含 three.js、postprocessing、N8AO、takram three-geospatial、ez-tree、lil-gui 與 earcut。"
                        ),
                        notice: language.text(
                            "Copyright (c) 2026 Yong Su, under the MIT License. The page is on the game's website, and the licences of the libraries it bundles (MIT, Zlib, ISC) are next to it, at the link below.",
                            "Copyright (c) 2026 Yong Su，依 MIT 授權使用。網頁放在遊戲官網，它內含的程式庫的授權條款（MIT、Zlib、ISC）也在官網，可以從下方連結閱讀。"
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
        ]
    }
}
