# TAIWAN-OFFICIAL-OUTLINES：台灣各縣市官方建物輪廓

## 進度

- 做到哪：PR #2751（draft）做完。決策 1015 是台中市改用臺中市建物圖，遠景的牆和屋頂分開算大小。工作串在第 2 次壓縮停手（2026-11-26）。
- 已驗證（Linux，本機）：
  - `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨。
  - Map3DFarViewTests（含新的台中最遠視角，最多 932,476 三角形，在 5,500 m）、Footprints、LowRise、RealBuildings、FacadeVariety、RealFacade、RoofContrast、Shadow、SunShadow、DataSourceCredit、WhatsNew、Map3DSceneLayerRegistryTests 全過。
  - `doc_numbers.py --check` 過。
  - CI 在 3e1037af9 上的 Swift 各工作全綠。gate 紅是因為 iOS App Build（45809264319）在排隊時被取消，好讓 TestFlight 0.6.0 (150) 先跑，不是程式錯。
- 下一步第一個指令：等 0.7.0 上架（2026-11-27 晚）後，確認 #2751 目前 head 的 gate 與 iOS 都綠，就照「綠了就合」合併。

## 工作

- 派工單：找台灣各縣市官方、開放授權的建物輪廓，比 Overture 細的就換進內建檔（作者 2026-11-26「都行」）。
- 分支 `claude/project-thread-6rmmc9`，PR #2751。
- 決策 1015。存檔版本、golden schema、GameCore 都不動。

## 做了什麼

- 查過各縣市（決策 1015 §2）：只有臺中市建物圖（data.gov.tw 158889，政府資料開放授權）能用。臺北、新北、桃園的地形圖要申請付費、不能轉發。臺南、高雄與其他縣市沒有開放的建物面。國土測繪中心三維建物付費，不用。
- `tools/overture-footprint-tiles/official_outlines.py`（新）：
  - 官方的先鋪，Overture 補空，照決策 1001 去重。
  - 樓層照圖（`cityMap`），沒有就用原有的。
  - 牆貼牆、同樓層的相連房子併成一棟。
  - 只重寫碰到的 4,283 個圖塊。
  - 跑一次約 17 分鐘。
- 內建 `taiwan_buildings.pmtiles`：26,350,699 B → 32,360,877 B。台中 209,589 棟 → 581,684 棟。
- App：`Map3DRealBuildings` 遠景的牆照樓高斜出的大小算（`Map3DScene.Builder.farSizing`），近景不變。
- 署名（`DataSourceCredits`）與更新說明（`WhatsNewNext/new/2026-11-26-taichung-city-outlines.txt`）已寫。
- 改前改後圖：`/mnt/project-files/taichung-official-outlines/taichung-before-after.jpg`（PR 附圖）。
- Overture 2026-11-18.0：只多 0.3%，這次不重做全台。下一次全台重建時換最新版（決策 1015 §7）。

## 還留下什麼

- **合併**：0.7.0 上架前不合（協調者交代）。上架後 gate 與 iOS 綠了就合。iOS 若又被取消或排隊太久，重跑它，過了再重跑 gate（Re-run failed jobs）。
- **main 的 `taiwan_buildings.pmtiles` 如果在合併前變了**（例如別的 PR 重做台灣樓層），不要選邊合二進位檔。從 main 的檔重跑：

  ```sh
  python3 -I tools/overture-footprint-tiles/official_outlines.py apply \
    RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles out.pmtiles \
    official_outlines.json taichung=t114/01-SHP/114期末_B0001_1216n.shp
  cp out.pmtiles RailwayGameApp/Resources/BaseMap/taiwan_buildings.pmtiles
  ```

  SHP 的下載與解壓指令在工具開頭的說明裡（data.gov.tw 158889 指向的 Google Drive 檔，78 MB 7z）。要在 `usage_permits.py apply` 之後跑。跑完把 `Map3DFarViewTests.testTheFarthestViewOfTaichungIsWithinBudget` 再跑一次，確認還在一百萬三角形以內，並把決策 1015 §4 的數字改成新的。
- 其他下一步見決策 1015 §8：別的縣市開放時加來源參數、每年換新的臺中圖、要不併棟得先讓遠景再省。

## UNVERIFIED

- iOS App Build 與 iPhone UI 測試在本分支還沒跑完過（要 macOS CI）。
- 實機上台中遠景與近景的樣子還沒看過，發版後請作者看臺中車站一帶拉到最遠。
