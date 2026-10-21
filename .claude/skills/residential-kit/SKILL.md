---
name: residential-kit
description: 台灣住宅街廓、界牆、庭院設施與四組景的原生 3D 配方、接點和七向透明圖。
---

# ResidentialKit

先讀 `CLAUDE.md`、`.claude/skills/art-style/SKILL.md`、`.claude/skills/station-kit/SKILL.md` 與工作登記 #231。只在本批新檔延伸；地圖放置、GameCore、存檔、Golden 與既有 Kit 由原負責者處理。

`Map3DResidentialKit.Part` 有 8 種住宅、8 種界牆與出入口、8 種庭院／街邊件；`Example` 有 4 個獨立組景。`Map3DResidentialKit.model(for:)` 按需建置。`Map3DModelPack(residentialKit:)` 預設不把它們加到常駐地圖模型。

內部幾何為 x 向前、y 向上、z 向右；原生檔及接點為 x 向前、y 向左、z 向上，單位公尺。落地物的最低 z=0。`balconyModule` 背板 x=0，必須貼實牆；其樓板和斜撐接到背板。`brickWall`、`tileWall` 的左右接點可接續邊牆。屋頂水塔與太陽能板須放在實體樓板上。窗面背後須有實牆，雙扇玻璃、窗框與背板需分層避免共面閃爍；騎樓和雨棚必須有接地的立柱，屋簷與門框不能懸空。住宅陽台須有接合牆體的樓板及可對應的落地門，太陽能板等斜面件要有可見的厚度與底面。

原始 factory 的路徑、SHA、授權條件與每件改造對照只在私有庫的 `remix-provenance.json`。新批次也先讀私有 `MODEL_CATALOG.json`、`ASSET_LICENSE.txt` 和實際 factory；重新設計輪廓或組件配置，不只換色。不得公開原 factory、原包模型、貼圖或品牌，也不得把私有原始素材送外部生成服務。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/residential-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/residential-kit-2026-10-21
```

沿用 `tools/station-kit/` 的 native、GLB 編碼器與 WebGL renderer。重建會匯出 28 native、28 GLB、196 張 384px 七向透明 PNG，生成分類、組景、下斜視及多底色預覽，並測試格式、SHA、瀏覽器操作與相關 XCTest。所有單件和組景均需低於原生 loader 15,000 三角形。若要重畫，刪除輸出目錄的 `render-cache.json`；既有快取只有 native SHA、renderer SHA 與七張圖片 SHA 全相同才會重用。

人工打開 `previews/parts.png`、三類總覽、`examples.png`、`directions.png`、`undersides.png`、`style-checks.png`，並在 viewer 旋轉檢查窗背、接柱、屋簷、樓板、底面。公開庫只放生成配方、工具、測試、此 skill、單一總覽與小型驗證 JSON；大型模型、完整圖、viewer 與來源對照只放私有庫。

報告明確標 VERIFIED／UNVERIFIED。Chromium WebGL 成功不代表 iPhone Metal、實機效能或遊戲地圖已接入。完整 Swift suite 交 CI。兩庫各開 draft PR，不自行合併。
