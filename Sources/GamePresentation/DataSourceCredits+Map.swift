// The data sources page: the base maps, the ground and the place data.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// The map: base maps, terrain, land cover and place data.
    static func mapSection(in language: DisplayLanguage) -> DataSourceSection {
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
                        "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0; the tiles and the tool that makes them come with the app, and a complete machine-readable copy under the same licence is available by writing to \(mailbox.english). The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0). Labels in Noto Sans, © The Noto Project Authors, under the SIL Open Font License 1.1, which comes with the app.",
                        "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用；圖磚與產生它的工具隨 App 提供，也可來信\(mailbox.chinese)索取以相同授權提供的完整機器可讀檔案。圖層照 OpenMapTiles 的格式（CC BY 4.0）。文字用 Noto Sans，© The Noto Project Authors，依 SIL Open Font License 1.1 使用，授權條款隨 App 提供。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                        DataSourceCredit.Link(title: language.text("OpenMapTiles schema", "OpenMapTiles 格式"), url: openMapTilesSchemaURL),
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
                        openStreetMapCopyright(in: language),
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
                // Decision 943: Taiwan's ground, its steep slopes and
                // the base map's hills, from the Ministry of the
                // Interior's terrain model where it reaches; the
                // licence asks for the provider, the year, the dataset
                // and its sentence.
                DataSourceCredit(
                    id: "moiTerrain",
                    title: language.text("Taiwan’s terrain", "台灣的地形"),
                    detail: language.text(
                        "The lie of the land on Taiwan’s main island, the islets beside it and Kinmen: how high the ground is on real-world maps, the hillsides steeper than 30 % where nothing new can be built, and the shaded hills of Taiwan’s OSM base map.",
                        "台灣本島、鄰近小島與金門的地形：實景地圖的地面高低、坡度超過 30%、不能新蓋的山坡地，以及台灣 OSM 底圖上山的陰影。"
                    ),
                    notice: language.text(
                        "Department of Land Administration, Ministry of the Interior, 2026: the 2026 edition of the 20-metre grid digital terrain model (DTM) of the whole of Taiwan. ",
                        "內政部地政司 2026 年「2026年版全臺灣20公尺網格數值地形模型DTM資料」"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: language.text("The dataset", "資料集"), url: moiTerrainURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 115: the steep slopes, worked out from the
                // Copernicus DEM, whose licence asks for this notice;
                // decision 124: the ground's height, from the same
                // data, and the licence's sentence on liability.
                // Decision 943: only where the Ministry of the
                // Interior's model does not reach.
                DataSourceCredit(
                    id: "copernicusDEM",
                    title: "Copernicus DEM",
                    detail: language.text(
                        "The lie of the land where Taiwan’s own terrain model does not reach: Penghu, Matsu, Green Island and a patch of the mountains of Miaoli.",
                        "台灣的地形模型沒有涵蓋的地方的地形：澎湖、馬祖、綠島，以及苗栗山區的一小塊。"
                    ),
                    notice: "Copernicus DEM GLO-30 (Matsu: GLO-90). Produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30.",
                    links: [
                        DataSourceCredit.Link(title: "Copernicus DEM", url: copernicusDEMURL),
                    ]
                ),
                // Decision 811: what covers the countryside's ground,
                // and where the 3D map's forests have trees; CC BY 4.0
                // asks for the project's own credit line.
                DataSourceCredit(
                    id: "esaWorldCover",
                    title: "ESA WorldCover",
                    detail: language.text(
                        "What covers the ground of Taiwan, Penghu, Kinmen and Matsu outside the towns, forest, fields, grassland, bare ground and wetland, on the 3D map, and where its forests have trees.",
                        "台灣、澎湖、金門與馬祖城鎮以外的地面是森林、農田、草地、裸地還是濕地，畫在 3D 地圖上，森林裡也長出樹。"
                    ),
                    notice: language.text(
                        "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium. ESA WorldCover 10 m 2021 v200, under CC BY 4.0. Simplified for the game.",
                        "© ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium。ESA WorldCover 10 m 2021 v200，依 CC BY 4.0 授權使用，為遊戲簡化過。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "ESA WorldCover", url: worldCoverURL),
                        DataSourceCredit.Link(title: "CC BY 4.0", url: ccByURL),
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
        )
    }
}
