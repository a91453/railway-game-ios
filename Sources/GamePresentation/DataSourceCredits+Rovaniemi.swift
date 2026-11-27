// The data sources page: Rovaniemi's map.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// Decision 789: Rovaniemi's map (`MapPacks/rovaniemi`, made by
    /// `tools/rovaniemi-map/`), credited once it is open.
    static func rovaniemiSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "rovaniemiRailways",
            title: language.text("Rovaniemi’s Railways", "羅瓦涅米的鐵道"),
            credits: [
                DataSourceCredit(
                    id: "rovaniemiVR",
                    title: language.text("VR’s trains in Lapland", "拉普蘭的芬蘭國鐵列車"),
                    detail: language.text(
                        "The line from Rovaniemi to Misi and Kemijärvi, and the main line south to Muurola, with every passenger train of a week in December at its real times.",
                        "從羅瓦涅米經米西到凱米耶爾維的路線，以及往南到穆羅拉的主線，十二月一週裡每一班客車都照真實時刻行駛。"
                    ),
                    notice: language.text(
                        "Timetables, station codes and station names: Source: Fintraffic / digitraffic.fi, licence CC 4.0 BY. Track, station positions, platforms, bridges and tunnels: © OpenStreetMap contributors, ODbL 1.0. The game is not affiliated with Fintraffic or VR Group.",
                        "時刻、車站代號與站名：來源 Fintraffic／digitraffic.fi，授權 CC 4.0 BY。軌道、車站位置、月台、橋梁與隧道：© OpenStreetMap 貢獻者，ODbL 1.0。本遊戲與 Fintraffic、芬蘭國鐵（VR Group）沒有任何關係。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Digitraffic licence", "Digitraffic 授權"), url: "https://www.digitraffic.fi/en/terms-of-service/"),
                        openStreetMapCopyright(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "rovaniemiMap",
                    title: language.text("Rovaniemi’s map", "羅瓦涅米的地圖"),
                    detail: language.text(
                        "On Rovaniemi’s map, the rivers and lakes, roads, woods, the airport and place names, on the flat map and the 3D map.",
                        "羅瓦涅米地圖上的河流與湖泊、道路、樹林、機場與地名，平面地圖與 3D 地圖都用。"
                    ),
                    notice: language.text(
                        "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026. The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0).",
                        "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月。圖層照 OpenMapTiles 的格式（CC BY 4.0）。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // Decisions 799 and 1009: the pack's buildings, the
                // National Land Survey's with OpenStreetMap's uses.
                DataSourceCredit(
                    id: "rovaniemiBuildings",
                    title: language.text("Rovaniemi’s buildings", "羅瓦涅米的建物"),
                    detail: language.text(
                        "On Rovaniemi’s map, the outlines, uses and heights of the buildings on the 3D map, and the uses and newer buildings the survey does not have.",
                        "羅瓦涅米地圖上，3D 地圖裡建物的外形、用途與高度，以及測量局沒有的用途與新建物。"
                    ),
                    notice: language.text(
                        "Contains data from the National Land Survey of Finland Topographic Database and Buildings 3D (2022), under the Creative Commons Attribution 4.0 licence. Uses and newer buildings: © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026. Storeys that are neither measured nor recorded are this game’s estimate.",
                        "含芬蘭國土測量局（Maanmittauslaitos）地形資料庫與 3D 建物（2022）的資料，依創用 CC 姓名標示 4.0 授權使用。用途與新建物：© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月。沒有實測也沒有記錄的樓層數是本遊戲的估計。"
                    ),
                    links: [
                        nationalLandSurveyLicence(in: language),
                        openStreetMapCopyright(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "rovaniemiTerrain",
                    title: language.text("Rovaniemi’s terrain", "羅瓦涅米的地形"),
                    detail: language.text(
                        "Lapland’s hills and river valleys: how high the ground is where track is laid, and the hill shading of the map.",
                        "拉普蘭的山丘與河谷：軌道鋪設處地面多高，以及地圖上山的陰影。"
                    ),
                    notice: language.text(
                        "Contains data from the National Land Survey of Finland Elevation model 10 m, 08/2023, under the Creative Commons Attribution 4.0 licence.",
                        "含芬蘭國土測量局（Maanmittauslaitos）10 公尺高程模型 2023 年 8 月的資料，依創用 CC 姓名標示 4.0 授權使用。"
                    ),
                    links: [
                        nationalLandSurveyLicence(in: language),
                    ]
                ),
                DataSourceCredit(
                    id: "rovaniemiPopulation",
                    title: language.text("Rovaniemi’s people", "羅瓦涅米的人口"),
                    detail: language.text(
                        "Where people live and work on Rovaniemi’s map, for how many ride from each station.",
                        "羅瓦涅米地圖上的人住在哪裡、在哪裡上班，用來算每一站有多少人搭車。"
                    ),
                    // Decision 1007: Statistics Finland's open data,
                    // spread over the map's buildings (a change the
                    // licence asks to be said).
                    notice: language.text(
                        "Source: Statistics Finland, Population grid data 1 km × 1 km 2025 and Paavo – Open data by postal code area 2025, under the Creative Commons Attribution 4.0 licence; spread over the map’s buildings.",
                        "資料來源：芬蘭統計局（Statistics Finland）1 公里人口格網 2025 年、郵遞區開放統計 Paavo 2025 年，依創用 CC 姓名標示 4.0 授權使用；已依地圖上的建物細分。"
                    ),
                    links: [
                        ccByLicense,
                    ]
                ),
                // Decision 1003: the months' rain and thunder
                // (`Disruptions.countryRain`).
                DataSourceCredit(
                    id: "rovaniemiWeather",
                    title: language.text("Rovaniemi’s weather", "羅瓦涅米的天氣"),
                    detail: language.text(
                        "How often it rains, snows or thunders in each month on Rovaniemi’s map.",
                        "羅瓦涅米地圖上每個月多常下雨、下雪、打雷。"
                    ),
                    notice: language.text(
                        "Finnish Meteorological Institute open data, CC BY 4.0: daily precipitation at Rovaniemi airport, 1998–2020, and lightning within 10 km of the town, 2011–2020, counted by month.",
                        "芬蘭氣象局開放資料，CC BY 4.0：羅瓦涅米機場 1998–2020 年的每日降水，與 2011–2020 年市區 10 公里內的閃電，按月計算。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Finnish Meteorological Institute open data", "芬蘭氣象局開放資料"), url: "https://en.ilmatieteenlaitos.fi/open-data"),
                        DataSourceCredit.Link(title: "CC BY 4.0", url: "https://creativecommons.org/licenses/by/4.0/"),
                    ]
                ),
            ]
        )
    }

    /// The National Land Survey of Finland's open data licence.
    private static func nationalLandSurveyLicence(in language: DisplayLanguage) -> DataSourceCredit.Link {
        DataSourceCredit.Link(title: language.text("National Land Survey open data licence", "芬蘭國土測量局開放資料授權"), url: "https://www.maanmittauslaitos.fi/en/opendata-licence-cc40")
    }
}
