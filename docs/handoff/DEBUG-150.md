# DEBUG-150：0.6.0 (150) 地圖包全部「尚未下載」

雲端工作串「修好 150 地圖包下載不了」，分支 `claude/project-thread-biw3d8`。存檔版本、決策、golden schema 不動。

## 進度

- 151（TestFlight run 151，main `60d841a8`）11-26 22:37 上架。作者 iPhone 上設定三列都是「使用內建資料」，香港、羅瓦涅米、福岡都能玩：內建保底有效。
- 下載還是壞的，151 的回報說出原因（下面「151 的回報」）。根因在系統端，App 端沒有可修的地方。
- 0.7.0 送審版保留內建（`CARRY_MAP_PACKS` 預設 YES；與發版串說好）。

## 151 的回報

三包都是 `noManifest`；`url(for:)` 對 `MapPacks/<城市>/pack.json` 和 `MapPacks/<城市>` 都回同一個錯：
`NSCocoaErrorDomain Code=513`「你沒有在檔案夾「<UUID>」裡面儲存檔案「Staged Subpaths.plist」的權限」（每包一個 UUID），App Group 資料夾裡沒有任何 `MapPacks` 檔。

- 也就是系統替 App 準備檔案時，要在那包的資料夾寫一份 `Staged Subpaths.plist`，卻被拒絕。問檔、問資料夾都一樣，所以 FB19512759 的「改問資料夾」繞不過。
- 手機從 11-07 起就是 iOS 27.3（24C5037i），147 那天也是，所以不是系統更新造成。150 與 147 的差別在 App Store Connect 那邊：六包一次上傳、香港等包按了「取代」、福岡多了分包。猜測是新版本的資料夾權限在手機上壞了（UNVERIFIED）。
- 151 內建了地圖，所以「刪掉重抓」不會跑（`!city.isCarried`）；設定裡的「移除」對內建的城市也不能按。要驗證重抓能不能修好，得用不內建的版本，或刪掉 App 重裝（存檔會不見，除非在 iCloud）。
- 可以回報 Apple（Feedback Assistant，Background Assets）：附上這段錯誤和 iOS 版本。
- 147（628fd6a）→ 150（760d40d）比過：香港的下載程式、Info.plist、entitlements、StoreDownloader 擴充都沒改（`MapPackDownloader.swift` 只把一個 ID 換成 `assetPackIDs`，香港與羅瓦涅米仍只有自己一包，`assetPackPath` 對它們給的路徑和以前一樣）；`testflight.yml` 只把時限從 45 改 90 分。改了的是**三個城市的資料本身**（香港、羅瓦涅米人口換官方，羅瓦涅米建物、福岡地形與分包），所以 150 是手機第一次把已下載的三包都換成新版本；147 時手機是第一次下載，沒有舊版要換。最可能是「換新版」這一步在手機上壞了（UNVERIFIED），不是分包本身（沒分包的香港也壞）。要不內建，得先在一台裝過舊版的手機上證明換版本能成功。

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
