# ROVANIEMI-OPEN：羅瓦涅米開放

## 進度

- **做到哪**：做完。開關、新遊戲清單、第 3 週聖誕老人村、價格與備用車量測、網站 credits（railway-reference-private #145，draft）。
- **已驗證**（Linux 雲端，VERIFIED）：
  - `swift build --build-tests -Xswiftc -warnings-as-errors`；
  - release 跑相關的 90 項測試；
  - `RovaniemiReportTests` 30 天：兩條線都虧，死結 0 分鐘。
- **下一步的第一個指令**：無（等 PR 的 CI）。

---

- 派工單：ROVANIEMI-OPEN（遊戲規劃，2026-11-17）；session_01JMHz9bckVEprLBmpgpVmVQ；分支 `claude/rovaniemi-open`。
- 決策 818。存檔版本、golden schema、GameCore、`project.yml`（Xcode 專案）都不動。

## 做了什麼

細節在 [`decisions/818.md`](../decisions/818.md)。

- `OverseasMaps.open` 加羅瓦涅米，資料來源頁跟著列。
- 新遊戲清單一開始就列羅瓦涅米：不靠航班，圖示是雪花，也不記成「第一張地圖」。
- `AssetPacks/rovaniemi.json`。地圖包**照舊隨 App 帶**（規劃 11-17 補充）。
- 地圖說明改成兩條線。
- 第 3 週在羅瓦涅米改成「讓一條路線連到北極圈上的聖誕老人村」。
- 平衡：**CRITICAL**，兩條線怎麼買都虧，沒修，排進優先清單 §29.20。
- 凱米耶爾維的備用車：決策 810 已經修好，量到 0 分鐘，沒改資料。

## 還留下的

1. **ROVANIEMI-PAIR**（bug，§29.20 第 1 項）：兩條一起買，主線的上車人數少一半。重現與數字在決策 818 §2。
2. **ROVANIEMI-FARE**（§29.20 第 2 項）：買來的線永遠回不了本，票價或成本要在 GameCore 改。
3. **ROVANIEMI-PACK-OUT**（§29.20 第 3 項）：下載修好後，把地圖包移出 App。現成的做法在這個分支的 commit `4967086`（之後在 `b938cf0` 收回）：
   - `project.yml` 只列 `Resources/MapPacks/hongkong`（`copyFiles` 到 `MapPacks`），XcodeGen 重產。
   - `MapPack.bundled` 在沒有 `pack.json` 時回傳 `nil`；`OverseasMap.isCarried`。
   - `MapPackDownloads.waitForAnswers(_:timeout:)`：App 啟動讀實景資料前，最多等 8 秒 App 沒帶的包。
   - 設定裡沒帶的城市寫「尚未下載」；清單上那一列寫「地圖下載中／還沒下載／關掉 App 再打開」。
   - `BaseMapFiles.cityTiles`／`cityFootprints`／`cityPacks` 改成每次算。
   - 對應的 Linux 測試也在那個 commit。
   - 這也就是 `ASSET-PACK.md` 的「第三段」，香港可以一起做。
4. **網站 credits**：railway-reference-private #145，開放羅瓦涅米的那一版發了之後才合。
5. **發版時（作者的 App Store Connect 步驟）**：`testflight.yml` 會多上傳 `mappack-rovaniemi`，要和 build 一起送審（同 `mappack-hongkong`）。

## UNVERIFIED

- iOS 編譯、UI 測試：交 PR 的 `ios-build.yml`。
- 新遊戲清單上那一列（雪花圖示、說明）：沒在模擬器或實機看過。網站截圖只跑一次，沒拍到就照 ui-review §3 合併後由作者看。
- 第 3 週的活動卡說明：要把裝置日期調到 12/15–12/21、開羅瓦涅米新局才看得到。
- 羅瓦涅米地圖在實機的記憶體與載入時間（13.4 MB），沒量。
