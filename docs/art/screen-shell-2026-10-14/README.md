# 整個畫面的外框（決策 226）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `solid-groups.png` 和文字紀錄；其他 2 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/screen-shell-2026-10-14/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

2026-10-14。先在 `art/screen-shell-layout` 跑了一次 `website-screenshots.yml`（run 38600383416，iPhone 17 Pro 橫拿，874×402 點），用拍到的 13 張實機截圖量出現在的版面，再畫三個方案。

美術 session 以四方角度定案 **C 路線圖的框**，理由寫在 `docs/ARCHITECTURE.md` 的決策 226。

| 檔案 | 內容 |
| --- | --- |
| `now.png` | 現況，照截圖量著重畫 |
| `a-two-platforms.png` | A 兩側月台：上面一條細看板，下面左右兩個拇指區 |
| `b-console.png` | B 車掌台：所有控制收進底部一條控制台 |
| `c-route-frame.png` | **C 路線圖的框**（定案）：iPhone 工具一欄在左、地圖控制一欄在右；iPad 工具留在左下一排。都有一條看板。多一組 iPad 直拿（820×1180） |
| `solid-groups.png` | 實色外框的三種切法：一整排、每顆分開、**按組分開**（定案），以及拖曳時那一欄變淡、iPad |
| `solid-outline.png` | 深色模式的外框：`ECEEF6` 2 點對 **`B4B9D9` 1.5 點**（定案），淺色照舊藏青 |
| `final-iphone.png` | **最終版**，iPhone 橫拿五種狀態：平常、選了車站、建造中、跟著一班車、拖曳經過左欄 |
| `final-ipad.png` | **最終版**，iPad 橫拿與直拿 |
| `c-states.png` | C 的「選了車站」「建造中」 |
| `device-61-1-vs-solid.png` | 61.1 的實機截圖（玻璃）和第 1、2 步的實色格子（CI 的 Simulator）上下比。2026-10-15 依此改回玻璃，`solid-*.png` 的材質不再適用 |

- 每張都有 iPhone（淺色、深色、灰階）和 iPad（淺色、深色）。
- 虛線框是沒有被任何按鈕蓋住的地圖，旁邊寫著約幾點。
- 地圖與站名是示意：車站、路線、建物都是假的。
- 按鈕上的圖示是 SF Symbols 的示意，App 照舊用 SF Symbols；站長用 App 裡的 `StationMasterTaiwanNormal`。
- 顏色只用 `Theme` 與 `Palette`，對比寫在 `docs/UI_THEME.md` 的「整個畫面的外框」一節。
- 預覽用 HTML 排版，再用環境裡的 Chromium（Playwright）截圖。腳本放在 scratchpad，不進 repo（art-style §3）。

## 搬到私有庫

2026-10-21 起，這個資料夾的其他預覽圖（含檢視頁）在私有庫 a91453/railway-reference-private 的 `Railway/game-art-previews/docs/art/screen-shell-2026-10-14/`，內容完整、連結照舊；這裡只留本說明與被程式或文件直接引用的圖。上面連到已搬走檔案的連結請到那裡看。
