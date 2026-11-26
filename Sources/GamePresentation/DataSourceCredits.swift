// Where the game's real-world data comes from, and the licences it is used
// under: the data sources screen and the credit on the map.
//
// After the owner's `Railway/` site's own data sources page
// (`Railway/site_archive_clean/data-sources/index.html`) and the notes in
// its data files (`source_notes` of `data/tra.json`, `thsr_track.json`,
// `afr.json`, `trtc.json` and the other systems'): the Ministry of
// Transportation and Communications' TDX under the Open Government Data
// License, version 1.0, and OpenStreetMap under the Open Database License.
// The population that sets a real-world station's ridership is the
// government's own counts, under the Open Government Data License (decision
// 1002, PopulationGrid.swift); the map packs abroad keep WorldPop's (CC BY 4.0).
//
// The page's sections are each in a file of their own,
// `DataSourceCredits+<section>.swift` (DATA-CREDITS-PER-MAP, 2026-11-27):
// Hong Kong, Rovaniemi and Fukuoka one each, and Taiwan's railways, people,
// map, 3D map and city view and sounds; this file keeps the types, the
// shared links and notices, and the order of the sections.
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
    static let worldPopURL = "https://www.worldpop.org"
    static let moiTerrainURL = "https://data.gov.tw/dataset/178729"
    static let copernicusDEMURL = "https://dataspace.copernicus.eu/explore-data/data-collections/copernicus-contributing-missions/collections-description/COP-DEM"
    static let worldCoverURL = "https://doi.org/10.5281/zenodo.7254221"
    static let travelSurveyURL = "https://data.gov.tw/dataset/6248"
    static let civilAviationURL = "https://www.caa.gov.tw"
    static let ccByURL = "https://creativecommons.org/licenses/by/4.0/"
    static let overtureURL = "https://overturemaps.org"
    static let overtureAttributionURL = "https://docs.overturemaps.org/attribution/"
    static let eastAsianBuildingsURL = "https://doi.org/10.5281/zenodo.8174931"
    static let openFreeMapURL = "https://openfreemap.org"
    static let openMapTilesURL = "https://openmaptiles.org"
    static let mapLibreURL = "https://github.com/maplibre/maplibre-native"
    static let openMapTilesSchemaURL = "https://openmaptiles.org/schema/"
    static let notoSansURL = "https://notofonts.github.io"
    /// Noto Sans's licence, from the font project (the text also comes with the app).
    static let notoSansLicenseURL = "https://openfontlicense.org/open-font-license-official-text/"
    /// MapLibre Native's licence, from its project (the text also comes with the app).
    static let mapLibreLicenseURL = "https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md"
    static let proceduralTokyoURL = "https://github.com/jeantimex/tokyo"
    static let slopNewYorkURL = "https://github.com/mrdoob/slop-newyork"
    /// The notices of the 3D city view's page and the libraries it bundles
    /// (decision 152), next to the page on the game's website (decision 163).
    /// Decision 503: whom the ODbL notices offer the derived files from,
    /// the brand's mailbox (``GameBrand/contactEmail``) or the developer.
    static var mailbox: (english: String, chinese: String) {
        GameBrand.current.contactEmail.map { ($0, " \($0) ") } ?? ("the developer", "開發者")
    }

    static var cityViewNoticesURL: String? { CityViewPage.root().map { $0 + "NOTICES.txt" } }
    static let polyHavenURL = "https://polyhaven.com"
    /// Decision 815's later note: the instruments the music is played on.
    /// Its licence asks for links to its own pages, not its download files.
    static let generalUserGSURL = "https://github.com/mrbumpy409/GeneralUser-GS"
    /// THEME-PLAIN item 1: the piano the music is played on (CC BY 3.0,
    /// which asks for the author, the title, the licence and that the
    /// samples were changed) and the strings and harp (CC0).
    static let salamanderPianoURL = "https://github.com/sfzinstruments/SalamanderGrandPiano"
    static let vscoURL = "https://github.com/sgossner/VSCO-2-CE"
    /// Decision 815's later note: whose the game's own music is, the
    /// brand's developer (``GameBrand``).
    static var musicHolder: (english: String, chinese: String) {
        ("the developer of \(GameBrand.current.english)", "\(GameBrand.current.chinese)開發者")
    }
    static let meshyURL = "https://www.meshy.ai"
    static let kenneyNatureKitURL = "https://kenney.nl/assets/nature-kit"
    static let kenneyIndustrialURL = "https://kenney.nl/assets/city-kit-industrial"
    static let kenneyCarKitURL = "https://kenney.nl/assets/car-kit"
    static let taipeiGarbageTrucksURL = "https://data.gov.tw/dataset/136515"
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
    /// Decision 724: the Tourism Administration's visitors by scenic spot.
    static let sightVisitorsURL = "https://data.gov.tw/dataset/8116"
    static let ccByIGOURL = "https://creativecommons.org/licenses/by/3.0/igo/"
    static let ccBy3URL = "https://creativecommons.org/licenses/by/3.0/"
    /// Decision 343: the recordings the running sounds are made to, on
    /// radio aporee ::: maps at the Internet Archive.
    static let banqiaoRecordingURL = "https://archive.org/details/aporee_34085_39187"
    static let guishanRecordingURL = "https://archive.org/details/aporee_17319_20158"
    static let ktxRecordingURL = "https://archive.org/details/aporee_65051_75140"
    /// Decision 567: the site whose KiHa 40 recordings the diesel loops are
    /// made to (its terms want the address in lower case).
    static let gepponkokuURL = "https://gepponkoku.nation.jp"
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
    /// heights (the Ministry of the Interior's terrain model and, where it
    /// does not reach, the Copernicus DEM; decision 943): the photo, shared away from the game's
    /// data sources page, names them all. Decision 811: and the ground's
    /// land cover (ESA WorldCover, CC BY 4.0).
    public static func map3DPhoto(realWorld: Bool, in language: DisplayLanguage) -> String {
        guard realWorld else { return "" }
        return "© OpenStreetMap · Overture Maps · \(language.text("MOI DTM", "內政部 DTM")) · Copernicus DEM · © ESA WorldCover · \(language.text("MOTC TDX", "交通部 TDX"))"
    }

    /// The Open Government Data License, linked from every source under it.
    static func openGovernmentLicense(in language: DisplayLanguage) -> DataSourceCredit.Link {
        DataSourceCredit.Link(title: language.text("Open Government Data License", "政府資料開放授權條款"), url: openGovernmentLicenseURL)
    }

    /// OpenStreetMap's copyright page, linked from every source drawn from
    /// its data.
    static func openStreetMapCopyright(in language: DisplayLanguage) -> DataSourceCredit.Link {
        DataSourceCredit.Link(title: language.text("OpenStreetMap copyright", "OpenStreetMap 版權"), url: openStreetMapCopyrightURL)
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
    ///
    /// Decision 697: an open overseas city's railways are a section of
    /// their own after Taiwan's (none is open yet).
    public static func sections(in language: DisplayLanguage, overseas: Set<OverseasMap> = OverseasMaps.open) -> [DataSourceSection] {
        taiwanSections(in: language) + OverseasMap.allCases.filter(overseas.contains).map { section(of: $0, in: language) }
    }

    /// What an overseas city's railways are and where their data comes
    /// from, with the notices its sources ask for.
    static func section(of city: OverseasMap, in language: DisplayLanguage) -> DataSourceSection {
        switch city {
        case .hongKong: hongKongSection(in: language)
        case .rovaniemi: rovaniemiSection(in: language)
        case .fukuoka: fukuokaSection(in: language)
        }
    }

    /// Taiwan's sections, in the order the page shows them; each is in a
    /// file of its own (DATA-CREDITS-PER-MAP), so a change to one source
    /// touches only that section's file.
    static func taiwanSections(in language: DisplayLanguage) -> [DataSourceSection] {
        [
            taiwanRailwaysSection(in: language),
            railwayDataSection(in: language),
            peopleSection(in: language),
            mapSection(in: language),
            map3DSection(in: language),
            cityViewSection(in: language),
            soundsSection(in: language),
        ]
    }
}
