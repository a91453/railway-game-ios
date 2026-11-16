# WREATH-NOSE 交接（2026-11-17）

session_01JMHz9cB996ub7hhXd25E4Q（雲端，Opus），分支 `claude/wreath-nose`，決策 806 §8（補充，不另取號）。存檔、golden、GameCore、fixtures、模型包與雜湊：都不動。

## 做了什麼

- `Sources/GamePresentation/Map3DChristmasLivery.swift`：`Dresser` 記下朝前的車窗玻璃；`windscreen(nose:span:)` 量擋風玻璃下緣，`longNose(_:)` 判長車鼻（玻璃下緣離車頭 ≥ 1 m）；`addNoseWreath` 把花圈縮成七成、放在鼻尖與玻璃之間的斜面上。其他車照決策 806 §7。
- 測試：`Map3DChristmasLiveryTests` 加兩個（長車鼻的花圈不碰任何車窗玻璃、在擋風玻璃下 0.1 m 以下、不超出車頭、比原本小；平頭車不判成長車鼻）。
- 工具：`tools/model-look/pair-livery.sh`（兩次匯出並排：原塗裝｜改前｜改後）；`shoot-livery.mjs` 讀 `labels`、多一張車頭近看（`nose-*.jpg`）。
- 圖：`docs/art/winter-livery-2-2026-11-16/wreath-nose-*.jpg`，三輪看圖寫在同資料夾 README 的「WREATH-NOSE」。阿里山機車的花圈（決策 806 修過、沒重拍的那個）在近看圖裡重拍了。

## 還留下的

- 總覽圖要規劃看過才合（`wreath-nose-game-day.jpg`、`wreath-nose-game-night.jpg`）。
- EMU3000 的花圈在深灰車鼻上對比低；EMU3000 車頭上方朝上的深灰面被雪頂蓋白（雪頂規則，不在這張單）。要改的話另開單。

## UNVERIFIED

- Metal 畫面、實機；圖是離線 WebGL。App 的程式沒改。
