# 地圖包的 asset pack（決策 776）

把 `RailwayGameApp/Resources/MapPacks/<城市>` 打成 Apple 代管的 Background Assets asset pack（`.aar`），之後上傳到 App Store Connect，玩家的 App 另外下載。

- 清單：`RailwayGameApp/AssetPacks/<城市>.json`（`assetPackID`、下載方式、要裝的資料夾）。路徑相對於 `RailwayGameApp/Resources`，所以包裡是 `MapPacks/hongkong/...`，和 App bundle 裡同一條路徑。
- 打包（只能在 macOS、Xcode 26 以上）：

  ```sh
  tools/asset-packs/package.sh /tmp/asset-packs
  ```

  只包其中幾包：後面接 `assetPackID`（`tools/asset-packs/package.sh /tmp/asset-packs mappack-hongkong`）。

- 上傳由 `testflight.yml` 做（決策 858）：**只上傳內容有變的那幾包**，因為 App Store Connect 每上傳一次就多一個版本、每個版本都要審。哪幾包有變由 `.github/scripts/testflight-map-packs.py` 判斷（和上一次成功發版的 commit 比 git 雜湊）；要全部重傳，按 workflow 時 `map_packs` 選 `all`。手動上傳是：

  ```sh
  xcrun altool --upload-asset-pack /tmp/asset-packs/mappack-hongkong.aar \
    --apple-id <App 的 Apple ID> --api-key <KEY_ID> --api-issuer <ISSUER_ID>
  ```

- Release 的 App 不帶這些資料夾裡的檔，只帶各自的 `pack.json`（決策 858）；Debug 的 App 整包帶。所以改了地圖包的任何檔，下一次發版就會上傳新版本。

- 授權：包裡的檔案和 `MapPacks/hongkong/pack.json` 的 `licences` 一樣（OpenStreetMap ODbL、DATA.GOV.HK、WorldPop CC BY 4.0、CSDI），鳴謝照舊在 `DataSourceCredits`。
