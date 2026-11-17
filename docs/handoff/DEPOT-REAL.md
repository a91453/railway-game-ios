# DEPOT-REAL（2026-11-17）

- 派工：遊戲規劃 session_01JMHz9ZJWaKh8kjuNDLtvar（NEXT_PRIORITIES §29.17 第 3 列）。session `session_01JMHz9bsrazDrT4xMPmDZJE`，雲端 Linux，分支 `claude/depot-real`，決策 829。
- 存檔版本不動（107）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。**GameCore 沒有改**，只改 GamePresentation 的收購鋪軌。

## 進度

- **做到哪**：做完了，PR 已開（等 CI）。這個 session 壓縮過 1 次，不再接新工作。
- **已驗證（Linux debug）**：香港兩線新局（擬實）收班死結 11 分鐘 → 0、誤點 477 → 326、沒發 12/740 → 13/732；`HongKongDepotTests` 4 個通過；機捷擬實一天的雜湊與 `main` 相同（`225289834efa6054`）。
- **下一步的第一個指令**：留下的第 1 項（清晨出庫排隊）：`DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_SIMPLE=1 DEPOT_RETURN_CONTROLLED=1 DEPOT_RETURN_WATCH=106200-108600 DEPOT_RETURN_WATCH_AT=蘆竹 swift test --skip-build --filter DepotReturnReportTests/testTheTaoyuanAirportLine`

## 做了什麼

- 香港的南港島綫、東涌綫收購時蓋出真實車廠：黃竹坑車廠 10 股、小蠔灣車廠 12 股（`RealLineDepotSite.wongChukHang`、`.siuHoWan`，位置從 OpenStreetMap 讀，`tools/rail-depots/hk_depot_site.py`）。
- 小蠔灣在第一條正線那一側，加了鏡像鋪法（`RealLineDepotLayout.lay(onFirst:)`）；只開給香港的線，台灣各線鋪出來的軌道不變。
- 回歸測試 `Tests/GamePresentationTests/HongKongDepotTests.swift`（在 `main` 上是紅的）。
- 機捷兩座機廠的真實停車股道數查到了（蘆竹 23、青埔 15，`tools/rail-depots/tymc_yard_tracks.py`），照鋪與只補到 18 都量過，**沒有收**：簡化＋管制清晨多漏班（決策 829 §4 的表）。兩座機廠維持 16、12。
- 數字、資料來源、五方、對照表都在 `docs/decisions/829.md`；留下的三項打了分，在 NEXT_PRIORITIES §29.30。

## HK-NIGHT-PARKED（§29.25 第 2 列）量到的

- 新買的線：機廠規則接手了（過夜車進車廠，`hk-tcl`、`hk-sil` 兩晚死結 0 分鐘）。
- 作者的存檔：**沒有接手**。存檔裡的線沒有車廠，這一版不會補。重放與 `main` 一模一樣：東涌綫 2、3、4 號 02:34 等到 05:54，200 分鐘，雜湊 `c285244e71926b28`。重現指令在決策 829 §5（存檔在私庫，不進這個公開庫）。照派工單不另修。

## 還留下什麼

分數與五方在 NEXT_PRIORITIES §29.30；細節在決策 829 §6。

1. **D2 的兩點都沒有解**（「05:56 那一班」「蘆竹機廠滿」）。量到的成因是同一個：清晨幾班同時要從蘆竹出庫，出庫的提前量只算一列自己的路程（`RunDepot.swift` 的 `runTrainLeavingDepot`）。加股數只會讓清晨要出庫的車更多。這是 GameCore 的死結類工作，這個 session 沒有動（壓縮過一次之後不接新工作；D2 已經試錯三條路，要從頭量）。DEPOT-DAWN-QUEUE，2.40。
2. 已經買下的線補線中間的機廠（香港舊存檔）。DEPOT-ADD-MID，2.15。
3. 機場快綫、迪士尼綫共用小蠔灣。1.85。
4. 香港尖峰尾沒發的班比沒有車廠時多 1 到 2 班（`hk-sil` 9 → 10、`hk-tcl` 3 → 4、`hk-airport` 3 → 5），原因沒查到；當下沒有車在車廠。併在 §29.25 第 1 列 HK-LATE-RUNS。

## UNVERIFIED

- 黃竹坑、小蠔灣真實可停幾列（港鐵沒有公開）；遊戲照列車數鋪。
- iOS 上的畫面沒有看（雲端沒有模擬器）：車廠用既有的機廠軌道與 3D 設施，沒有新畫面；小蠔灣一帶的地形是填海地，Linux 測試只確認鋪得上、車進得去。
- 量測都是 Linux debug；一年的營收沒有量。
- 這個 session 量測用的 log 在暫存區，不會留下；要重跑照決策 829 §4 的指令。

## 怎麼重現

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
swift test --skip-build --filter HongKongDepotTests
# 兩線新局兩晚（約 6 分鐘）；單線加 DEPOT_RETURN_ONLY=hk-sil（1 分鐘）或 hk-tcl（3 分鐘）
DEPOT_RETURN_REPORT=1 DEPOT_RETURN_EPISODES=1 DEPOT_RETURN_CHECKSUM=1 swift test --skip-build --filter DepotReturnReportTests/testHongKong
```
