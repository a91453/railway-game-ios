# 台鐵與捷運營運資料移植研究

- 查閱日期：2026-10-05
- railway-game-ios (main)：`d2de3d5f814af3a3ecc6d6cf33e7b334226acfaf`
- railway-reference-private：`2db0c5a6963798e6b86723bb001189343a59940c`

## `tra_station_class.json`
- **檔案大小**：3847 bytes
- **最上層欄位**：`基隆, 三坑, 八堵, 百福, 五堵, 汐止, 汐科, 南港, 松山, 臺北, 萬華, 板橋, 浮洲, 樹林, 南樹林, 山佳, 鶯歌, 鳳鳴, 桃園, 內壢, ... (共 210 個)`
- **來源與授權**：無標示
- **筆數**：210
- **每筆資料的欄位與型別**：
  - `基隆` (Value): `str`
- **資料範例**：
  ```json
  {
    "基隆": "一等"
  }
  ```

## `tra_station_info.json`
- **檔案大小**：36116 bytes
- **最上層欄位**：`基隆, 三坑, 八堵, 七堵, 百福, 五堵, 汐止, 汐科, 南港, 松山, 台北, 台北-環島, 萬華, 板橋, 浮洲, 樹林, 南樹林, 山佳, 鶯歌, 鳳鳴, ... (共 246 個)`
- **來源與授權**：無標示
- **筆數**：246
- **每筆資料的欄位與型別**：
  - `name`: `str`
  - `id`: `str`
  - `address`: `str`
  - `lat`: `float`
  - `lon`: `float`
  - `feature`: `str`
- **資料範例**：
  ```json
  {
    "基隆": {
  "name": "基隆",
  "id": "0900",
  "address": "203001基隆市中山區中山一路 16 之 1 號",
  "lat": 25.13191,
  "lon": 121.73837,
  "feature": ""
}
  }
  ```

## `tra_platforms.json`
- **檔案大小**：13494 bytes
- **最上層欄位**：`source, license, note, built_at, bbox, filters, maxSegmentDevM, estLenByTier, stations, derived`
- **來源與授權**：
  - source: OpenStreetMap contributors — way[railway=platform／public_transport=platform／railway=platform_edge] 與 node[stop_position／railway=stop]，經 Overpass API 取得
  - license: ODbL 1.0（https://www.openstreetmap.org/copyright）
- **說明**：`stations`（197 站）與 `derived`（42 站）都是「站名 → [[lat, lon], [lat, lon]]」月台兩端座標；`estLenByTier` 是 5 個數字的陣列。
- **資料範例 (stations 內一筆)**：
  ```json
  {
    "基隆": [[25.13194, 121.73841], [25.13366, 121.73975]]
  }
  ```

## `tra_track_sections.json`
- **檔案大小**：41157 bytes
- **最上層欄位**：`version, source_notes, pairs`
- **來源與授權**：
  - source_notes: 本站自算，無外部上游：由 rail-3d/physical/network.json（OSM 股道幾何）與 rail-3d/physical/dispatch.json（各站對實際派過的路徑）算出相鄰兩站之間有平行正線股道的長度佔比，≥0.5 判雙線（tracks=2）否則單線（tracks=1）。南迴線／臺東線同名隧道 way 是否為第二股，2026-09-14 已用交通部 TDX GIS 圖資 v3「軌道路網實體路線」（逐股道官方幾何，政府資料開放授權條款-1.0）逐對核實：核實過的算平行股道，未核實／經核實只有一股的仍不算。核實證據 scripts/fixtures/tra-parallel-verified-tdx-0914.json（產生器 scripts/build_tdx_parallel_evidence.mjs）；TDX 與台鐵官方《路線修築沿革》衝突時以沿革為準（南迴線無添築雙線紀錄 ⇒ 不算；山里─臺東 2013 添築雙線 ⇒ 算）。maxPathM＝該站對派過的實體股道路徑中最長者（公尺，進位到公釐再加 1 公釐），index.html 建跑段剖面時站間長度取它與示意線形長的較大者，畫在任一條實體股道或示意線形上的點速才不會超過剖面速度（＝不超過車種極速）。鍵＝兩站名正規化成班表用字「臺」後排序、以 | 相接（讀表端 index.html 用班表站名查）。via＝班表（data/tra_schedule_dense.json）排在站對中間、派車表沒有的站，其座標投影到該站對每條派過路徑上離鍵的第一站、第二站各最遠多少公尺（進位規則同 maxPathM），index.html 當停在那一站的前後兩截剖面長下限。產生器 scripts/build_tra_track_sections.mjs。
- **筆數**：`pairs` 是 243 個站對（tracks=2 有 181 個、tracks=1 有 62 個）
- **每筆資料的欄位**：`tracks`, `parallelFrac`, `lengthM`, `maxPathM`, `refs`, `via`, `override`
- **資料範例**：
  ```json
  {
    "七堵|八堵": {"tracks": 2, "parallelFrac": 0.995, "lengthM": 2398, "maxPathM": 2411.357, "refs": ["宜蘭線", "縱貫線"]}
  }
  ```

## `trtc_codes.json`
- **檔案大小**：6960 bytes
- **最上層欄位**：`BL01, BL02, BL03, BL04, BL05, BL06, BL07, BL08, BL09, BL10, BL11, BL12, BL13, BL14, BL15, BL16, BL17, BL18, BL19, BL20, ... (共 122 個)`
- **來源與授權**：無標示
- **筆數**：122
- **每筆資料的欄位與型別**：
  - `name`: `str`
  - `on`: `list`
- **資料範例**：
  ```json
  {
    "BL01": {"name": "頂埔", "on": [{"ln": "BL", "i": 0}]}
  }
  ```

## `tra.json`
- **檔案大小**：266326 bytes
- **最上層欄位**：`system, source_notes, lines, shape_source`
- **來源與授權**：
  - source_notes: Overpass 節點來源：https://maps.mail.ru/osm/tools/overpass/api/interpreter（node railway~station|halt, operator~台鐵/臺灣鐵路/Taiwan Railway，bbox=21.9,120.0,25.3,122.0），共取得 245 個車站節點。 註：overpass-api.de 與 lz4.overpass-api.de 對含中文字查詢在本次執行環境一律回 HTTP 406，改用備援鏡像清單依序重試取得。 OSM 並無以「縱貫線/山線/海線/屏東線/南迴線/臺東線/北迴線/宜蘭線」命名、涵蓋整段的 route=train relation（該 tag 對應的是個別車次如「自強108」），故 9 段路線站序改採台鐵官方公開站序（本腳本 LINE_DEFS 手工列出）比對站名取得座標，座標本身全部即時查自 OSM。 班距（headwaySec）為粗估值，headway_estimated=true。 2026-07-11:補入班表有停靠但站列缺漏的9個營運中車站(百福/南樹林/暖暖/精武/仁德/內惟/美術館/鼓山/三塊厝),座標取自TDX車站資料。 2026-07-11:山線補登成功站(原僅在成追線,缺山線邊致成追線跨線班次繞行追分/彰化回頭路)。 2026-07-11:臺東線玉里–三民段以TDX TT線形替換(OSM曾routed樂合/安通舊線,偏達0.8km)。 2026-10-02:縱貫線北段補入平鎮臨時站(中壢–埔心間,2026-10-03啟用,ODS逐日時刻表10/3起停站碼1105);TDX與ODS車站清單尚未上架,座標取data/tra_station_info.json的先行紀錄(provisional,非官方值,來由見scripts/fetch_tra_station_info.mjs),d為投影到本線shape的里程。
- **筆數**：16
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `headway_estimated`: `bool`
  - `stations`: `list`
  - `shape`: `list`
  - `shapeLen`: `float`
- **資料範例**：
  ```json
{
  "id": "縱貫線北段",
  "name": "縱貫線北段（基隆–竹南）",
  "color": "#2E6FB0",
  "peakHeadwaySec": 600,
  "offpeakHeadwaySec": 1200,
  "headway_estimated": true,
  "stations": [
    {
      "name": "基隆",
      "lat": 25.1330324,
      "lon": 121.7392299,
      "d": 0.08681449584462424
    },
    {
      "name": "三坑",
      "lat": 25.1222174,
      "lon": 121.7420983,
      "d": 1.5022487144504275
    },
    {
      "name": "八堵",
      "lat": 25.1084954,
      "lon": 121.7290072,
      "d": 3.823717919230238
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "shapeLen": 125.5676
}
  ```

## `trtc.json`
- **檔案大小**：110559 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 信義東延段廣慈/奉天宮站(R01):車站座標取 TDX 官方值(2026-09-10 上架後換掉先行補入的 OSM 值);線形取自 OSM(TDX 的 R 線幾何仍無東延段);沿線里程指 OSM 月台停車點;站間行駛時間仍為估算(TDX 尚未提供 R01 區間),上架後應以官方值取代;交通部 TDX 運輸資料流通服務(台北捷運路線幾何/站序/班距/站間行駛時間,2026-07 抓取);環狀線為 OSM 幾何+官網公告班距估算;環狀線站間行駛時間補用臺北捷運公司「相鄰兩站間之行駛時間及停靠站時間」(生效 2025-06-03);環狀線站間行駛時間補用臺北捷運公司「相鄰兩站間之行駛時間及停靠站時間」(生效 2025-06-03);環狀線停靠站時間補自臺北捷運公司「相鄰兩站間之行駛時間及停靠站時間」(生效 2025-06-03)
- **筆數**：9
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
  - `dwellSec`: `list`
- **資料範例**：
  ```json
{
  "id": "BR",
  "name": "文湖線",
  "color": "#C48C31",
  "peakHeadwaySec": 120,
  "offpeakHeadwaySec": 420,
  "stations": [
    {
      "name": "動物園",
      "lat": 24.998205,
      "lon": 121.579501,
      "d": 0
    },
    {
      "name": "木柵",
      "lat": 24.99824,
      "lon": 121.573127,
      "d": 0.6706,
      "dwell": 25
    },
    {
      "name": "萬芳社區",
      "lat": 24.99857,
      "lon": 121.568088,
      "d": 1.184,
      "dwell": 25
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": 67
    },
    {
      "run": 47
    },
    {
      "run": 99
    },
    "..."
  ],
  "dwellSec": [
    0,
    25,
    25,
    "..."
  ]
}
  ```

## `krtc.json`
- **檔案大小**：44545 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務(高雄捷運紅/橘線與高雄輕軌:路線幾何/站序/站間行駛時間,2026-07 抓取);輕軌班距為官方公告估算(尖峰約10分/離峰約15分)
- **筆數**：3
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
- **資料範例**：
  ```json
{
  "id": "KR",
  "name": "紅線",
  "color": "#E4002B",
  "peakHeadwaySec": 240,
  "offpeakHeadwaySec": 420,
  "stations": [
    {
      "name": "小港",
      "lat": 22.56478,
      "lon": 120.353808,
      "d": 0,
      "dwell": 300
    },
    {
      "name": "高雄國際機場",
      "lat": 22.570166,
      "lon": 120.341772,
      "d": 1.4751,
      "dwell": 20
    },
    {
      "name": "草衙",
      "lat": 22.580354,
      "lon": 120.328569,
      "d": 3.379,
      "dwell": 25
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": 120
    },
    {
      "run": 180
    },
    {
      "run": 180
    },
    "..."
  ]
}
  ```

## `tymc.json`
- **檔案大小**：37399 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務(桃園機場捷運:路線幾何/站序/班距/站間行駛時間,2026-07 抓取);以普通車全站停靠型態繪製 2026-07-11:移除新北產業園區站西側shape反向重走段(同軌去回偽折返,致列車視覺繞圈);車站d重投影。
- **筆數**：1
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
- **資料範例**：
  ```json
{
  "id": "A",
  "name": "機場捷運",
  "color": "#8246AF",
  "peakHeadwaySec": 900,
  "offpeakHeadwaySec": 900,
  "stations": [
    {
      "name": "台北車站",
      "lat": 25.04869,
      "lon": 121.51428,
      "d": 0
    },
    {
      "name": "三重站",
      "lat": 25.0548,
      "lon": 121.48273,
      "d": 4.1692
    },
    {
      "name": "新北產業園區站",
      "lat": 25.06171,
      "lon": 121.45918,
      "d": 7.6192
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": 300
    },
    {
      "run": 180
    },
    {
      "run": 60
    },
    "..."
  ]
}
  ```

## `afr.json`
- **檔案大小**：157504 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務 v3/Rail/AFR/*(Station/Line/StationOfLine/Shape),2026-07 抓取。 v2 的 /v2/Rail/AFR/* 全部 404,僅 v3 有資料。 本線(LineID=1)官方 StationOfLine 列 17 站(嘉義…第二分道→二萬平→阿里山),但實際路線在二萬平之後必經神木站:本線 shape 的幾何終點就落在神木(離軌1.2m),阿里山站離本線 shape 有 503m、實際由神木線(LineID=3,神木→阿里山)銜接。故 stations 末站依幾何現實改列神木,並在班次 densify 的車站圖上斷開「二萬平↔阿里山」這條官方相鄰邊、改接神木——否則最短路徑會抄捷徑,車次5/8 少掉神木一站。 本線原始 WKT 為 22 個 MULTILINESTRING 碎片,其中 19 個碎片(共約4.6km)聚集在獨立山迴圈區,2D 投影下自我交叉形成多個分岔節點(螺旋繞山多圈、不同圈次在平面投影上座標重疊所致),無法用簡單首尾配對拼接;改用連通分量+Eulerian 最大覆蓋路徑,並以「接縫處方向連續」為擇優準則(真實軌道是平滑曲線,錯接必然出現銳角;單看端點距離無法分辨圈次)。驗證:螺旋區累積轉向 2.02 圈、銳角接縫 0 處(未套用此準則時為 0.02 圈、4 處銳角)。 TDX shape 的本線1處與祝山線4處跨分量缺口，改以 © OpenStreetMap 貢獻者（ODbL）active narrow_gauge 軌道補齊（2026-07-21擷取；共5段、ways 1429750186,1429734254,340254443,229516472,1137994868），不再以直線穿越山谷。 全部車站離軌距離均在150m內。
- **筆數**：12
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `stations`: `list`
  - `shape`: `list`
  - `shapeLen`: `float`
- **資料範例**：
  ```json
{
  "id": "AFR_MAIN",
  "name": "本線（嘉義－阿里山）",
  "color": "#B03A2E",
  "stations": [
    {
      "name": "嘉義",
      "lat": 23.479,
      "lon": 120.4412,
      "d": 0.0037
    },
    {
      "name": "北門",
      "lat": 23.488,
      "lon": 120.4542,
      "d": 1.6817
    },
    {
      "name": "鹿麻產",
      "lat": 23.5042,
      "lon": 120.5315,
      "d": 10.9063
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "shapeLen": 69.4759
}
  ```

## `tmrt.json`
- **檔案大小**：5881 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務(台中捷運綠線:路線幾何/站序/班距/站間行駛時間,2026-07 抓取)
- **筆數**：1
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
- **資料範例**：
  ```json
{
  "id": "TG",
  "name": "綠線",
  "color": "#79BB29",
  "peakHeadwaySec": 360,
  "offpeakHeadwaySec": 540,
  "stations": [
    {
      "name": "北屯總站",
      "lat": 24.18913,
      "lon": 120.70864,
      "d": 0
    },
    {
      "name": "舊社",
      "lat": 24.18228,
      "lon": 120.70729,
      "d": 0.977,
      "dwell": 25
    },
    {
      "name": "松竹",
      "lat": 24.1808,
      "lon": 120.70145,
      "d": 1.6594,
      "dwell": 30
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": 124
    },
    {
      "run": 80
    },
    {
      "run": 160
    },
    "..."
  ]
}
  ```

## `ntdlrt.json`
- **檔案大小**：11635 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務(淡海輕軌:路線幾何/站序,2026-07 抓取);班距為官方公告估算(尖峰約10分/離峰約15分),TDX 無班距/站間時間檔
- **筆數**：2
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
  - `headway_estimated`: `bool`
- **資料範例**：
  ```json
{
  "id": "V",
  "name": "綠山線",
  "color": "#FF2A00",
  "peakHeadwaySec": 600,
  "offpeakHeadwaySec": 900,
  "stations": [
    {
      "name": "紅樹林",
      "lat": 25.155597,
      "lon": 121.458851,
      "d": 0
    },
    {
      "name": "竿蓁林",
      "lat": 25.162415,
      "lon": 121.456232,
      "d": 0.8192
    },
    {
      "name": "淡金鄧公",
      "lat": 25.169363,
      "lon": 121.460813,
      "d": 1.7529
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": null
    },
    {
      "run": null
    },
    {
      "run": null
    },
    "..."
  ],
  "headway_estimated": true
}
  ```

## `ntalrt.json`
- **檔案大小**：8569 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 交通部 TDX 運輸資料流通服務(安坑輕軌:路線幾何/站序,2026-07 抓取);班距為官方公告估算(尖峰約12分/離峰約15分),TDX 無班距/站間時間檔
- **筆數**：1
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
  - `headway_estimated`: `bool`
- **資料範例**：
  ```json
{
  "id": "K",
  "name": "安坑輕軌",
  "color": "#9E925E",
  "peakHeadwaySec": 720,
  "offpeakHeadwaySec": 900,
  "stations": [
    {
      "name": "雙城",
      "lat": 24.946321,
      "lon": 121.489645,
      "d": 0
    },
    {
      "name": "玫瑰中國城",
      "lat": 24.95076,
      "lon": 121.493861,
      "d": 0.6521
    },
    {
      "name": "台北小城",
      "lat": 24.95369,
      "lon": 121.49937,
      "d": 1.3057
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": null
    },
    {
      "run": null
    },
    {
      "run": null
    },
    "..."
  ],
  "headway_estimated": true
}
  ```

## `sanying.json`
- **檔案大小**：18515 bytes
- **最上層欄位**：`system, source_notes, lines`
- **來源與授權**：
  - source_notes: 路線幾何:交通部 TDX 運輸資料流通服務(新北捷運三鶯線,2026-09-27 抓取);車站座標:OpenStreetMap 貢獻者(ODbL,2026-07 擷取);站序站名:新北捷運公司官網;站間行駛時間:交通部 TDX 運輸資料流通服務(新北捷運三鶯線,2026-09-12 抓取);班距為試營運公告估算(尖峰6分/離峰8分)
- **筆數**：1
- **每筆資料的欄位與型別**：
  - `id`: `str`
  - `name`: `str`
  - `color`: `str`
  - `peakHeadwaySec`: `int`
  - `offpeakHeadwaySec`: `int`
  - `stations`: `list`
  - `shape`: `list`
  - `segs`: `list`
  - `headway_estimated`: `bool`
- **資料範例**：
  ```json
{
  "id": "LB",
  "name": "三鶯線",
  "color": "#79BCE8",
  "peakHeadwaySec": 360,
  "offpeakHeadwaySec": 480,
  "stations": [
    {
      "name": "頂埔",
      "lat": 24.9595906,
      "lon": 121.4193677,
      "d": 0,
      "dwell": 25
    },
    {
      "name": "媽祖田",
      "lat": 24.9534443,
      "lon": 121.4120896,
      "d": 1.0186,
      "dwell": 25
    },
    {
      "name": "長壽山",
      "lat": 24.9441968,
      "lon": 121.4025763,
      "d": 2.465,
      "dwell": 25
    },
    "..."
  ],
  "shape": "[... shape coordinates omitted ...]",
  "segs": [
    {
      "run": 99
    },
    {
      "run": 120
    },
    {
      "run": 112
    },
    "..."
  ],
  "headway_estimated": true
}
  ```

## 站名比對
### `tra_station_class.json` 比對結果
- **對得上的數量**：209
- **App 有但資料沒有的站名 (33站)**：上員, 九讚頭, 內灣, 八斗子, 六家, 十分, 千甲, 合興, 埔心, 大華, 富貴, 嶺腳, 左營(舊城), 平溪, 平鎮, 成功, 新莊, 望古, 林榮新光, 榮華, 橫山, 水里, 沙崙, 海科館, 源泉, 濁水, 竹中, 竹東, 菁桐, 車埕, 長榮大學, 集集, 龍泉
- **資料有但 App 沒有的站名 (1站)**：左營

### `tra_station_info.json` 比對結果
- **對得上的數量**：240
- **App 有但資料沒有的站名 (2站)**：左營(舊城), 新城 (太魯閣)
- **資料有但 App 沒有的站名 (6站)**：南方小站, 台北-環島, 左營, 新城, 樹林調車場, 潮州基地

## 各系統營運資料
### TRA
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| 縱貫線北段 | 縱貫線北段（基隆–竹南） | 37 | 600 | 1200 | 無 | 無 | 無 | 可以 |
| 山線 | 山線（竹南–彰化） | 23 | 720 | 1200 | 無 | 無 | 無 | 可以 |
| 海線 | 海線（竹南–彰化） | 18 | 900 | 1500 | 無 | 無 | 無 | 可以 |
| 縱貫線南段 | 縱貫線南段（彰化–高雄） | 46 | 600 | 1200 | 無 | 無 | 無 | 可以 |
| 屏東線 | 屏東線（高雄–枋寮） | 21 | 720 | 1200 | 無 | 無 | 無 | 可以 |
| 南迴線 | 南迴線（枋寮–臺東） | 12 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| 臺東線 | 臺東線（臺東–花蓮） | 27 | 900 | 1500 | 無 | 無 | 無 | 可以 |
| 北迴線 | 北迴線（花蓮–蘇澳新） | 13 | 900 | 1500 | 無 | 無 | 無 | 可以 |
| 宜蘭線 | 宜蘭線（蘇澳–八堵） | 27 | 720 | 1200 | 無 | 無 | 無 | 可以 |
| NEIWAN | 內灣線（新竹–內灣） | 13 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| LIUJIA | 六家線（竹中–六家） | 2 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| PINGXI | 平溪線（三貂嶺–菁桐） | 7 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| SHENAO | 深澳線（瑞芳–八斗子） | 3 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| JIJI | 集集線（二水–車埕） | 7 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| SHALUN | 沙崙線（中洲–沙崙） | 3 | 1800 | 3600 | 無 | 無 | 無 | 可以 |
| chengzhui | 成追線（追分–成功） | 2 | - | - | 無 | 無 | 無 | 可以 |

### TRTC
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| BR | 文湖線 | 24 | 120 | 420 | 有 | 有 | 有 | 可以 |
| R | 淡水信義線 | 28 | 360 | 540 | 有 | 有 | 有 | 可以 |
| R_XBT | 新北投支線 | 2 | 420 | 600 | 無 | 有 | 有 | 可以 |
| G | 松山新店線 | 19 | 240 | 420 | 有 | 有 | 有 | 可以 |
| G_XBT | 小碧潭支線 | 2 | 720 | 960 | 無 | 有 | 有 | 可以 |
| O_XINZHUANG | 中和新蘆線（迴龍） | 21 | 360 | 600 | 有 | 有 | 有 | 可以 |
| O_LUZHOU | 中和新蘆線（蘆洲） | 17 | 360 | 600 | 有 | 有 | 有 | 可以 |
| BL | 板南線 | 23 | 360 | 540 | 有 | 有 | 有 | 可以 |
| Y | 環狀線 | 14 | 290 | 450 | 有 | 有 | 有 | 可以 |

### KRTC
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| KR | 紅線 | 25 | 240 | 420 | 無 | 有 | 有 | 可以 |
| KO | 橘線 | 14 | 240 | 420 | 無 | 有 | 有 | 可以 |
| C | 環狀輕軌 | 38 | 600 | 900 | 無 | 有 | 有 | 可以 |

### TYMC
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| A | 機場捷運 | 22 | 900 | 900 | 無 | 無 | 有 | 可以 |

### AFR
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| AFR_MAIN | 本線（嘉義－阿里山） | 17 | - | - | 無 | 無 | 無 | 可以 |
| AFR_ZHUSHAN | 祝山線 | 3 | - | - | 無 | 無 | 無 | 可以 |
| AFR_SHENMU | 神木線 | 2 | - | - | 無 | 無 | 無 | 可以 |
| AFR_ZHAOPING | 沼平線 | 2 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_阿里山 | 阿里山站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_神木 | 神木站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_神木_2 | 神木站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_祝山 | 祝山站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_第一分道 | 第一分道站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_第一分道_2 | 第一分道站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_第二分道 | 第二分道站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |
| AFR_YARD_第二分道_2 | 第二分道站股道 | 0 | - | - | 無 | 無 | 無 | 可以 |

### TMRT
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| TG | 綠線 | 18 | 360 | 540 | 無 | 有 | 有 | 可以 |

### NTDLRT
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| V | 綠山線 | 11 | 600 | 900 | 無 | 無 | 無 | 可以 |
| VB | 藍海線 | 12 | 600 | 900 | 無 | 無 | 無 | 可以 |

### NTALRT
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| K | 安坑輕軌 | 9 | 720 | 900 | 無 | 無 | 無 | 可以 |

### SANYING
| id | name | 站數 | peakHeadwaySec | offpeakHeadwaySec | dwellSec 陣列 | 站上有 dwell | segs 有 run | 對應 track_lines.geojson |
|---|---|---|---|---|---|---|---|---|
| LB | 三鶯線 | 12 | 360 | 480 | 無 | 有 | 有 | 可以 |

## 之後移植要注意的事
- 有 33 個 App 內的台鐵站名，在 `tra_station_class.json` 找不到等級資料（上員, 九讚頭, 內灣, 八斗子, 六家, 十分, 千甲, 合興, 埔心, 大華, 富貴, 嶺腳, 左營(舊城), 平溪, 平鎮, 成功, 新莊, 望古, 林榮新光, 榮華, 橫山, 水里, 沙崙, 海科館, 源泉, 濁水, 竹中, 竹東, 菁桐, 車埕, 長榮大學, 集集, 龍泉）。
- 有部分台鐵站名與資料庫對不上：App 端的 `左營(舊城)` 在資料庫對應為 `左營`；App 端的 `新城(太魯閣)` 在資料庫對應為 `新城`。
- 以下路線完全沒有停站時間資料（既無 dwellSec 陣列也無各站 dwell）：TRA 的 `縱貫線北段`, TRA 的 `山線`, TRA 的 `海線`, TRA 的 `縱貫線南段`, TRA 的 `屏東線`, TRA 的 `南迴線`, TRA 的 `臺東線`, TRA 的 `北迴線`, TRA 的 `宜蘭線`, TRA 的 `NEIWAN`, TRA 的 `LIUJIA`, TRA 的 `PINGXI`, TRA 的 `SHENAO`, TRA 的 `JIJI`, TRA 的 `SHALUN`, TRA 的 `chengzhui`, TYMC 的 `A`, AFR 的 `AFR_MAIN`, AFR 的 `AFR_ZHUSHAN`, AFR 的 `AFR_SHENMU`, AFR 的 `AFR_ZHAOPING`, AFR 的 `AFR_YARD_阿里山`, AFR 的 `AFR_YARD_神木`, AFR 的 `AFR_YARD_神木_2`, AFR 的 `AFR_YARD_祝山`, AFR 的 `AFR_YARD_第一分道`, AFR 的 `AFR_YARD_第一分道_2`, AFR 的 `AFR_YARD_第二分道`, AFR 的 `AFR_YARD_第二分道_2`, NTDLRT 的 `V`, NTDLRT 的 `VB`, NTALRT 的 `K`。
- 以下路線沒有站間行駛秒數資料（segs 無 run 欄位）：TRA 的 `縱貫線北段`, TRA 的 `山線`, TRA 的 `海線`, TRA 的 `縱貫線南段`, TRA 的 `屏東線`, TRA 的 `南迴線`, TRA 的 `臺東線`, TRA 的 `北迴線`, TRA 的 `宜蘭線`, TRA 的 `NEIWAN`, TRA 的 `LIUJIA`, TRA 的 `PINGXI`, TRA 的 `SHENAO`, TRA 的 `JIJI`, TRA 的 `SHALUN`, TRA 的 `chengzhui`, AFR 的 `AFR_MAIN`, AFR 的 `AFR_ZHUSHAN`, AFR 的 `AFR_SHENMU`, AFR 的 `AFR_ZHAOPING`, AFR 的 `AFR_YARD_阿里山`, AFR 的 `AFR_YARD_神木`, AFR 的 `AFR_YARD_神木_2`, AFR 的 `AFR_YARD_祝山`, AFR 的 `AFR_YARD_第一分道`, AFR 的 `AFR_YARD_第一分道_2`, AFR 的 `AFR_YARD_第二分道`, AFR 的 `AFR_YARD_第二分道_2`, NTDLRT 的 `V`, NTDLRT 的 `VB`, NTALRT 的 `K`。
- 以下路線班距為估算值（headway_estimated）：TRA 的 `縱貫線北段`, TRA 的 `山線`, TRA 的 `海線`, TRA 的 `縱貫線南段`, TRA 的 `屏東線`, TRA 的 `南迴線`, TRA 的 `臺東線`, TRA 的 `北迴線`, TRA 的 `宜蘭線`, TRA 的 `NEIWAN`, TRA 的 `LIUJIA`, TRA 的 `PINGXI`, TRA 的 `SHENAO`, TRA 的 `JIJI`, TRA 的 `SHALUN`, TRTC 的 `Y`, KRTC 的 `C`, NTDLRT 的 `V`, NTDLRT 的 `VB`, NTALRT 的 `K`, SANYING 的 `LB`。
- 成追線與林鐵等路線沒有班距資料：TRA 的 `chengzhui`, AFR 的 `AFR_MAIN`, AFR 的 `AFR_ZHUSHAN`, AFR 的 `AFR_SHENMU`, AFR 的 `AFR_ZHAOPING`, AFR 的 `AFR_YARD_阿里山`, AFR 的 `AFR_YARD_神木`, AFR 的 `AFR_YARD_神木_2`, AFR 的 `AFR_YARD_祝山`, AFR 的 `AFR_YARD_第一分道`, AFR 的 `AFR_YARD_第一分道_2`, AFR 的 `AFR_YARD_第二分道`, AFR 的 `AFR_YARD_第二分道_2`。
