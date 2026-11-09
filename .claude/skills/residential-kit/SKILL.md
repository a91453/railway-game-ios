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

## 傳統建築：中式屋頂零件＋照片定比例＋OSM 外框（決策 669）

1. 先在 #1579 登記；讀本 skill、art-style、決策 457／610／669。先找現有
   `Map3DChineseRoof.swift` 與 `Map3DRealFacade.swift` 的零件，不另外寫一套屋頂或冷氣機。
2. 一棟有名稱的真實建築先記錄照片 URL、拍攝角度／日期／授權及 OSM way/relation ID、
   資料日期與 ODbL 致謝。OSM 從 Taiwan 全島 PBF 讀取，不能用 Overpass。
   將外框轉成公尺局部座標，量長寬、朝向、前後殿／護龍位置；不要拿包圍盒填滿三合院中庭。
3. 用正面與側面照片，以已知門寬或 OSM 面寬為比例尺，分別估牆高、屋脊高、出簷、
   開間與護龍高。透視照片不能當正投影；遮蔽處標推估或未知。尺寸與照片比值逐項寫進
   每輪 README／SOURCE，不能把通用 kit 尺寸宣稱為測繪值。沒有照片或可靠外框時只做
   明確標示 illustrative 的通用建築，本輪即為這種情況。
4. kit 內座標 x前/y上/z右；`kitChineseRoof` 轉接既有 `LandmarkMesh.chineseRoof`，
   以 5 倍建屋頂再縮回，讓地標原有的脊飾厚度適合小建築。長邊是屋脊方向；
   廟門／正側殿用歇山、翹角和簡化燕尾；住宅用低翹角歇山。現有零件不能精確表現
   馬背山牆時必須記缺口，不把歇山稱為馬背。屋簷底要接牆頂，不用抬高藏交界。
5. 小口磚用磚紅牆面與淺色帶分塊，不逐塊堆砌。窗雨遮出挑 0.55m、有厚度和底面；
   冷氣用決策 610 的 `addStub`（0.35 × 0.8 × 0.55m、8 三角），貼實牆。
   既有鐵窗、騎樓、水塔與頂加不重做。所有轉入的屋頂只輸出 plain 色面，不依賴 Metal tile shader。
6. `model(for:)` 取新近景；`model(for:far:true)` 保留原配方；
   `model(for:far:false,traditional:false)` 明確回退。近景選用是呼叫者責任；
   本輪不改地圖 LOD／Map3DScene。每個零件和整棟量近／遠三角形，寫進 PR。
7. 重建六種本輪模型（兩個 kit 共用同一工具）：

   ```sh
   tools/civic-kit/rebuild-roofs.sh ../railway-assets-private/game-art-previews/docs/art/chinese-roof-kits-2026-11/revision-1
   ```

   每個模型一個資料夾，near／far／fallback 各七向透明 PNG、GLB、原生檔與離線 viewer。
   每模型最多 21 張 PNG、單張 ≤2MB；不放 ZIP、不建 history。
   新一輪刪掉上一輪同模型的重檔；保留 PNG、README、SOURCE。
   本輪是通用建築配方的獨立比較包，未替換舊整套 kit 的歷史交付。
8. 跑 Swift 6.4 warnings-as-errors 與兩個 kit 測試 class；看上／下／前後／兩側／斜視，
   尤其窗背、屋簷、曲面法線與冷氣貼牆。素材庫提交前跑
   `python3 tools/asset_guard.py --base origin/main`。PR 附總覽與 README；
   第 3 級須遊戲規劃看過總覽才能合併。CI 綠可轉 ready，不等於外觀已接受。
