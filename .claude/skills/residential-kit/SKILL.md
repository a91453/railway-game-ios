---
name: residential-kit
description: 台灣住宅街廓、界牆、庭院設施與四組景的原生 3D 配方、接點和七向透明圖。
---

# ResidentialKit

先讀 `CLAUDE.md`、`.claude/skills/art-style/SKILL.md`、`.claude/skills/station-kit/SKILL.md` 與工作登記 #1579。只在本批新檔延伸；地圖放置、GameCore、存檔、Golden 與既有 Kit 由原負責者處理。

`Map3DResidentialKit.Part` 有 10 種住宅、8 種界牆與出入口、8 種庭院／街邊件；`Example` 有 4 個獨立組景。`Map3DResidentialKit.model(for:)` 按需建置。`Map3DModelPack(residentialKit:)` 預設不把它們加到常駐地圖模型。

內部幾何為 x 向前、y 向上、z 向右；原生檔及接點為 x 向前、y 向左、z 向上，單位公尺。落地物的最低 z=0。`balconyModule` 背板 x=0，必須貼實牆；其樓板和斜撐接到背板。`brickWall`、`tileWall` 的左右接點可接續邊牆。屋頂水塔與太陽能板須放在實體樓板上。窗面背後須有實牆，雙扇玻璃、窗框與背板需分層避免共面閃爍；騎樓和雨棚必須有接地的立柱，屋簷與門框不能懸空。住宅陽台須有接合牆體的樓板及可對應的落地門，太陽能板等斜面件要有可見的厚度與底面。

原始 factory 的路徑、SHA、授權條件與每件改造對照只在私有庫的 `remix-provenance.json`。新批次也先讀私有 `MODEL_CATALOG.json`、`ASSET_LICENSE.txt` 和實際 factory；重新設計輪廓或組件配置，不只換色。不得公開原 factory、原包模型、貼圖或品牌，也不得把私有原始素材送外部生成服務。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/residential-kit/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/residential-kit-2026-10-21
```

沿用 `tools/station-kit/` 的 native、GLB 編碼器與 WebGL renderer。重建會匯出 30 native、30 GLB、210 張 384px 七向透明 PNG，生成分類、組景、下斜視及多底色預覽，並測試格式、SHA、瀏覽器操作與相關 XCTest。所有單件和組景均需低於原生 loader 15,000 三角形。若要重畫，刪除輸出目錄的 `render-cache.json`；既有快取只有 native SHA、renderer SHA 與七張圖片 SHA 全相同才會重用。

人工打開 `previews/parts.png`、三類總覽、`examples.png`、`directions.png`、`undersides.png`、`style-checks.png`，並在 viewer 旋轉檢查窗背、接柱、屋簷、樓板、底面。公開庫只放生成配方、工具、測試、此 skill、單一總覽與小型驗證 JSON；大型模型、完整圖、viewer 與來源對照只放私有庫。

報告明確標 VERIFIED／UNVERIFIED。Chromium WebGL 成功不代表 iPhone Metal、實機效能或遊戲地圖已接入。完整 Swift suite 交 CI。兩庫各開 draft PR，不自行合併。

## 傳統建築（決策669第二輪，以此取代第一輪）

1. 先登記#1579，查照片／參考庫，再定建築類型：現代透天平頂；老透天也平頂、另用老立面變體；兩層老街屋用高牌樓立面＋後方直脊兩坡；一般三合院用硬山兩坡＋馬背。翹角、燕尾留給廟宇，不把所有老房子套同一屋頂。
2. 具名建築：SOURCE記照片URL／作者／日期／授權，至少正面、側面；由門寬或OSM面寬估牆高、開間、屋脊、出簷。OSM從Taiwan全島PBF讀取、記way/relation ID／日期／ODbL。U形外框不能用包圍盒填中庭。透視觀察標誤差、遮蔽處標推估；沒有可靠外框的只做明確示意模型。
3. 照片定比例先列比值，再列遊戲尺寸。例如本輪三峽上層窗高／層高約0.5–0.65，模型1.7/2.95；大溪牌樓冠／層高約0.35–0.65，模型1.85/2.95。迪化街取分格、窗框節奏，不複製店招／花飾。比值是透視估計，誤差約±20%，不是實測。來源逐輪寫進README／SOURCE。
4. 廟宇重用Map3DChineseRoof，kitChineseRoof轉軸、只輸出plain色面。一般住宅用residentialPitchedRoof／residentialHardRoof；residentialHorseback是圓弧封閉山牆，近12弧段、遠6段。馬背新件在residential-kit，不能改台北地標的ChineseRoof／TaipeiPalaces幾何；既有地標測試及逐位元比對要過。
5. 近遠共用主牆色、屋頂種類與極值，遠景只減曲面細分與小零件；modern／old窄透天都不能加翹頂。老立面用磚紅＋淺帶；灰concrete雨遮0.55m出挑、0.06m厚，底邊封閉；冷氣直接重用610的addStub（8三角）。鐵窗、騎樓、水塔、頂加不重做。
6. 新配方明確呼叫model(for:part,far:false/true)；traditional:false才回退。既有單參數API的既有part保持原配方，因為地圖已使用civic-kit，不能藉改kit偷偷改地圖或突破其預算。新part無前版時SOURCE要說明fallback是簡化示意，不能冒稱舊版。地圖接入仍另派。
7. tools/civic-kit/rebuild-roofs.sh（或residential同名入口）輸出私有chinese-roof-kits-2026-11/revision-N。每模型一資料夾，三態×七向透明PNG、GLB、原生與自包含viewer。總覽前三欄近／遠／回退，第四欄用同角度、同公尺相機並排近遠，不各自fit。單張≤2MB、每模型≤21PNG；無ZIP/history。開新輪同PR刪前輪重檔，留PNG／README／SOURCE。
8. 每個新零件列近遠三角形成本；正側殿燕尾每端≤50三角。跑Swift6.4 WAE及兩個kit、Map3DLandmarksTests、Map3DTaipeiLandmarksTests等相關測試；人工看正／側／俯／下及剪影。素材staged tree與HEAD各跑asset_guard。兩PR維持draft，CI綠在#1579交規劃看總覽，看過才ready，不自行合併。
