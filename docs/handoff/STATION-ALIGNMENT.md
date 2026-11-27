# STATION-ALIGNMENT（車站規則 (b) 量測表；(c) 交給下一個工作串）

## 進度

- 做到哪：(b) 完成，PR #2795（決策 1021）。(c) 沒開始：這個工作串壓縮過一次，照規則不接新工作，交給新的工作串。
- 已驗證：Linux Swift 6.4 `swift build --build-tests -Xswiftc -warnings-as-errors`；完整量測一次約 5 分，295 列，配得到 OSM 月台的 246 列中位數 8.5 m、50 m 以上 10 列。
- 下一步的第一個指令：`STATION_ALIGN_REPORT=/tmp/before.tsv swift test --skip-build --filter StationAlignmentReportTests`（改前的表，之後和改後比）。

## 派工

- 規劃4 工作串「量月台與站房偏差」，分支 `claude/project-thread-geiw1u`；決策 1021；存檔版本、golden schema、GameCore 不動。
- 規則全文：`docs/handoff/STUDIO-MODELS-IN.md`「車站地標的規則」第 4 條（副本 `/mnt/project-files/station-rules/STATION-RULES-2026-11-27.md`）。
  重點：先放真實站房模型，再拿掉它底下的 Overture／官方 3D 建物（`underLandmark`、`replacedPlots`，決策 791、879），不是先清空再補。

## (c) 要做的（協調者 11-27 同意照 1021 §3 做；作者先前「好那你做吧」）

1. **月台沿線位置對準 OSM 月台。** 現在收購以站點為中心、照長度推（`RealLineAcquisition.swift` 約 1802 行
   `platformLength`／`half`、`stationLayout.holding(half:)`；單站收購 `RealStationPurchase.swift` `realStationOffer`）。
   台灣台鐵先用 App 裡的 `tra_platforms.json`（`RealStationData.platform(forStation:)`，`isDerived` 的是推估的）把月台中心移到兩端中點；
   其他系統與地圖要先做一份月台資料（可從 `tools/station-alignment/data/*.json` 的 OSM 月台抽，ODbL 要進 `DataSourceCredits`）。
   月台仍要在同一段平坦軌道上，移過去碰到坡、道岔、別的月台的，留原位並在測試寫明。
2. **測試守住上限。** 把 `StationAlignmentReportTests` 的量法拿一部分做成常駐測試（不要整套，5 分太久；挑台灣台鐵＋高鐵＋台南），
   `worst_m` 先訂 20 m，超過的逐站修或列例外與原因。台南一定要在裡面。
3. **台南 1936 年站房。** `Map3DStationExteriorBatch2.swift` `tainan1936` 畫在 `x = -208, z = 20`（原點 `tainanOrigin` 120.21332, 22.99714），
   真站房是 OSM r6477070（原點西約 83 m），差約 125 m；移過去、確認地下化出入口那塊（w1568887226，110 m 地面軌道在輪廓裡）
   和軌道的關係，拍改前改後（作者要求）。改 3D 的 PR 要在說明寫經驗檔或「經驗：」一行（`lessons-link.yml`）。
4. **壓軌的站房**（新烏日 418 m、高雄地標 656、花蓮 490、新左營 342、台北地標 320…，表的 `buildings_on_track`）在 3D 看是否真的撞，撞的切開或抬高。
5. 真實足跡當站房（第 4 條的第三順位）是另一大塊，可以再拆一張。

## 要注意

- 大站（台北、南港、博多）配對會配到別條線的月台，看 `other_osm_groups_across_m`；福岡地鐵、香港部分站 OSM 沒畫月台。
- 另一個工作串（STATION-LANDMARKS，決策 1020）在改 `Map3DLandmarkRegistry*`、`Map3DHongKongLandmarks.swift`、`Map3DStations.swift`、
  `Map3DHakataStation.swift`；動之前先在 #2118 看它的狀態。
- 改收購鋪線前讀 `.claude/skills/real-line-laying/SKILL.md`；會動到很多既有測試的月台位置（共站、待避線），先跑 `RealLineAcquisitionTests`。
- 評分：`railway-assets-private-2` `docs/priorities/STATION-ALIGNMENT.md`。
