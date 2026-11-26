# DEBUG-150：0.6.0 (150) 地圖包全部「尚未下載」

雲端工作串「修好 150 地圖包下載不了」，分支 `claude/project-thread-biw3d8`。存檔版本、決策、golden schema 不動。

## 進度

- 做到哪：修正 PR 已開（見 #2118 的登記）；等 CI 綠就合，再由作者從 `main` 跑 `testflight.yml` 出 0.6.0 (151)。
- 已驗證：`MapPackDownloadsTests` 在 Linux 全過（含新的 `testAPackFoundOnlyBySearchingTheSharedFolderIsTaken`）。App 端（`MapPackDownloader.swift`）只能在實機驗，UNVERIFIED。
- 下一步：151 裝上後看設定的三列地圖；若還是「尚未下載」，請作者貼「回報問題」的「地圖包：」那一行，看 `url(for:) said …` 與 `… MapPacks files in the shared folder` 兩段。

## 看到的

- 作者 iPhone（iOS 27.3，iPhone18,1）裝 150 後，香港、羅瓦涅米、福岡三列都是「尚未下載」，按「重新下載」也一樣；147 前一天正常。
- 回報：`mappack-hongkong not used: noManifest (pack.json looked for at nowhere)`，另兩座城相同。也就是 `ensureLocalAvailability` 沒有出錯（不然會是 `not fetched`），可是 `AssetPackManager.url(for:)` 對 `MapPacks/<城市>/pack.json` 和它的資料夾都沒給位置，連手機上的舊版也沒有。
- App Store Connect：六包（香港 7、羅瓦涅米 4、福岡 4、佐賀／熊本／長崎 2）20:22–20:24 上傳，20:55 都是「準備進行內部與外部測試」。所以不是審核或處理中的問題。
- 150 和 147 之間，香港這條路的程式沒變（決策 991 只多了福岡的分包），Info.plist、entitlements、extension 也沒變；150 是第一次一次傳六包、第一次有分包。根因在系統那一端，沒查到確定的原因。

## 改了什麼（151）

1. `take` 多第三個找法：在 App Group 的資料夾裡找路徑含 `MapPacks/<城市>/<檔名>` 的檔（同一路徑有兩份取最新），`url(for:)` 失靈時也讀得到（`MapPackDownloads.mapPackFiles(under:)`）。
2. 系統說包在手機上、卻一個檔都找不到（`noManifest`）時，把那座城的每一包 `remove` 掉、`ensureLocalAvailability` 重抓一次，再讀。每次問（開 App、按「重新下載」）最多一次。
3. 回報問題的「地圖包：」在 `noManifest` 時多寫兩段：`url(for:)` 回的錯（最多兩條）、App Group 資料夾裡看到幾個 `MapPacks` 檔、哪些城市。
4. 保底：Release 也把地圖包整包裝進 App（`project.yml` 的 `CARRY_MAP_PACKS`，預設 YES；設 NO 回到只帶 `pack.json`），App 約多 140 MB；`testflight-verify-ipa.sh` 不再擋，只在摘要列出帶了幾個檔。App 照樣在背景下載，下載到就用下載的、沒有就用內建的，所以回報裡的「地圖包：」還是看得到下載的結果。內建時不做第 2 點的重抓（不然每次開 App 都重抓 140 MB）。

## 0.7.0

- 地圖包從 150（`760d40d`）到現在沒改，151 與之後的發版不會再傳新版（`testflight-map-packs.py` 跟上一次成功的 run 比）。
- 0.7.0 送審前：先看 151 的回報。下載正常（三列「已下載」、回報沒有 `noManifest`）才把 `CARRY_MAP_PACKS` 設成 NO 拿掉內建；查不出來就帶著內建送審（App 大 140 MB，但玩家一定玩得到）。
- 送 App Store 審核時，在版本頁的「素材包」把六包目前的版本一起加進去（香港 7、羅瓦涅米 4、福岡 4、佐賀／熊本／長崎 2）。
