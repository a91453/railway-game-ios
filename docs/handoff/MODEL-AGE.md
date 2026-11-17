# MODEL-AGE：3D 模型新舊盤點（2026-11-17）

## 進度

- 只讀研究，做完了。
  - 報告在 `docs/research/MODEL_AGE_2026-11-17.md`。
  - 分數在 `docs/research/NEXT_PRIORITIES_2026-10-12.md` §29.15。
  - 總覽圖與兩份附表在 `docs/art/model-age-2026-11-17/`。
  - 沒有動程式、GameCore、存檔、golden 或 fixture。
- 驗證：
  - **VERIFIED**：在 Linux 上用 `tools/train-models/run.sh` 匯出模型，用 `tools/model-look/shoot.mjs` 拍圖，並排見總覽圖。
  - **UNVERIFIED**：實機 Metal；台灣汽車、機車、住宅立面的真實照片（Commons 限流）；DR1000 遠景 bug 只讀了程式。
- 下一步：照 §29.15 往下派。第一張是 bug 列（DR1000／DR3100 加進 `nearOnly`），先寫一個會紅的測試：
  ```sh
  swift test --skip-build --filter Map3DDR3100Tests
  ```

## 交給誰

| 項目 | 分數 | 誰 | 什麼時候 |
| --- | --: | --- | --- |
| DR1000／DR3100 遠景 bug | 2.30 | 雲端 | 隨時 |
| FACADE-VARIETY、ROOF-VARIETY | 3.45、2.70 | 雲端配方 | REGION-LOOK-HK（#2330，決策 812）合併之後 |
| E200-REDO | 3.40 | 雲端配方，model-look 三輪 | 隨時；鳴日號一起重漆 |
| TW-CARS、SCOOTER-OLD | 3.25、2.65 | 雲端，`tools/hk-vehicles` | 隨時 |
| PLAYER-BOX | 3.10 | 雲端，residential-kit 與 commercial-kit | 隨時 |
| 其餘 | ≤2.75 | 見報告 §4 | — |

## 還留下

- **貼圖集與夜窗都到上限了**：
  - `Map3DSurfaces.png` 是 24 層；`nightWindows[12]` 兩種表面佔一列，也是 24 種。
  - FACADE-VARIETY 若要加新窗種，就要同時改 PNG、`Map3DCamera.swift:547-554`、`Map3DShaders.metal:39` 與 `:494`、`Map3DMetalView.swift:869-938`。
  - 改之前先和 SUN-TIMES（決策 813）確認它動了 `Map3DCamera` 的哪幾行。
- 盤點初稿把推拉式自強號的 E500 列成借用，是錯的（決策 425），已更正。
- 羅瓦涅米的 VR 列車畫哪一款，地圖開放後再拍。
- **art-style §7 兩句（§29.14 第 5 項，3.35）沒改成**：這個 session 改 `.claude/skills/art-style/SKILL.md` 時被權限擋了兩次（自動模式的分類器），所以留給規劃或下一張單。建議的字句如下。
  1. 「一般建物是白、米白的方塊，窗用細線、不用貼圖；」後面接：「近處的高樓可以用幾何做出窗的樣式（陽台與落地窗、帶狀窗、帷幕牆的窗間橫帶、直條遮陽鰭、凸窗），每棟的窗寬、樓高、側面窗數不同，但仍是平塗、調色盤的顏色，不貼照片。」
  2. 「跟遊戲裡現有的列車（決策 230）、透天厝、月台放在一起看不出差別」改成：「跟遊戲裡通過 model-look 三輪的新模型（例如 E500、港鐵市區綫、追分站）放在一起看不出差別；決策 230 的早期列車、黃盒子房屋是要換的舊一代，不是比對的基準。」
- 非 3D 的舊東西已在報告 §6 盤點，分數寫在 §29.15 的第二張表。
