# ASSET-PACK：地圖包分包下載（決策 776）

- 派工：主規劃 11-15（作者：「分包下載還沒用耶」）；雲端 thread session「讓地圖包分包下載上線」，分支 `claude/project-thread-4lw06v`。
- 存檔版本、golden schema、GameCore 不動；決策 776。

## 做了（第一段）

遊戲改從 `MapPack.current` 讀海外地圖包（下載的優先、不然讀 bundle）；App 的 `MapPackDownloader` 與打包清單、`tools/asset-packs/package.sh` 備好。App 還沒有 App Group 與 extension，所以下載器不會跑，玩家看不到差別。

## 作者已做的 Apple 帳號步驟（11-15）

1. 建 App Group `group.io.github.a91453.RailwayGame`。
2. App ID `io.github.a91453.RailwayGame` 勾 App Groups、選這個 group。
3. 建下載器的 App ID `io.github.a91453.RailwayGame.MapPackDownloader`，勾同一個 group。

## 第二段

extension、App Group 權限、Info.plist 三個鍵、`testflight.yml` 打包上傳（決策 776「第二段」）。**在 133 發版之後才合併**。

## 還留下的

1. 第二段合併後第一次發版：看 `testflight.yml` 的 export 有沒有過（extension 的描述檔）、「Upload the map packs」有沒有警告；作者到 App Store Connect 該 App 確認 asset pack `mappack-hongkong` 出現、處理完成。外部測試與上架前，asset pack 要和 build 一起送審。
2. 內部 TestFlight 實機：Console（或回報問題的 log）有 `map pack mappack-hongkong used`。
3. **第三段 PR**（內部 TestFlight 實機 log 看到 `map pack mappack-hongkong used` 之後）：不再把 `Resources/MapPacks` 複製進 App；香港還沒下載完時開航名單顯示「下載中」；`OSMMapBackground.cityTiles`／`cityFootprints`／`cityPacks` 改成下載完再算。

## MAPPACK-STATUS（2026-11-16，雲端 session_01JMHz9ampfMVSjE1GvHhgjU，分支 `claude/mappack-status`）

- 派工：遊戲規劃 11-16。存檔版本、golden schema、GameCore 不動；寫進決策 776「後續」，沒有新決策。
- 做了：`MapPackStatus` 與 `MapPackDownloads.note`／`status`／`report`（GamePresentation，有 Linux 測試）；`MapPackDownloader` 記狀態；設定「地圖」一節每個開放城市一列（「香港地圖　已下載／下載中／使用內建資料」）；「回報問題」的訊息多一行「地圖包：mappack-hongkong used」（原因只在這裡）。
- **實機怎麼看（取代上面「還留下的」第 2 點接 Mac 看 log）**：裝了帶這個改動的 TestFlight 版，開設定 →「地圖」一節看「香港地圖」那一列。「已下載」＝下載並用上，可以開第三段；「下載中」一直不變＝還沒下載完或系統還沒排到；「使用內建資料」＝沒用上，按「回報問題」看訊息最後的「地圖包：」那一行是 `bundled`（這個建置沒設好下載）、`not used: …`（下載到但被拒，附原因）還是 `not fetched: …`（沒下載到，附錯誤）。
- 還留下：第三段（上面第 3 點）照舊；第三段把香港移出 App 之後，「使用內建資料」這個說法要跟著改（那時沒有內建的）。
- UNVERIFIED：iOS 編譯（看 PR 的 `ios-build.yml`）；實機下載與那一列的顯示。

## MAPPACK-FIX（2026-11-17）

136 實機香港地圖包下載到但被拒用（`incomplete("airfields.json")`）：每個檔改各自問 `AssetPackManager`，拒用時回報帶線索。見 `docs/handoff/MAPPACK-FIX.md`、決策 819；驗收是設定那一列變「已下載」，之後才做上面的第三段。

## UNVERIFIED

- `MapPackDownloader` 在 iOS 上的編譯（看 PR 的 `ios-build.yml`）。
- `package.sh`、清單格式、上傳指令（要 Mac）。
- 實機下載（第二段之後）。

## 第三段做完了（2026-11-18，MAP-PACK-OUT）

決策 858、`docs/handoff/MAP-PACK-OUT.md`：Release 的 App 只帶各城市的 `pack.json`，香港與羅瓦涅米的資料都靠下載；發版只上傳有變的地圖包。上面「還留下的」第 3 點到此結束。
