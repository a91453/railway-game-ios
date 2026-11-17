# FACADE-VARIETY（決策 817）

## 進度

- 做完：五個立面圖層、每棟的開間與樓高、近景的陽台／遮陽鰭／凸窗（每塊 8,000 個三角形）、香港地標夜窗；看圖三輪，總覽圖在 `docs/art/facade-variety-2026-11-17/`。
- 已驗證（Linux，本機）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；定案的程式跑 13 類 Map3D 測試 98 個全過（含新的 `Map3DFacadeVarietyTests` 6 個；第一輪的程式另跑過 20 類 144 個）；三角形與建置時間見決策 817。
- 下一步：等遊戲規劃看總覽圖；CI（iOS 的 Metal 編譯與 UI 測試）結果。

## 交接

- 派工：NEXT_PRIORITIES §29.14 第 1 項（3.45）與決策 791 的香港地標夜窗（2.55）；session_01JMHz9af2P3vR3U4bFQFtGD，分支 `claude/facade-variety`。
- GameCore、存檔版本、golden、SaveFixtures、ReplayFixtures 不動。
- 新外觀：照派工單，遊戲規劃看過總覽圖才合併。
- UNVERIFIED LOCALLY：`Map3DShaders.metal` 的 `nightWindows[16]`、`glassMirror[32]` 在 Metal 上的編譯與畫面（Linux 只比對陣列內容）；實機的幀時間。
- 還留下的（決策 817「還有哪裡不好」）：預算到頂的塊仍有幾棟陽台塔沒有欄板；圖層每層一樣，沒有頂樓或低樓層換樣式；十字形、Y 形公屋要資料有那個外框。
