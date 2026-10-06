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
    static let openGovernmentLicenseURL = "https://data.gov.tw/license"
    static let openStreetMapCopyrightURL = "https://www.openstreetmap.org/copyright"
    static let odblURL = "https://opendatacommons.org/licenses/odbl/1-0/"
    static let repositoryURL = "https://github.com/a91453/railway-game-ios"
    static let worldPopURL = "https://www.worldpop.org"
    static let worldPopDatasetURL = "https://doi.org/10.5258/SOTON/WP00840"
    static let ccByURL = "https://creativecommons.org/licenses/by/4.0/"

    /// The short credit shown on a real-world map while Taiwan's railways
    /// are drawn on it.
    public static func railwaysOnMap(in language: DisplayLanguage) -> String {
        language.text("Railways: MOTC TDX, © OpenStreetMap contributors", "鐵道：交通部 TDX、© OpenStreetMap 貢獻者")
    }

    /// Every source, by the part of the game that uses it.
    public static func sections(in language: DisplayLanguage) -> [DataSourceSection] {
        [
            DataSourceSection(
                id: "railways",
                title: language.text("Taiwan’s Railways on Real-World Maps and the Real-World Demo", "實景地圖與實景示範地圖上的台灣鐵道"),
                credits: [
                    DataSourceCredit(
                        id: "tdx",
                        title: language.text(
                            "Ministry of Transportation and Communications, TDX",
                            "交通部 TDX 運輸資料流通服務"
                        ),
                        detail: language.text(
                            "The shapes, station order and station names of the High Speed Rail, the metro and light rail lines and the Alishan Forest Railway; the positions of some TRA stations; the official colours of the Airport MRT, the Danhai and Ankeng light rail, the Sanying Line and the Taichung Metro; the official TRA and metro station codes, addresses, and line headways.",
                            "高鐵、捷運、輕軌與阿里山林鐵的路線幾何、站序與站名，部分台鐵車站的座標，機場捷運、淡海與安坑輕軌、三鶯線與台中捷運的官方路線色，以及台鐵與捷運車站代碼、地址與各線營運班距。"
                        ),
                        notice: language.text(
                            "Used under the Open Government Data License, version 1.0.",
                            "依政府資料開放授權條款第 1 版使用。"
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
                        id: "openStreetMap",
                        title: "OpenStreetMap",
                        detail: language.text(
                            "The shapes of the TRA lines, some metro lines and part of the Alishan Forest Railway, the positions of stations, physical platform coordinates, single and double track estimates, and the shops, offices, schools and sights that decide what kind of place a company’s new station on a real-world map serves, from OpenStreetMap’s contributors.",
                            "台鐵、部分捷運與阿里山林鐵部分路段的軌道幾何、車站的座標、實體月台座標與單雙線估算，以及決定公司在實景地圖上新建車站類型的商店、辦公、學校與景點，來自 OpenStreetMap 貢獻者。"
                        ),
                        notice: language.text(
                            "© OpenStreetMap contributors, under the Open Database License (ODbL) 1.0. The game’s railway, platforms, track sections and places files (track_lines.geojson, track_stations.geojson, tra_platforms.json, tra_track_sections.json and taiwan_places.json) are available under the same licence in its source repository.",
                            "© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用。遊戲的鐵道、月台、單雙線與地點資料檔（track_lines.geojson、track_stations.geojson、tra_platforms.json、tra_track_sections.json、taiwan_places.json）依同一授權，在遊戲的原始碼儲存庫提供。"
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
                            "The station order of the TRA lines (TRA open data) and of the Sanying Line (New Taipei Metro); the official colours of the Taipei and Kaohsiung Metro lines, from their operators’ websites; the colours of the TRA, High Speed Rail and Alishan Forest Railway lines, after their operators’ own colours.",
                            "台鐵路線的站序（台鐵公開資料）與三鶯線的站序（新北捷運公司）；台北捷運與高雄捷運各線的官方路線色，取自營運機構的網站；台鐵、高鐵與阿里山林鐵路線的顏色，依各營運機構的公司色。"
                        ),
                        notice: language.text(
                            "The lines and the English station names are compiled by Along the Line; the game is not affiliated with any operator.",
                            "路線與車站的英文名稱由《沿線》整理；遊戲與各營運機構無關。"
                        ),
                        links: []
                    ),
                ]
            ),
            DataSourceSection(
                id: "places",
                title: language.text("Places to Start", "開始的地點"),
                credits: [
                    DataSourceCredit(
                        id: "places",
                        title: language.text("Stations and cities", "車站與城市"),
                        detail: language.text(
                            "Taiwan’s stations are the railways’ above; the other cities are the city centres of the author’s transit game.",
                            "台灣的車站來自上面的鐵道資料；其他城市是作者的交通經營遊戲的城市中心。"
                        ),
                        notice: language.text(
                            "Station positions © OpenStreetMap contributors (ODbL 1.0) and MOTC TDX.",
                            "車站座標 © OpenStreetMap 貢獻者（ODbL 1.0）與交通部 TDX。"
                        ),
                        links: []
                    ),
                ]
            ),
            DataSourceSection(
                id: "population",
                title: language.text("Station Ridership on Real-World Maps", "實景地圖的車站客流"),
                credits: [
                    DataSourceCredit(
                        id: "worldPop",
                        title: "WorldPop",
                        detail: language.text(
                            "How many people live around a station a company builds on a real-world map in Taiwan, which sets its ridership: WorldPop’s 2025 estimates per square kilometre (R2025A).",
                            "公司在台灣實景地圖上建站時，用來估計車站周邊住了多少人、決定它的客流：WorldPop 2025 年每平方公里的人口估計（R2025A）。"
                        ),
                        notice: language.text(
                            "WorldPop (www.worldpop.org), University of Southampton, under the Creative Commons Attribution 4.0 International licence (CC BY 4.0); DOI 10.5258/SOTON/WP00840. The game rounds each square to whole people.",
                            "WorldPop（www.worldpop.org），南安普敦大學，依創用 CC 姓名標示 4.0 國際授權（CC BY 4.0）使用；DOI 10.5258/SOTON/WP00840。遊戲把每一格的人數四捨五入到整數。"
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
                            "The map under real-world games, and the place search.",
                            "實景地圖的底圖與地點搜尋。"
                        ),
                        notice: language.text(
                            "Its notices are behind the Legal link at the bottom of the map.",
                            "授權聲明見地圖下方的法律聲明連結。"
                        ),
                        links: []
                    ),
                ]
            ),
        ]
    }
}
