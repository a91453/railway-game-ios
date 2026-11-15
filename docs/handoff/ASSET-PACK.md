# ASSET-PACK：地圖包分包下載（決策 776）

- 派工：主規劃 11-15（作者：「分包下載還沒用耶」）；雲端 thread session「讓地圖包分包下載上線」，分支 `claude/project-thread-4lw06v`。
- 存檔版本、golden schema、GameCore 不動；決策 776。

## 做了（第一段）

遊戲改從 `MapPack.current` 讀海外地圖包（下載的優先、不然讀 bundle）；App 的 `MapPackDownloader` 與打包清單、`tools/asset-packs/package.sh` 備好。App 還沒有 App Group 與 extension，所以下載器不會跑，玩家看不到差別。

## 還留下的

1. **作者的 Apple 帳號步驟**（一次一步，作者做完一步再給下一步）：
   1. 開發者網站 Certificates, Identifiers & Profiles → Identifiers → 右上 + → App Groups → 說明填 Along the Line map packs、ID 填 `group.io.github.a91453.RailwayGame`。
   2. 同一頁的 App ID `io.github.a91453.RailwayGame`：勾 App Groups，選上面那個 group，存檔。
   3. （第二段 PR 合併、`testflight.yml` 第一次跑過之後）App Store Connect 該 App → 確認 asset pack `mappack-hongkong` 出現、處理完成；外部測試前和 build 一起送審。
2. **第二段 PR**（作者做完 1.1、1.2 之後）：`project.yml` 加 extension target `MapPackDownloader`（bundle ID `io.github.a91453.RailwayGame.MapPackDownloader`，`EXExtensionPointIdentifier` `com.apple.background-asset-downloader-extension`，`StoreDownloaderExtension`）、兩邊的 App Group 權限、App 的三個 Info.plist 鍵；重產 Xcode 專案；`testflight.yml` 在 export 前打包、上傳（`altool --upload-asset-pack`）；`testflight-verify-ipa.sh` 檢查 extension 在 IPA 裡。extension 的 App ID 是否能由 `-allowProvisioningUpdates` 自動建、自動掛 App Group，未確認；不行的話作者在開發者網站多建一個 App ID 並勾同一個 group。App 照舊帶香港。
3. **第三段 PR**（內部 TestFlight 實機 log 看到 `map pack mappack-hongkong used` 之後）：不再把 `Resources/MapPacks` 複製進 App；香港還沒下載完時開航名單顯示「下載中」；`OSMMapBackground.cityTiles`／`cityFootprints`／`cityPacks` 改成下載完再算。

## UNVERIFIED

- `MapPackDownloader` 在 iOS 上的編譯（看 PR 的 `ios-build.yml`）。
- `package.sh`、清單格式、上傳指令（要 Mac）。
- 實機下載（第二段之後）。
