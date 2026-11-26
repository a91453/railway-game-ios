// The data sources page: Hong Kong's map.
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// Hong Kong's map (decision 712).
    static func hongKongSection(in language: DisplayLanguage) -> DataSourceSection {
        DataSourceSection(
            id: "hongKongRailways",
            title: language.text("Hong Kong’s Railways", "香港的鐵道"),
            credits: [
                DataSourceCredit(
                    id: "hongKongMTR",
                    title: language.text("MTR", "港鐵"),
                    detail: language.text(
                        "The ten railway lines of Hong Kong’s MTR, from the Airport Express to the Disneyland Resort Line, each in its own colour, with their stations’ Chinese and English names. Their trains run to times estimated from how often and how fast the real trains ran on the days they were watched.",
                        "香港港鐵的十條鐵路綫，從機場快綫到迪士尼綫，每條綫用自己的路綫色，車站有中文與英文站名。列車的時刻是照觀察那幾天真實列車的班距與行車時間估出來的。"
                    ),
                    notice: language.text(
                        "Track, station positions, station names, bridges, tunnels and line colours: © OpenStreetMap contributors, ODbL 1.0. Station names and order are checked against, and station codes come from, MTR Corporation Limited’s open data on DATA.GOV.HK (MTR Lines and Stations), used under DATA.GOV.HK’s Terms and Conditions of Use. Headways and running times: worked out from MTR’s Next Train open data on DATA.GOV.HK, November 2026. The intellectual property rights in the MTR data belong to MTR Corporation Limited. The game is not affiliated with MTR Corporation Limited or the Hong Kong SAR Government.",
                        "軌道、車站位置、站名、橋梁、隧道與路綫色：© OpenStreetMap 貢獻者，ODbL 1.0。站名與站序用香港鐵路有限公司在「資料一線通」（DATA.GOV.HK）公開的「港鐵路綫及車站」資料核對，車站代號取自該資料，依「資料一線通」的使用條款及條件使用。班距與行車時間：由港鐵在「資料一線通」公開的「下一班列車」資料（2026 年 11 月）算出。港鐵資料的知識產權屬香港鐵路有限公司所有。本遊戲與香港鐵路有限公司、香港特別行政區政府沒有任何關係。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("DATA.GOV.HK Terms and Conditions of Use", "資料一線通使用條款及條件"), url: "https://data.gov.hk/en/terms-and-conditions"),
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // Decision 712: the base map of Hong Kong's map
                // (`MapPacks/hongkong/basemap.pmtiles`).
                DataSourceCredit(
                    id: "hongKongMap",
                    title: language.text("Hong Kong’s map", "香港的地圖"),
                    detail: language.text(
                        "On Hong Kong’s map, the land and the sea, roads, parks, woods and place names, on the flat map and the 3D map.",
                        "香港地圖上的陸地與海、道路、公園、樹林與地名，平面地圖與 3D 地圖都用。"
                    ),
                    notice: language.text(
                        "© OpenMapTiles © OpenStreetMap contributors. The map data is © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026; the tiles and the tool that makes them come with the app. The tiles’ layers follow the OpenMapTiles schema (CC BY 4.0).",
                        "© OpenMapTiles © OpenStreetMap 貢獻者。地圖資料 © OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月；圖磚與產生它的工具隨 App 提供。圖層照 OpenMapTiles 的格式（CC BY 4.0）。"
                    ),
                    links: [
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // Decision 726: the ground of Hong Kong's map
                // (`MapPacks/hongkong/heights.dat`, `water.json`'s
                // steep slopes, `terrain.pmtiles`).
                DataSourceCredit(
                    id: "hongKongTerrain",
                    title: language.text("Hong Kong’s terrain", "香港的地形"),
                    detail: language.text(
                        "Hong Kong’s hills and sea: how high the ground is where track is laid, and the hill shading of the map.",
                        "香港的山與海：軌道鋪設處地面多高，以及地圖上山的陰影。"
                    ),
                    notice: language.text(
                        "Digital Terrain Model, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal (Common Spatial Data Infrastructure), used under the CSDI Portal Terms and Conditions of Use; the Government and the Lands Department keep their intellectual property rights in the data.",
                        "數碼地形模型，香港特別行政區政府地政總署，經空間數據共享平台（CSDI）提供，依空間數據共享平台的使用條款使用；資料的智慧財產權屬香港特別行政區政府與地政總署。"
                    ),
                    links: [
                        DataSourceCredit.Link(
                            title: language.text("Digital Terrain Model", "數碼地形模型"),
                            url: "https://portal.csdi.gov.hk/geoportal/?datasetId=landsd_rcd_1638158088368_93806"
                        ),
                        DataSourceCredit.Link(
                            title: language.text("CSDI Portal Terms and Conditions of Use", "空間數據共享平台使用條款"),
                            url: "https://portal.csdi.gov.hk/csdi-webpage/doc/TNC"
                        ),
                    ]
                ),
                // Decision 835: what covers Hong Kong's ground
                // (`MapPacks/hongkong/landcover.dat`), from the
                // Planning Department's land use grid.
                DataSourceCredit(
                    id: "hongKongLandUse",
                    title: language.text("Hong Kong’s land use", "香港的土地用途"),
                    detail: language.text(
                        "On Hong Kong’s 3D map, the colour of the ground outside the city, its woods, scrub, grassland, farms and wetlands, and the trees in its woods.",
                        "香港的 3D 地圖上，市區以外地面的顏色：樹林、灌叢、草地、農地與濕地，以及樹林裡的樹。"
                    ),
                    notice: language.text(
                        "Land use: Planning Department, Government of the Hong Kong SAR, via DATA.GOV.HK (2025 Raster Grids on Land Utilization), used under DATA.GOV.HK’s Terms and Conditions of Use. Simplified for the game.",
                        "土地用途：香港特別行政區政府規劃署，經「資料一線通」（DATA.GOV.HK）提供（2025 年土地利用網格），依「資料一線通」的使用條款及條件使用，為遊戲簡化過。"
                    ),
                    links: [
                        DataSourceCredit.Link(
                            title: language.text("Raster Grids on Land Utilization", "土地利用網格"),
                            url: "https://data.gov.hk/en-data/dataset/hk-pland-pland1-land-utilization-in-hong-kong-raster-grid"
                        ),
                        DataSourceCredit.Link(title: language.text("DATA.GOV.HK Terms and Conditions of Use", "資料一線通使用條款及條件"), url: "https://data.gov.hk/en/terms-and-conditions"),
                    ]
                ),
                // Decisions 712, 729 and 791: the buildings of Hong Kong's
                // map (`MapPacks/hongkong/buildings.pmtiles`): the
                // Lands Department's outlines and heights,
                // OpenStreetMap's uses.
                DataSourceCredit(
                    id: "hongKongBuildings",
                    title: language.text("Hong Kong’s buildings", "香港的建物"),
                    detail: language.text(
                        "On Hong Kong’s 3D map, where each building stands, its outline and how tall it is.",
                        "香港的 3D 地圖上每棟建物的位置、外形與高度。"
                    ),
                    notice: language.text(
                        "Outlines and heights: Building data, Lands Department, Government of the Hong Kong SAR, via the CSDI Portal (Common Spatial Data Infrastructure), used under the CSDI Portal Terms and Conditions of Use; the Government and the Lands Department keep their intellectual property rights in the data. What each building is used for: © OpenStreetMap contributors, under the Open Database License (ODbL) 1.0, data to November 2026; the file made from them and the tool that makes it come with the app. Where a building’s height is not recorded, the game estimates it from the recorded buildings like it and from WorldPop’s population (CC BY 4.0). The shapes of the landmark towers, and where the Tsing Ma Bridge’s towers stand and how tall they are: 3D Visualisation Map (non-textured individualised models), Lands Department, Government of the Hong Kong SAR, via Open3Dhk; the Government and the Lands Department keep their intellectual property rights in the data.",
                        "外形與高度：建築物資料，香港特別行政區政府地政總署，經空間數據共享平台（CSDI）提供，依空間數據共享平台的使用條款使用；資料的智慧財產權屬香港特別行政區政府與地政總署。建物的用途：© OpenStreetMap 貢獻者，依開放資料庫授權（ODbL）1.0 使用，資料到 2026 年 11 月；由它們做成的檔與產生它的工具隨 App 提供。沒有記載高度的建物，由遊戲依同類有記載的建物與 WorldPop 的人口（CC BY 4.0）估計。地標大樓的外形，以及青馬大橋橋塔的位置與高度：三維視像化地圖（無紋理單體模型），香港特別行政區政府地政總署，經 Open3Dhk 提供；資料的智慧財產權屬香港特別行政區政府與地政總署。"
                    ),
                    links: [
                        DataSourceCredit.Link(
                            title: language.text("Building data", "建築物資料"),
                            url: "https://portal.csdi.gov.hk/geoportal/?datasetId=landsd_rcd_1637211194312_35158"
                        ),
                        DataSourceCredit.Link(title: language.text("3D Visualisation Map", "三維視像化地圖"), url: "https://3d.map.gov.hk"),
                        DataSourceCredit.Link(
                            title: language.text("CSDI Portal Terms and Conditions of Use", "空間數據共享平台使用條款"),
                            url: "https://portal.csdi.gov.hk/csdi-webpage/doc/TNC"
                        ),
                        openStreetMapCopyright(in: language),
                    ]
                ),
                // Decisions 712 and 1008: the people and jobs of Hong
                // Kong's map (`MapPacks/hongkong/population.json`,
                // `tools/census-grid/hongkong_census_grid.py`).
                DataSourceCredit(
                    id: "hongKongPeople",
                    title: language.text("Hong Kong’s people", "香港的人口"),
                    detail: language.text(
                        "On Hong Kong’s map, how many people live and work round each station, which sets how many ride from it and where they go.",
                        "香港地圖上每座車站周圍住了多少人、有多少人在那裡上班，決定有多少人從那裡搭車、往哪裡去。"
                    ),
                    notice: language.text(
                        "Residents: 2021 Population Census, Census and Statistics Department. Jobs: Quarterly Survey of Employment and Vacancies, 2021, Census and Statistics Department. Tertiary Planning Units and land use: Planning Department. All Government of the Hong Kong SAR, via DATA.GOV.HK and the CSDI Portal (Common Spatial Data Infrastructure), used under their Terms and Conditions of Use. Spread over the homes and workplaces for the game.",
                        "住的人：2021 年人口普查，政府統計處。上班的人：2021 年就業及職位空缺按季統計調查，政府統計處。小規劃統計區與土地用途：規劃署。都是香港特別行政區政府的資料，經「資料一線通」（DATA.GOV.HK）與空間數據共享平台（CSDI）提供，依兩者的使用條款使用；為遊戲分配到住宅與工作的地方。"
                    ),
                    links: [
                        DataSourceCredit.Link(
                            title: language.text("2021 Population Census", "2021 年人口普查"),
                            url: "https://data.gov.hk/en-data/dataset/hk-censtatd-census_geo-2021-population-census-by-ssg"
                        ),
                        DataSourceCredit.Link(
                            title: language.text("Persons engaged by Tertiary Planning Unit", "按小規劃統計區劃分的就業人數"),
                            url: "https://data.gov.hk/en-data/dataset/hk-censtatd-tablechart-215-16009"
                        ),
                        DataSourceCredit.Link(title: language.text("DATA.GOV.HK Terms and Conditions of Use", "資料一線通使用條款及條件"), url: "https://data.gov.hk/en/terms-and-conditions"),
                        DataSourceCredit.Link(
                            title: language.text("CSDI Portal Terms and Conditions of Use", "空間數據共享平台使用條款"),
                            url: "https://portal.csdi.gov.hk/csdi-webpage/doc/TNC"
                        ),
                    ]
                ),
                // Decision 1003: the months' rain and thunder
                // (`Disruptions.countryRain`).
                DataSourceCredit(
                    id: "hongKongWeather",
                    title: language.text("Hong Kong’s weather", "香港的天氣"),
                    detail: language.text(
                        "How often it rains or thunders in each month on Hong Kong’s map.",
                        "香港地圖上每個月多常下雨、打雷。"
                    ),
                    notice: language.text(
                        "Hong Kong Observatory: days with thunderstorms in its monthly normals of 1991–2020, and days with 1 mm of rain or more counted from its daily rainfall of 1991–2020.",
                        "香港天文台：1991–2020 年月平均值的雷暴日數，與由 1991–2020 年每日雨量算出的 1 毫米以上雨日。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Hong Kong Observatory", "香港天文台"), url: "https://www.hko.gov.hk/en/cis/normal/1991_2020/normals.htm"),
                    ]
                ),
                // Decision 712: Hong Kong International Airport on
                // Hong Kong's map (`AirportCatalog.overseasPlaces`).
                DataSourceCredit(
                    id: "hongKongAirport",
                    title: language.text("Hong Kong International Airport", "香港國際機場"),
                    detail: language.text(
                        "On Hong Kong’s map, how many passengers and flights the airport has in a day, and its flights to Taiwan.",
                        "香港地圖上機場一天有多少旅客與航班，以及飛台灣的航線。"
                    ),
                    notice: language.text(
                        "Passengers and flights of 2025: Airport Authority Hong Kong’s traffic figures. Flights to Taiwan: Civil Aviation Administration, Ministry of Transportation and Communications (Taiwan), Civil Aviation Statistics annual report 2025. Position: OpenStreetMap contributors. The game is not affiliated with Airport Authority Hong Kong.",
                        "2025 年的旅客與航班：香港機場管理局公布的航空交通量。飛台灣的航線：交通部民用航空局《民航統計年報》2025 年。位置：OpenStreetMap 貢獻者。本遊戲與香港機場管理局沒有任何關係。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Civil Aviation Administration", "交通部民用航空局"), url: civilAviationURL),
                    ]
                ),
            ]
        )
    }
}
