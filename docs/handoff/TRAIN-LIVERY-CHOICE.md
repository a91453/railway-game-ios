# TRAIN-LIVERY-CHOICE 交接（2026-11-25）

## 進度

- 做到哪：機制、700T（橘色帶預設、青綠帶可選）、路線頁選單與「同款列車的路線全部套用」都做完，決策 983。
- 已驗證：Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 通過；`TrainPaintTests` 9 項與相關模型、鎖、聖誕塗裝測試通過；`hashes.lock.json` 只改 700T 的 12 行。App 端靠 CI 的 Xcode 建置，實機 UNVERIFIED。
- 下一步的第一個指令：沒有待辦；要加下一款車的塗裝，讀 `docs/decisions/983.md`「加一套塗裝怎麼做」。

派工：總表第三版功能第 7 名（`a91453/railway-assets-private-2` `docs/priorities/TRAIN-LIVERY-CHOICE.md` 第 1 列）。雲端工作串「讓玩家逐線選塗裝」，分支 `claude/project-thread-40kinx`。不動 GameCore、存檔版本、golden。

## 還留下什麼

- **N700S 的深綠線當可選塗裝**：等決策 979（N700S 換成舊版車模）合併後，在它的註冊（`Map3DTrainRegistration`）加 `paints:`，配方畫藍線、深綠做成一套塗裝。這次沒做，因為那款車模正在另一串換。
- **接下來的塗裝單**（同一份評分表第 2 到 4 列）：LIVERY-CHUKUANG（莒光客車真車橘預設、深藍可選）、LIVERY-E500-PP（E500 與推拉）、LIVERY-BODY-COLOUR（自選底色，要一個選色畫面）。前三者都只要改那款車的配方顏色加一個 `TrainPaintFamily`。
- **只有 3D 地圖換色**：2D 地圖、列車展示、車庫、列車肖像還是畫車款自己的那一套。要讓它們跟著換，從 `GameSession.trainPaint(of:on:)` 取塗裝、在各自畫車的地方套 `TrainPaint.painted`。
- **發版後請作者實機看**：高鐵路線的路線頁設定區有「700T 塗裝」選單；選青綠帶後 3D 地圖上這條線的 700T 變青綠、別條線不變；「同款列車的路線全部套用」；重開 App 選擇還在；和聖誕塗裝同時開也正常。
- 截圖驗收沒拍（路線頁多一列，ui-review §3）。
