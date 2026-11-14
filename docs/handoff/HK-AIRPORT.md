# HK-AIRPORT：香港機場上 3D 地圖

- 派工：遊戲規劃第 65 任（2026-11-14），雲端 thread session，分支 `claude/project-thread-4ps1jy`。作者「香港機場根本沒做」，選「照建議做」。
- 決策 733（`docs/decisions/733.md`）。存檔版本、golden、fixtures、GameCore：不動。
- 做了：`tools/airfields/build_airfields.py` 留下 OSM 誤標成內移跑道頭的整條跑道（赤鱲角 07C/25C）；香港地圖包加 `airfields.json`、`no_build.json`；`RealWorldData.load` 與 App 的 3D 把開放城市的不蓋區與機場場面和台灣的一起讀；`addGround` 不在不蓋區上染地塊色（已開香港局的綠斑）；`HongKongAirportTests`。
- 調查報告（原因、試跑數字）：專案檔 `hk-airport/HK_AIRPORT_FINDINGS_2026-11-14.md`。

## UNVERIFIED

- 雲端沒有 Swift（下載 403），編譯與測試交 CI（或作者 Mac）。
- 3D 的樣子：改前改後截圖要在作者 Mac 的模擬器拍（屬第三級：作者看過才合）。
- 台灣的 `taiwan_airfields.json` 沒有用改過的工具重建，不知道台灣有沒有線會被這次的修正多收進來。

## 留下的

- 一號客運大樓的拱形屋頂等地標模型、機場快綫機場站與航廈的連接（決策 733 §4）。
