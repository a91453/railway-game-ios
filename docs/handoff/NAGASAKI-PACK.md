# NAGASAKI-PACK 交接（決策 997 長崎縣、決策 998 西九州新幹線）

## 進度

- 做到哪：PR 1 的程式、測試和 997 草稿已經推上分支（WIP commit，還沒開 PR）。地面和四包還沒重做；PR 2 是共用資料夾 `nagasaki-pack/pr2-nishi-kyushu-wk-nk.patch`。
- 已驗證：沒有。這兩張 PR 的 Swift 測試都還沒跑過；重合 KS 會得到一模一樣的地圖包，這點核對過。
- 下一步的第一個指令：`osmium extract -b 129.30,32.05,131.37,34.07 kyushu.pbf -o /tmp/fk/osm/four.pbf`，接著抓標高（下面「PR 1 的狀態」）。

2026-11-26（台灣時間 08:40），雲端 session，分支 `claude/project-thread-dzwmgt`。上一串對話被壓縮兩次，照規則停手。
作者：「那還要補長崎縣嗎 這樣西九州新幹線就能用了」；後來又說「對了西九州我舊版有做塗裝」「直接用n700s套上塗裝就行了吧」。

兩張 PR，照順序做（分支只有一條，PR 2 要等 PR 1 合併後從 main 重開同名分支）：

1. **PR 1、決策 997**：日本地圖西緣移到 W 129.34，長崎縣成為第四個包 `fukuoka-nagasaki`。這張 PR 也加長崎開局點、長崎與壹岐機場、jp68–jp88 的 21 個景點。
2. **PR 2、決策 998**：西九州新幹線（武雄溫泉—長崎，`kyushushinkansen:NK`）可以單獨買，車是 6 輛 N700S，一天 42 班。

存檔版本、golden schema、GameCore 都不動。

## PR 1 的狀態

這個分支上的 WIP commit 有：

- 程式和測試：`MapPackDownloads`、`AttractionCatalog`、`AirportCatalog`、`DataSourceCredits`、`MapGrowthLayoutTests`、`OverseasSightsTests`、`MapPackDownloadsTests`、`FukuokaRailwaysTests`。
- 工具：`build_fukuoka_rail.py` 的 `EXTENT`、`STARTS`、`OLDER`；`build_fukuoka_ground.py` 的 `BOX`；`split_prefectures.py` 的 `PARTS`；README。
- 新的 `RailwayGameApp/AssetPacks/fukuoka-nagasaki.json`。
- WhatsNew 檔。
- `docs/decisions/997.md` 的草稿，§3 和 §4 的數字還是 TODO。

**還沒做的是地面，地圖包也還沒重切**：`MapPacks/` 和 `fukuoka_buildings.json`、`fukuoka_sources.json` 都還是 main 上的樣子，所以這個 WIP 的 CI 會紅（範圍 129.34 對不上）。接手的串照下面做：

```sh
# 1. OSM：osmtoday 的 Kyushu 抽取，範圍多切 0.04°
osmium extract -b 129.30,32.05,131.37,34.07 kyushu.pbf -o /tmp/fk/osm/four.pbf
osmium tags-filter -o /tmp/fk/osm/admin4.pbf kyushu.pbf r/admin_level=4
# 2. 國土地理院標高：5 m 39,376 片、10 m 10,044 片（約 1 小時；可以開第二個程序倒著抓）
python3 -I tools/fukuoka-map/fetch_gsi_dem.py /tmp/fk/gsi
# 3. 地面：其餘命令照 tools/fukuoka-map/README.md（全部改用 four.pbf）
#    依序 basemap、buildings、population、airfields、no_build、grids
# 4. 照縣界切成四包
python3 -I tools/fukuoka-map/split_prefectures.py /tmp/fk/osm/admin4.pbf RailwayGameApp/Resources/MapPacks
```

上一串在 container 裡已經重做好 basemap（整張 69.0 MB）、buildings、population，但 container 會被收回，所以沒有推。接手的串要重做。

做完以後：

- 填 997 §3 的各包大小，和 §4 的高度範圍、陸地、水、陡坡。
- 更新 `FukuokaGroundTests` 的數字，`BaseMapStyleTests` 和 `MapPackExtentsTests` 有用到包數的話也要改。
- 跑測試：`swift test --skip-build --filter 'MapGrowthLayoutTests|FukuokaRailwaysTests|OverseasSightsTests|MapPackDownloadsTests|FukuokaGroundTests'`。
- 告訴作者：`mappack-fukuoka-nagasaki` 是新的 asset pack，第一次上傳要審核。四包的圖磚都重切過，四包都要上傳。

## PR 2 的狀態

整份 diff 在共用資料夾 `nagasaki-pack/pr2-nishi-kyushu-wk-nk.patch`，是從 main 4d437f1 做的，PR 1 的程式也一起包在裡面。PR 1 合了以後在新分支 `git apply` 它，PR 1 那幾個檔會衝突，留 main 的版本就好。

已經寫好、合進地圖包的：

- `build_nishi_kyushu_shinkansen.py` 和它的產出 `tools/fukuoka-map/nishi-kyushu-shinkansen/`。
- `build_kyushu_shinkansen.py merge` 改成看線（`LINE_ORDER = ("KS","NK")`）。重合 KS 會得到一模一樣的地圖包。
- `build_fukuoka_rail.refresh_manifest`：有分包時不會把 parts 洗掉。

遊戲端：

- `DemoRealLines.cars(ofLine:system:)`：NK 是 6 輛。
- `Map3DRealTrains`：NK 用 `Map3DN700S`，6 輛。
- `OverseasMaps`：線色 `0xA6192E`、名稱。
- `RealLineAcquisition`：長崎是島式 2 面 4 線，武雄溫泉 2 線。

測試：新的 `NishiKyushuShinkansenTests`；`KyushuShinkansenTests`、`FukuokaRailwaysTests`、`TimetableCheckupAllBoughtTests.testNishiKyushuShinkansen` 也改了。

**這些測試都還沒跑過**，上一串停手時建置做到 114/161。下面三個斷言是推測的，要先驗證：

- 時刻表的 `runs.tracks` 有沒有照 `realTracks`。
- 月台長度是不是 150 m。
- 武雄溫泉是不是兩個側式月台。

接下來要做的：

1. 建置，跑 `NishiKyushuShinkansenTests`、`KyushuShinkansenTests`。
2. 兩種規則都跑 NK 的體檢：`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY="fukuoka kyushushinkansen:NK simple"`，`simple` 再換成另一種規則跑一次。
3. 把預算加到 `CheckupBudgets/Fukuoka.swift`。
4. 架空線照 #2703 核對。
5. 寫 `docs/decisions/998.md`，加 WhatsNew 檔。
6. 開 draft PR。

機廠先不蓋，三組車晚上都停在長崎。大村車輛基地（線中間）要不要蓋，先讀 `depot-work` skill 再決定。

## 之後

- かもめ塗裝：等 #2711 N700S 合併後，在 N700S 上套舊版的西九州塗裝（作者說「直接用n700s套上塗裝就行了吧」）。
- 特急リレーかもめ和武雄溫泉的對面轉乘：另開一張。
- 開局畫面的選項：決策 991 交接的下一張 PR，接在 #2704 後面。
- 研究筆記：共用資料夾 `nagasaki-pack/west-kyushu-research.md`。
