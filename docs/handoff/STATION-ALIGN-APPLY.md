# STATION-ALIGN-APPLY（車站規則 (c)：月台對準 OSM、台南站房、站房底下的 Overture）

## 進度

- 做到哪：決策 1022 的四件做完（月台沿線對準、20 m 常駐測試、台南 1936 年站房、外觀研究底下不畫底圖建物的測試）。
- 已驗證：Linux Swift 6.4 `swift build --build-tests -Xswiftc -warnings-as-errors`；`RealPlatformEndsTests`、
  `Map3DStationExteriorFootprintsTests`、`StationAlignmentReportTests/testPlatformsLieAlongTheRealOnes` 與收購、共站、
  重買、海外地圖的測試（PR 說明列了哪些）。
- 下一步的第一個指令：`STATION_ALIGN_REPORT=/tmp/now.tsv swift test --skip-build --filter StationAlignmentReportTests/testReport`
  （約 7 分），和 `tools/station-alignment/REPORT-2026-11-27-AFTER.tsv` 比。

## 重新產生 `real_platforms.json`

`STATION_ALIGN_REPORT=/tmp/r.tsv STATION_ALIGN_PLATFORMS=/tmp/real_platforms.json swift test --skip-build --filter StationAlignmentReportTests/testReport`，
再複製到 `RailwayGameApp/Resources/RealRailways/real_platforms.json`。配對是拿遊戲月台去找最近的 OSM 月台組，所以這次的檔是用
**改之前**的鋪法量的（230 站）；用改之後的鋪法重量會配到 226 站（月台移了以後，幾站的最近一組變了）。OSM 資料更新時：先照
`tools/station-alignment/README.md` 重抽 `data/*.json`，暫時把 `RealPlatformEnds` 的檔拿掉（`platformEnds` 為 nil 就照舊鋪）
再量，量出來的才是對舊鋪法的配對。

## 留給之後的

1. **壓軌的站房**（1021 §3 的 3）：新烏日 418 m、高雄地標 656、花蓮 490、新左營 342、台北地標 320…（表的 `buildings_on_track`），
   在 3D 看是否真的撞，撞的切開或抬高。
2. **真實足跡當站房**（車站規則第 4 條的第三順位）：另一大塊，可以再拆一張。
3. **例外的站**（`StationAlignmentReportTests.offTheRealPlatforms` 與決策 1022 §1）：南港、台北、高鐵桃園／台南／苗栗、
   十四張、香港茘景／奧運／東涌、羅瓦涅米、兩個博多。配到的是別條線的月台：要分出每條線自己的月台組（OSM 的 `ref`、
   `railway:track_ref`，或照遊戲月台的股數挑），才能對準。
4. 高鐵、機捷、海外三張地圖不在常駐測試裡（5 分）；改鋪法時跑一次完整報告。九州新幹線熊本仍差 100 m：端點站，往前移
   待避線會伸出延伸段，要把熊本以南的延伸加長（或等「熊本→新水俣」延伸段上架）才對得上。
5. **舊版站房導入**（決策 1022 §1 (5)，assets-2 `docs/planning/OLD-3D-COMPAT.md`）：18 棟純站房（方法 A）排在真實足跡之後、
   站型套件之前，`scale = 0.5`，左側月台轉 180°，島式 11 m 不變；方法 B 固定股道模組導入時再處理。先讀 Mac 的
   `~/AlongTheLine-Studio/reports/agy-audit/station_audit/STATION_IMPORT_GUIDE.md` 與 `station_kit_spec.json`（這個工作串讀不到）。
   月台高度 1.08～1.15 m、月台緣 1.55～1.76 m、跨站淨空 ≥ 6.50 m 由 `RealPlatformEndsTests.testTheOldVersionsPlatformMeasuresHold` 守著。

## 要注意

- `real_platforms.json` 的 key：線是 `<RealBranchLine.id>|<站名>`，單買的站是 `<系統>|<站名>`（`RealPlatformEnds.key`）。
- 鋪線移了月台後鋪不上，`laidOffer` 會整條照舊再鋪一次；單買的站先試一半。這兩個後備讓「原本買得到的都還買得到」。
- Overture 每月換新是另一張（決策 1026，`taiwan_buildings.pmtiles`）；站房底下的移除照位置，換新後不用改程式。
