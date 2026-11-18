# MAP-PACK-OUT：App 不再帶香港、羅瓦涅米的地圖資料（決策 858）

## 進度

- **做到哪**：做完，PR 見 #2118 的登記。Release 的 App 只帶各城市的 `pack.json`，資料靠下載；發版只上傳有變的地圖包。
- **已驗證**：Linux 建置與相關測試、`testflight-map-packs.py --selftest`（決策 858 §4）。實機與第一次發版都還沒驗。
- **下一步的第一個指令**：無。下一次發版後照下面「驗收」看。

---

- 派工：協調者 11-18（作者確認 139 兩列都「已下載」；又：「但是每上傳一次就要審核一次」）；雲端工作串「拿掉內建地圖資料」，分支 `claude/project-thread-opekgf`。
- 決策 858。存檔版本、golden schema、GameCore 不動。
- 這是 `ASSET-PACK.md` 的「第三段」與 `ROVANIEMI-OPEN.md` 的 ROVANIEMI-PACK-OUT，兩個一起做完。

## 驗收（作者裝下一版 TestFlight 之後）

1. 發版的 run：「Upload the map packs that changed」那一步應該寫「The map packs are the same as at the last release; none was uploaded.」（兩包和 139 一樣）。App Store Connect 的 `mappack-hongkong` 停在第 6 版，不會多第 7 版。
2. 直接更新（不刪 App）：開 App，設定 → 地圖，兩列都是「已下載」；新遊戲 → 實景地圖，香港（若已開航）與羅瓦涅米照常可選；香港、羅瓦涅米的舊存檔照常開。
3. 想多看一步：刪掉 App 重裝，開飛航模式第一次開。台灣照玩，那兩列是「尚未下載」，清單上寫「地圖還沒下載。連上網路後會自動下載。」；關飛航模式，等一下（最慢 15 秒後重試），那兩列自己變「已下載」、清單打開，不用重開 App。
4. 不對的話按「回報問題」，看最後「地圖包：」那一行（`not fetched: …`、`not used: …`、`used: not the version the app lists`）。

## 還留下的

- **之後改地圖包內容的工作串**：改 `Resources/MapPacks/<城市>` 的任何檔，下一次發版就會上傳那一包的新版本，要審。作者在 App Store Connect 把新版本和 build 一起送審（run 的摘要會提醒）。新版還沒審過時，玩家用手機上的舊版（決策 858 §1 第 8 點），不會沒有地圖，但看不到新資料。
- **新城市**（福岡，JAPAN-FUKUOKA-1）：開放時加 `RailwayGameApp/AssetPacks/<城市>.json`；Release 的 App 自動只帶它的 `pack.json`。
- 沒有做「下載進度條」：只有下載中／已下載／尚未下載三種字。14 MB 在一般網路是幾秒，沒有評分。
- `docs/TESTFLIGHT_GITHUB_ACTIONS.md` 流程圖那一行已改。

## UNVERIFIED

見決策 858 §4：App 的編譯與 UI 測試交 `ios-build.yml`；Release 的下載路徑、離線重試、發版新步驟只有實機與第一次真的發版能驗。
