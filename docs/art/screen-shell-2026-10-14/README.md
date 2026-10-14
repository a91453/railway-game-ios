# 整個畫面的外框（決策 226）

2026-10-14。先在 `art/screen-shell-layout` 跑了一次 `website-screenshots.yml`（run 38600383416，iPhone 17 Pro 橫拿，874×402 點），用拍到的 13 張實機截圖量出現在的版面，再畫三個方案。

美術 session 以四方角度定案 **C 路線圖的框**，理由寫在 `docs/ARCHITECTURE.md` 的決策 226。

| 檔案 | 內容 |
| --- | --- |
| `now.png` | 現況，照截圖量著重畫 |
| `a-two-platforms.png` | A 兩側月台：上面一條細看板，下面左右兩個拇指區 |
| `b-console.png` | B 車掌台：所有控制收進底部一條控制台 |
| `c-route-frame.png` | **C 路線圖的框**（定案）：iPhone 工具一欄在左、地圖控制一欄在右；iPad 工具留在左下一排。都有一條看板。多一組 iPad 直拿（820×1180） |
| `c-states.png` | C 的「選了車站」「建造中」 |

- 每張都有 iPhone（淺色、深色、灰階）和 iPad（淺色、深色）。
- 虛線框是沒有被任何按鈕蓋住的地圖，旁邊寫著約幾點。
- 地圖與站名是示意：車站、路線、建物都是假的。
- 按鈕上的圖示是 SF Symbols 的示意，App 照舊用 SF Symbols；站長用 App 裡的 `StationMasterTaiwanNormal`。
- 顏色只用 `Theme` 與 `Palette`，對比寫在 `docs/UI_THEME.md` 的「整個畫面的外框」一節。
- 預覽用 HTML 排版，再用環境裡的 Chromium（Playwright）截圖。腳本放在 scratchpad，不進 repo（art-style §3）。
