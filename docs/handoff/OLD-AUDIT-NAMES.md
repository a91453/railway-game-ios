# OLD-AUDIT-NAMES：依舊版模型盤點報告正名（2026-11-24）

## 進度

做完名稱與決策；精細版京急新1000形重轉待 Mac。

- 派工：協調者，依 agy-c 舊版模型校對報告（2026-11-24，作者看圖確認的 17 題）。
- session：session_01YGNNunLoYvk8pDbKeZNsyX，分支 `claude/project-thread-0yder1`。
- 存檔版本、決策編號、golden schema 都不動；決策 767、891、924 各補一節「後來」。

## 做了什麼

- 車庫裡的紅色通勤車改名「京急新1000形」，分類「日本」，軌距 1,435 mm（決策 891 後來）。
- 決策 767 的儲煤台正名「給炭台」（資料來源頁跟著改），924 的給水塔正名「給水タンク」（維持現件 `2cedf43508`），程式註解與 `tools/old-models/old_tanks.py` 的來源字串跟著改。
- 舊版 `69ca306c2c` 是「レストラン」：遊戲 repo 沒有它的決策（原本預定的 944 後來給了關渡大橋），正名只在素材庫 -2（`old-port-japan-modern-station-2026-11/README.md`、`docs/priorities/JP-ROADSIDE-RESTAURANT.md`）。

## 還留下什麼

1. **京急新1000形改用精細版重轉**（要 Mac）：舊版 `~/SwiftRailMac/assets/models/item_54af03fae6….glb`（車頭）與 `item_a78b3de843….glb`（中間車）。雲端找不到備份。
   - 第一步：在 Mac 把兩個 GLB 與縮圖推到素材庫 -2 `game-art-previews/docs/art/old-port-keikyu-new1000-2026-11/old-version/`（照 `old-port-japan-modern-station-2026-11/README.md` 的表記大小與 SHA-256）。
   - 再照 `tools/texture-palette/`（`cut_faces.py`、`to_swift.py`）重轉成 `Map3DRedCommuterMesh.swift` 的 `encodedCab`、`encodedMiddle`：中間車改用 `a78b3de843`，不再拿車頭後半鏡像。顏色照決策 891 的色票。
   - 改了網格要重算 `Map3DModelPackLockTests` 的摘要；`Map3DTrainSetTests`、`Map3DModelTests` 的 `set-redCommuter-*` 名稱不用改。
   - 同外形的銀色車身紅帶「新1000形(ステンレス車)」車頭 `af620959c2`（415 面）可之後另評。
2. 給水塔改用 7 貼圖版 `ea3a5ef18b`：低優先，下次重做給水塔時一起（決策 924 後來）。

## UNVERIFIED

車庫的新名稱與分類沒有在 Simulator 或實機看過（Linux 只跑了 GamePresentation 的測試）。
