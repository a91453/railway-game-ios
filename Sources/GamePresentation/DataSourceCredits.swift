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
    static let odblURL = "https://opendatacommons.org/licenses/odbl/1-0/"
    static let repositoryURL = "https://github.com/a91453/railway-game-ios"
    static let worldPopURL = "https://www.worldpop.org"
    static let copernicusDEMURL = "https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM"
    static let worldPopDatasetURL = "https://doi.org/10.5258/SOTON/WP00840"
    static let ccByURL = "https://creativecommons.org/licenses/by/4.0/"
    static let openFreeMapURL = "https://openfreemap.org"
    static let openMapTilesURL = "https://openmaptiles.org"
    static let mapLibreURL = "https://github.com/maplibre/maplibre-native"
    /// MapLibre Native's licence and its third-party notices, as the app
    /// bundles them (`Resources/Licenses/`).
    static let mapLibreLicenseURL = "https://github.com/a91453/railway-game-ios/blob/main/RailwayGameApp/Resources/Licenses/MapLibre-iOS-LICENSE.md"

    /// The short credit shown on a real-world map while Taiwan's railways
    /// are drawn on it.
    public static func railwaysOnMap(in language: DisplayLanguage) -> String {
        language.text("Railways: MOTC TDX, © OpenStreetMap contributors", "鐵道：交通部 TDX、© OpenStreetMap 貢獻者")
    }

    /// The short credit on a real-world map whose base map is
    /// OpenStreetMap's (decision 97): the wording OpenFreeMap asks for.
    public static func openStreetMapBaseMap(in language: DisplayLanguage) -> String {
        language.text("OpenFreeMap © OpenMapTiles Data from OpenStreetMap", "OpenFreeMap © OpenMapTiles，資料來自 OpenStreetMap")
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
                            "交通部 TDX 運輸資料流通服務"
                        ),
                        detail: language.text(
                            "Routes, station order and names of the High Speed Rail, metro, light rail and Alishan Forest Railway lines; the positions of some TRA stations; official line colours, station codes, addresses and headways.",
                            "提供高鐵、捷運、輕軌與阿里山林鐵的路線、站序與站名，部分台鐵車站的位置，各線的官方路線色、車站代碼、地址與營運班距。"
                        ),
                        notice: language.text(
                            "Used under the Open Government Data License, version 1.0.",
                            "依「政府資料開放授權條款第 1 版」使用。"
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
                            "The timetable of the Pingxi Line's trains, which the real-world demo runs at their real times.",
                            "平溪線各班列車的時刻表，實景示範照真實時刻開車。"
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
                    DataSourceCredit(
                        id: "openStreetMap",
                        title: "OpenStreetMap",
                        detail: language.text(
                            "Track alignments of the TRA and some metro and forest railway sections, station and platform positions, single and double track, places such as shops, offices, schools and sights that tell the game what kind of area a new station serves, and the industrial land, parks and farmland of real-world maps, and their coastline, rivers and lakes, where towns do not grow.",
                            "提供台鐵與部分捷運、林鐵路段的軌道走向、車站與月台位置、單雙線資訊，商店、辦公室、學校、景點等地點（用來判斷新車站周邊是什麼樣的地方），以及實景地圖上的工業區、公園與農地，和海岸線、河川與湖泊（城鎮不會長到水上）。"
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
                    // Decision 97: the OpenStreetMap base map, after `Ci/`'s
                    // credit for it ("OpenFreeMap © OpenMapTiles Data from
                    // OpenStreetMap").
                    DataSourceCredit(
                        id: "openFreeMap",
                        title: "OpenFreeMap",
                        detail: language.text(
                            "The OpenStreetMap base map of real-world maps (the map style menu’s OSM): OpenFreeMap’s vector tiles in its Positron and Dark styles.",
                            "實景地圖的 OpenStreetMap 底圖（地圖樣式選單的「OSM」）：OpenFreeMap 的向量圖磚與它的 Positron、Dark 樣式。"
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
                    // Decision 115: the steep slopes, worked out from the
                    // Copernicus DEM, whose licence asks for this notice;
                    // decision 124: the ground's height, from the same
                    // data, and the licence's sentence on liability.
                    DataSourceCredit(
                        id: "copernicusDEM",
                        title: "Copernicus DEM",
                        detail: language.text(
                            "The heights of Taiwan, Penghu, Kinmen and Matsu (GLO-30, 30 m; Matsu GLO-90): the ground's height on real-world maps, and the hillsides of more than 30 % where nothing new can be built.",
                            "台灣、澎湖、金門與馬祖的地形高度（GLO-30，30 公尺；馬祖為 GLO-90）：實景地圖的地面高度，以及坡度超過 30%、不能新蓋的山坡地。"
                        ),
                        notice: "Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.",
                        links: [
                            DataSourceCredit.Link(title: "Copernicus DEM", url: copernicusDEMURL),
                        ]
                    ),
                ]
            ),
        ]
    }
}
