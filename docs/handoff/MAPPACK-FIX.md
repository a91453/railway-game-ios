# MAPPACK-FIX：下載的香港地圖包被拒用（決策 819）

- 派工：遊戲規劃 11-17（bug）；雲端 session_01JMHz9YiuyqQSmoz6Bk5oTv，分支 `claude/mappack-fix`。
- 存檔版本、golden schema、GameCore 不動；決策 819。

## 做了

- 原因（從 Apple 文件與實機訊息推出，沒有實機重現）：`url(for: pack.json)` 給的是只放那一個檔的資料夾，App 卻拿它當整包的資料夾，所以清單第一個檔 `airfields.json` 就找不到。repo 裡 `pack.json` 的 15 個大小全部正確。
- 修法：每個檔各自問 `AssetPackManager.url(for: "MapPacks/hongkong/<檔名>")`，問不到的再問整個資料夾一次接檔名；`MapPack` 讀檔改吃每個檔各自的 URL（不在 App Group 另建資料夾，不多佔 14.3 MB）。
- 拒用時，「回報問題」的「地圖包：」那一行與 log 多一段括號線索：每種問法找到幾個檔、`pack.json` 所在資料夾與裡面有幾個項目、第一個沒找到的檔清單上的大小與各問法給的位置在不在。
- 封存時的 ExtensionKit 警告：Xcode 的已知誤報，extension 在 IPA 的 `Extensions/` 裡（136 的 IPA 檢查是 yes），不改（決策 819）。

## 驗收（作者裝下一版 TestFlight 之後）

1. 開 App 等幾秒（下載器在背景跑），設定 →「地圖」→「香港地圖」應該是 **已下載**。
2. 如果還是「使用內建資料」：按「回報問題」，看最後「地圖包：」那一行：
   - `used`：其實已收下，是那一列沒更新，回報給規劃。
   - `not used: …（found N of 15 files (a, b by locator); pack.json in …）`：a 是逐檔問找到的、b 是問整個資料夾找到的。0 與 0 表示兩種問法都拿不到檔，把整行貼到 #2118。
   - `not fetched: …`：沒下載到（和這張無關的原因，例如網路、App Store Connect 還沒處理完）。

## 還留下的

- 實機看到「已下載」之後，另開一張做決策 776 第三段（香港、羅瓦涅米移出 App）。ROVANIEMI-OPEN（決策 818）照舊隨 App 帶。
- 如果實機回報兩種問法都拿不到（`0, 0 by locator`），下一個試的是 `AssetPackManager.contents(at:)` 讀 JSON、`descriptor(for:)` 開 pmtiles（文件說這兩個比 `url(for:)` 可靠），那時 `MapPack` 要能吃「讀資料的函式」而不只是 URL。

## UNVERIFIED

- `MapPackDownloader` 的 iOS 編譯（看 PR 的 `ios-build.yml`）。
- 實機下載的檔案位置與修好與否（上面的驗收）。
