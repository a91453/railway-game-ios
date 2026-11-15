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

## UNVERIFIED

- `MapPackDownloader` 在 iOS 上的編譯（看 PR 的 `ios-build.yml`）。
- `package.sh`、清單格式、上傳指令（要 Mac）。
- 實機下載（第二段之後）。
