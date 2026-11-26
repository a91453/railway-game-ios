# OLD-MODELS-CLEANUP：刪掉被新版取代的舊模型

## 進度

- 做到哪：第 1 張 #2776 已合併（2026-11-27）；#2767（N700ST）也已合併，第 2 張（下面「還留下什麼」第 1 項）可以開工。
- 已驗證：#2776 本地 `swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨、相關 18 個測試類別 116 過 1 跳過；CI gate 與 iOS 建置綠。
- 下一步的第一個指令：`grep -rn '"teal"\|highSpeedPaints\|highSpeedGameBandColor' Sources Tests RailwayGameApp`

## 規則與來源

作者 2026-11-27 01:13（Taiwan time）：遊戲內有新版模型取代時，舊模型（配方、只為它存在的測試、拍圖工具）要刪，例：綠色 700T。
舊存檔要自動轉新車。01:30：700T「青綠帶」固定塗裝改成自選顏色，就能刪。

- 派工單：OLD-MODELS-CLEANUP（#2118 登記，comment 7199454612）
- 分支：`claude/project-thread-3agume`
- 存檔版本、決策編號、golden schema：都不動（第 1 張改的是決策 988 §7、930 §6 的「後來」）

## 清查結果（2026-11-27，列車、地標、建物、車站）

| 項目 | 取代它的 | 處理 |
|---|---|---|
| 配方 700T 四節與整列（`Map3DTrainShapeRefresh.refreshHighSpeed*`、`formation`） | 決策 988 `Map3DTHSR700T` | #2776 刪 |
| #1103 蒸汽機車＋煤水車（`Map3DSteamTender`） | 決策 930 CT273（解不開時畫雙機頭 `Map3DDuplexSteam`） | #2776 刪 |
| `Map3DTrainLocomotive.ct273` 柴油替身 | 同上 | #2776 刪 |
| 工具 `tools/train-shape-refresh`（留 `glb-audit.py`，tourism-emu500、new-taipei-lrt 用）、`steam-tender`、`hsr-trains-408`、`hsr-far-422`、`n700s-n700st` | — | #2776 刪，各留 README 指 109dade0 重建 |
| 700T「青綠帶」固定塗裝（`highSpeedPaints` 的 `teal`，遊戲裡唯一的 `TrainPaint`） | 自選顏色 | **未做**，見下 |
| N700S-G、京急舊網格 | N700S、京急新 1000 | 早已刪，舊鍵轉新車（`Map3DTrainSets.byType`） |
| 九州 800／N700、地標、車站 | — | 沒有舊版；舊站型目錄 `Map3DStationKitBuildings.station` 只剩 `tools/station-kit` 七向圖用，遊戲不畫，沒動 |

刪掉的都不在存檔裡（存檔存車種鍵，舊鍵本來就轉到新車），所以第 1 張不用遷移。

## 還留下什麼

1. **700T／N700ST 帶色改自選顏色，刪 `teal`**（`Map3DTrainShapeRefresh.highSpeedPaints`，#2767 後 sets 是 700T 與 N700ST）。
   - 帶色由玩家自選（色盤或幾個預設色＋自選），換色仍走 `TrainPaint.Swap(from: highSpeedBandColor, to: 選的顏色)`，不加模型、不動雜湊。
   - 玩家裝置上記著 `"teal"` 的（`LauncherPreferences.trainPaints`）要轉成自選的同一個青綠（`highSpeedGameBandColor` = `Map3DPalette.shopAwnings[0]`），玩家看起來不變。
   - 牽涉：`TrainPaint.swift`、`LauncherPreferences.swift`、`RailwayGameApp/Views/LinesPanel.swift`（選塗裝的地方）、`Map3DPreviewScreen.swift`、`TrainPaintTests`、`Map3DTHSR700TTests`、`Map3DSeries700Tests`。
   - 是畫面改動：讀 `.claude/skills/ui-review/SKILL.md`，照決策 482 的等級截圖。
   - 順手：E200 與 700T 顏色各自分檔，刪掉 `Map3DTrainShapeRefresh.swift`（E200 移到自己的檔，700T 顏色移到 `Map3DTHSR700T` 旁）。
2. （另開單，可不做）standard 包另外做 8 種列車整列展示模型（GreenTram、FourCarMetro…formation），遊戲不畫，刪了能省開地圖時間。
3. `Map3DTrainShell.swift` 第 7 行註解還提到已刪的 `refreshHighSpeed`，下次改到時順手改掉。
