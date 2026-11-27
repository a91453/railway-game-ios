// The data sources page: the 3D map (ground, buildings' storeys, models).
// One file of `DataSourceCredits` (DATA-CREDITS-PER-MAP): `sections(in:)` in
// DataSourceCredits.swift lists the sections in their order; the shared
// links and notices are there too.

extension DataSourceCredits {
    /// The 3D map: its ground, buildings' storeys and models.
    static func map3DSection(in language: DisplayLanguage) -> DataSourceSection {
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
                // Decision 725: the shape of ten Taipei temples, from
                // the city's religious buildings' 3D models.
                DataSourceCredit(
                    id: "taipeiTempleModels",
                    title: language.text("Taipei temple models", "臺北廟宇模型"),
                    detail: language.text(
                        "The shape of Longshan Temple, Xingtian Temple, Zhinan Temple, six more of Taipei’s temples and a church in 3D maps, painted in the game’s colours.",
                        "3D 地圖上龍山寺、行天宮、指南宮等十座臺北廟宇與教堂的外形，塗上遊戲的顏色。"
                    ),
                    notice: language.text(
                        "Department of Civil Affairs, Taipei City Government: Taipei religious buildings 3D models, used under the Open Government Data License, version 1.0.",
                        "臺北市政府民政局「臺北市宗教建築 3D 模型庫」，依政府資料開放授權條款第 1 版使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Taipei religious buildings 3D models", "臺北市宗教建築 3D 模型庫"),
                                              url: "https://data.gov.tw/dataset/121136"),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 389: the storeys of the footprints' buildings
                // in the 3D map, from two city maps and GHSL's heights;
                // decision 1011: the usage permits of New Taipei, Taipei
                // and Hsinchu City, found by their door-number points,
                // Tainan's, found by its parcels' centres, and elsewhere
                // the real-price registry's storeys at its door numbers.
                // Decision 1015: in Taichung the outlines are the
                // building map's too, and Overture's fill only the gaps.
                DataSourceCredit(
                    id: "buildingStoreys",
                    title: language.text("Building storeys", "建物樓層"),
                    detail: language.text(
                        "How many storeys the real buildings of 3D maps in Taiwan have, from Taichung’s building map, Taipei’s building permit map the usage permits of New Taipei, Taipei, Tainan and Hsinchu City and the real-price registry of home sales, and elsewhere how tall the buildings round them are. In Taichung the buildings’ outlines are the building map’s too. Where the map has no building, the homes sold in the real-price registry stand along the roads with their own storeys.",
                        "台灣實景 3D 地圖上真實建物的樓層，取自臺中市建物圖、臺北市建築執照套繪圖、新北市、臺北市、臺南市、新竹市的使用執照與內政部實價登錄，其他地方參考周圍建物的高度。台中市的建物輪廓也取自臺中市建物圖。地圖上沒有建物的地方，路邊照實價登錄賣過的房子蓋，樓層和房型照登錄。"
                    ),
                    notice: language.text(
                        "Taichung City Government, Taichung building map (2022, 2024 and 2025); Taipei City Government, Taipei building permit map and Taipei usage permit summaries; New Taipei City Government, New Taipei building permits; Tainan City Government, Tainan usage permits and parcel centres; Hsinchu City Government, Hsinchu City usage permits; Ministry of the Interior, Department of Land Administration, real-price registry of real estate transactions; and the door-number points of Taiwan’s cities and counties by their governments, through OpenAddresses and Overture Maps; used under the Open Government Data License, version 1.0. European Commission, Joint Research Centre (2023): GHS-BUILT-H R2023A, average building height, doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE, under CC BY 4.0.",
                        "臺中市政府「臺中市建物圖」（111、113、114 年）；臺北市政府「臺北市建築執照套繪圖」「臺北市歷年使用執照摘要」；新北市政府「新北市建築執照存查」；臺南市政府「臺南市政府使用執照資料」「臺南市宗地地號屬性資料」；新竹市政府「新竹市使用執照清冊」；內政部地政司「不動產買賣實價登錄批次資料」；各縣市政府的門牌坐標（經 OpenAddresses、Overture Maps 取得）；依政府資料開放授權條款第 1 版使用。European Commission, Joint Research Centre (2023): GHS-BUILT-H R2023A（平均建物高度），doi:10.2905/85005901-3A49-48DD-9D19-6261354F56FE，依 CC BY 4.0 使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: language.text("Taichung building map (2022)", "臺中市建物圖（111 年）"), url: "https://data.gov.tw/dataset/162900"),
                        DataSourceCredit.Link(title: language.text("Taichung building map (2024)", "臺中市建物圖（113 年）"), url: "https://data.gov.tw/dataset/152106"),
                        DataSourceCredit.Link(title: language.text("Taichung building map (2025)", "臺中市建物圖（114 年）"), url: "https://data.gov.tw/dataset/158889"),
                        DataSourceCredit.Link(title: language.text("Taipei building permit map", "臺北市建築執照套繪圖"), url: "https://data.gov.tw/dataset/151936"),
                        DataSourceCredit.Link(title: language.text("Taipei usage permit summaries", "臺北市歷年使用執照摘要"), url: "https://data.gov.tw/dataset/128203"),
                        DataSourceCredit.Link(title: language.text("New Taipei building permits", "新北市建築執照存查"), url: "https://data.gov.tw/dataset/123639"),
                        DataSourceCredit.Link(title: language.text("Tainan usage permits", "臺南市政府使用執照資料"), url: "https://data.gov.tw/dataset/121026"),
                        DataSourceCredit.Link(title: language.text("Tainan parcel centres", "臺南市宗地地號屬性資料"), url: "https://data.gov.tw/dataset/176361"),
                        DataSourceCredit.Link(title: language.text("Hsinchu City usage permits", "新竹市使用執照清冊"), url: "https://data.gov.tw/dataset/163823"),
                        DataSourceCredit.Link(title: language.text("Real-price registry", "不動產買賣實價登錄批次資料"), url: "https://data.gov.tw/dataset/18703"),
                        DataSourceCredit.Link(title: "OpenAddresses", url: "https://openaddresses.io"),
                        openGovernmentLicense(in: language),
                        DataSourceCredit.Link(title: "GHS-BUILT-H", url: "https://doi.org/10.2905/85005901-3A49-48DD-9D19-6261354F56FE"),
                        ccByLicense,
                    ]
                ),
                // Decision 385: the land the 3D map's town keeps off and
                // the airports' buildings, from OpenStreetMap's
                // Taiwan extract (tools/no-build-land).
                DataSourceCredit(
                    id: "noBuildLand",
                    title: language.text("Airports and open land", "機場與空地"),
                    detail: language.text(
                        "Where real-world 3D maps keep houses off airports, military land, cemeteries, golf courses, railway land and ports, and the airports’ terminals, hangars, runways, taxiways, aprons and stands, from OpenStreetMap.",
                        "實景 3D 地圖上機場、軍事用地、墓地、高爾夫球場、鐵路用地與港區不蓋房子的範圍，以及機場的航廈、機棚、跑道、滑行道、停機坪與機位，取自 OpenStreetMap。"
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
                // (decision 979: Map3DN700S, the author's own N700S of
                // the earlier version, its texture cut into faces of the
                // game's colours), which the author lets the game and
                // its public repository carry.
                DataSourceCredit(
                    id: "highSpeedTrainModel",
                    title: language.text("White high-speed train", "白色高速列車"),
                    detail: language.text(
                        "The Train Pack’s high-speed train on the 3D map, white with two blue lines: a model the game’s author made.",
                        "列車包裡 3D 地圖上的高速列車，白色車身配兩道藍色線條：遊戲作者自己做的模型。"
                    ),
                    notice: language.text(
                        "The game author’s own model from the game’s earlier version, in the game’s colours, used with the author’s permission.",
                        "遊戲作者在舊版遊戲裡自己做的模型，換成遊戲的配色，經作者同意使用。"
                    ),
                    links: []
                ),
                // Decisions 988 and 989: the 700T (Map3DTHSR700T) and
                // the 700 series in its own paint (Map3DSeries700),
                // the author's own 700 series cars of the earlier
                // version, their texture cut into faces of the game's
                // colours.
                DataSourceCredit(
                    id: "highSpeed700Model",
                    title: language.text("High-speed 700T and 700 Series", "高鐵 700T 與 700 系"),
                    detail: language.text(
                        "The high-speed line’s 700T on the 3D map, white with an orange band, and the white and blue 700 Series in the garage: models the game’s author made.",
                        "3D 地圖上高鐵的 700T（白色車身配橘色帶）和車庫裡白色車身配藍帶的 700 系：遊戲作者自己做的模型。"
                    ),
                    notice: language.text(
                        "The game author’s own models from the game’s earlier version, in the game’s colours, used with the author’s permission.",
                        "遊戲作者在舊版遊戲裡自己做的模型，換成遊戲的配色，經作者同意使用。"
                    ),
                    links: []
                ),
                // Decision 767: the coal bunker in the old brick plants'
                // yards (Map3DSceneryProp.coalBunker), the author's own
                // model from the earlier version, recoloured
                // (tools/coal-bunker/).
                DataSourceCredit(
                    id: "coalBunkerModel",
                    title: language.text("Coaling stage", "給炭台"),
                    detail: language.text(
                        "The coaling stage with its conveyor in the old brick plants’ yards on the 3D map: a model the game’s author made.",
                        "3D 地圖上老磚廠空地裡、附輸送帶的給炭台：遊戲作者自己做的模型。"
                    ),
                    notice: language.text(
                        "The game author’s own model, in the game’s colours, used with the author’s permission.",
                        "遊戲作者自己做的模型，換成遊戲的配色，經作者同意使用。"
                    ),
                    links: []
                ),
                // The 3D map's city buses (Map3DCityBus): generated by
                // the owner with Meshy on a paid plan, so the output is
                // theirs (Meshy's terms §3.2); told as generated, as
                // tools/meshy/README.md asks. Decision 467: and the stop
                // poles (Map3DSceneryProp), said to be generated as
                // Meshy's terms §2.4 ask (decision 940: the post boxes
                // are the studio's now, not Meshy's). Decision 787: and
                // the people seen close up (Map3DCommuterFigure), told as
                // AI-generated. Decision 927: and the Great Buddha of
                // Baguashan (Map3DBaguashanBuddha), its statue Meshy's.
                // Decision 935: and the night market's bulbs, canopy and
                // cart, the Tiangong burner (Map3DMeshyMarketTemple) and the
                // stone lions (Map3DTempleStoneLion). Decision 1035: and
                // the dragons, columns, Tudigong, dog and pigeons
                // (Map3DTempleProp).
                // Decision 918: and five more people (Map3DPedestrian) and
                // the parked bicycles (Map3DBicycle).
                DataSourceCredit(
                    id: "meshy",
                    title: "Meshy",
                    detail: language.text(
                        "The city buses on the 3D map’s streets: a model generated with Meshy’s AI from a description and a photograph. The evening garbage truck and recycling truck, the bus stop signs on the pavements, and the level crossings’ barriers and warning lights: models generated by AI from a description, simplified and in the game’s colours. The night markets’ strings of bulbs, striped canopies and snack carts, the Tiangong burners, stone lions and dragon columns before the temples, the cut-tile dragons on their roofs, the Tudigong figures at the shrines, and the dogs and pigeons on temple squares and station forecourts: models generated by AI from a description, simplified and in the game’s colours. The people on the platforms, streets and bus stops, seen close up, and the parked bicycles: AI-generated models, simplified and in the game’s colours. The Great Buddha of Baguashan in Changhua: a statue generated with Meshy’s AI, simplified and in the game’s colours.",
                        "3D 地圖街上的公車：用 Meshy 的 AI 依描述與照片生成的模型。傍晚的垃圾車與資源回收車，人行道上的公車站牌，以及平交道的柵欄與警示燈：用 AI 依描述生成的模型，經過簡化並換成遊戲的配色。夜市的燈泡串、帆布棚與小吃推車，廟前的天公爐、石獅與龍柱，廟頂的剪黏雙龍，土地公廟的土地公像，以及廟埕與車站前的土狗與鴿子：用 AI 依描述生成的模型，經過簡化並換成遊戲的配色。近看時月台、街上與公車站的行人，以及停著的腳踏車：AI 生成的模型，經過簡化並換成遊戲的配色。彰化八卦山的大佛：用 Meshy 的 AI 生成的佛像，經過簡化並換成遊戲的配色。"
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
                // Decision 458: the conifers, bushes and tanks
                // (Map3DSceneryProp), reshaped from Kenney's CC0 models
                // (tools/kenney-props/SOURCE.md). CC0 asks for no
                // credit; Kenney's licence file welcomes it. Decision
                // 838: and the cars on Taiwan's streets (Car Kit,
                // tools/tw-cars/README.md).
                DataSourceCredit(
                    id: "kenney",
                    title: "Kenney",
                    detail: language.text(
                        "The conifers in the 3D map’s mountain woods, the bushes by the stations and the line, the tanks in the factory yards and the cars on the streets: Kenney’s models, reshaped and in the game’s colours.",
                        "3D 地圖山區樹林裡的針葉樹、車站前與沿線的灌木叢、工廠空地的儲槽、街上的汽車：Kenney 的模型，改了形狀並換成遊戲的配色。"
                    ),
                    notice: language.text(
                        "Nature Kit, City Kit (Industrial) and Car Kit by Kenney (kenney.nl), under CC0 1.0 (public domain dedication).",
                        "Kenney（kenney.nl）的 Nature Kit、City Kit (Industrial) 與 Car Kit，依 CC0 1.0（公眾領域貢獻宣告）使用。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Nature Kit", url: kenneyNatureKitURL),
                        DataSourceCredit.Link(title: "City Kit (Industrial)", url: kenneyIndustrialURL),
                        DataSourceCredit.Link(title: "Car Kit", url: kenneyCarKitURL),
                        DataSourceCredit.Link(title: "CC0 1.0", url: cc0URL),
                    ]
                ),
                // Decision 437: the garbage truck's hours, stops and
                // pace, measured from Taipei's open data.
                DataSourceCredit(
                    id: "taipeiGarbageTrucks",
                    title: language.text("Taipei garbage truck stops and routes", "臺北市垃圾車點位路線資訊"),
                    detail: language.text(
                        "When the evening garbage truck comes round on the 3D map’s streets, how often it stops and how fast it drives.",
                        "3D 地圖街上傍晚的垃圾車幾點出來、多久停一站、開多快。"
                    ),
                    notice: language.text(
                        "Department of Environmental Protection, Taipei City Government, 2026: Taipei garbage truck stops and routes. ",
                        "臺北市政府環境保護局 2026 年「臺北市垃圾車點位路線資訊」"
                    ) + openGovernmentAttribution(in: language),
                    links: [
                        DataSourceCredit.Link(title: language.text("Dataset", "資料集"), url: taipeiGarbageTrucksURL),
                        openGovernmentLicense(in: language),
                    ]
                ),
                // Decision 827: the Tamsui-Xinyi line's elevated station
                // shells started from Slop New York's code and shapes.
                // Decision 391 (後來, ELEVATED-ROAD-HEIGHT): the heights
                // of the elevated roads' levels are its Taipei edition's.
                DataSourceCredit(
                    id: "slopNewYork",
                    title: "Slop New York",
                    detail: language.text(
                        "Its station shapes were the starting point for the elevated stations of the Tamsui-Xinyi Line, and the heights of the elevated roads follow its Taipei edition.",
                        "淡水信義線高架車站的外觀以它的車站造型為起點；高架道路的高度參考它的台北版。"
                    ),
                    notice: language.text(
                        "Copyright (c) 2026 Mr.doob, under the MIT License.",
                        "Copyright (c) 2026 Mr.doob，依 MIT 授權使用。"
                    ),
                    links: [DataSourceCredit.Link(title: "Slop New York", url: slopNewYorkURL)]
                ),
                // Decision 882: the letters of the platforms' name boards.
                DataSourceCredit(
                    id: "platformNameBoards",
                    title: "Noto Sans TC",
                    detail: language.text(
                        "The letters of the station names on the platforms' name boards in the 3D map.",
                        "3D 地圖月台站名牌上的站名字形。"
                    ),
                    notice: language.text(
                        "Noto Sans CJK, © Adobe (http://www.adobe.com/), with Reserved Font Name 'Source', under the SIL Open Font License 1.1, which comes with the app.",
                        "Noto Sans CJK，© Adobe（http://www.adobe.com/），保留字型名稱「Source」，依 SIL Open Font License 1.1 使用，授權條款隨 App 提供。"
                    ),
                    links: [
                        DataSourceCredit.Link(title: "Noto Sans CJK", url: notoSansURL),
                        DataSourceCredit.Link(title: language.text("Noto Sans licence", "Noto Sans 授權條款"), url: notoSansLicenseURL),
                    ]
                ),
            ]
        )
    }
}
