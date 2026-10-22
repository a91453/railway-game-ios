# 3D 地圖的亮度方案（決策 272）

> 2026-10-22 起這個資料夾只留這份 README、總覽圖 `temple.jpg` 和文字紀錄；其他 2 張圖搬到 `a91453/railway-reference-private: Railway/game-art-previews/docs/art/map3d-brightness-2026-10-17/`，檔名不變（作者 2026-10-21 的規則，`docs/HANDOFF.md` §2）。

用 `tools/map3d-preview` 畫：WebGL 照 `Map3DShaders.metal` 的算式重畫，不是 iPhone 的畫面。兩鎮地圖、下午 2 點。

每張四格：

| 左上 | 右上 |
| --- | --- |
| A：現在 | B：白天的光強一成二 |
| **C：B ＋ 公園與樹更綠（選這個）** | 目標畫面 `ftwplus-street.jpg` |

- `temple.jpg`：廟與公園，120 m。
- `rows.jpg`：透天厝街區，170 m。
- `mid.jpg`：城鎮，450 m。

試過但沒有列為方案的：地面調亮（`#E1E5F0`、`#DDE3F4`）。下午的暖光下地面變成粉橘色，所以地面照決策 241 不動。目標畫面空地上的大片草地也沒有做：空地是 2D 地圖的地面色，3D 與 2D 要一致。
