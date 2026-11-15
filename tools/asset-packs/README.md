# 地圖包的 asset pack（決策 776）

把 `RailwayGameApp/Resources/MapPacks/<城市>` 打成 Apple 代管的 Background Assets asset pack（`.aar`），之後上傳到 App Store Connect，玩家的 App 另外下載。

- 清單：`RailwayGameApp/AssetPacks/<城市>.json`（`assetPackID`、下載方式、要裝的資料夾）。路徑相對於 `RailwayGameApp/Resources`，所以包裡是 `MapPacks/hongkong/...`，和 App bundle 裡同一條路徑。
- 打包（只能在 macOS、Xcode 26 以上）：

  ```sh
  tools/asset-packs/package.sh /tmp/asset-packs
  ```

- 上傳（App Store Connect API 金鑰，和 `testflight.yml` 用的同一把；還沒接進 workflow）：

  ```sh
  xcrun altool --upload-asset-pack /tmp/asset-packs/mappack-hongkong.aar \
    --apple-id <App 的 Apple ID> --api-key <KEY_ID> --api-issuer <ISSUER_ID> --wait
  ```

- 授權：包裡的檔案和 `MapPacks/hongkong/pack.json` 的 `licences` 一樣（OpenStreetMap ODbL、DATA.GOV.HK、WorldPop CC BY 4.0、CSDI），鳴謝照舊在 `DataSourceCredits`。
