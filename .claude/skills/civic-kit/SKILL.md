---
name: civic-kit
description: 公共建築、室內家具、台式廟宇與市場的原生 3D 配方、安裝接點與七向透明圖。
---

# 公共建築、家具、廟宇市場

先讀 CLAUDE.md、art-style、station-kit 與工作登記 #1579。只延伸 Map3DCivicKit*.swift、tools/civic-kit、本skill、對應測試及文件；不要改既有車站、地圖放置或商店街。

**看圖再改**：測試全過不算做完。新做或重做模型時照 [model-look](../model-look/SKILL.md)：先有真實照片，用遊戲鏡頭的角度與大小拍圖、對清單找毛病、改，至少三輪，最後交一張總覽圖給作者或另一個 session 判。

48件：building12、furniture24、culture12；4個組景。內部 x前/y上/z右；輸出模型與connector是native x前/y左/z上，公尺。Map3DCivicKit.model(for:) 按需建置；Map3DModelPack(civicKit:) 不自動加入常駐standard。

新素材必須改輪廓、比例與組件布局，使用既有霧面色票。私有來源只取建模方法，不能原樣複製factory、模型、貼圖、標誌或文字；來源SHA與改造對照只放私有庫。不得把私有原始資產送外部生成服務。

地面件腳底z=0；wall件背板x=0；ceiling件最高點z=0向下吊掛。寫字桌desktop接點z=.80，先放桌再將桌燈mount對齊desktop。壁鐘、窗簾、投影幕、吸音板必須貼實體牆，不當落地物。天花投影機先有承重橫樑或天花。窗戶附背板，走廊附立柱。屋簷封閉底面與裙邊；不能用大幅抬高掩蓋穿插。廟門紅柱、燕尾屋脊與廟埕為重新組合的遊戲造型，非實測名勝。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/civic-kit/rebuild.sh /path/to/railway-assets-private/game-art-previews/docs/art/civic-kit-2026-10-21
```

沿用station-kit的native、GLB、renderer；52模型、364張384px透明圖。Swift6.4 warnings-as-errors；相關kit／原生格式XCTest、4項既有Node編碼測試；逐頂點native讀回、完整GLB重編、圖片SHA/非空/不裁邊、分類、安裝面、桌面、窗戶背板、預算與決定性都要通過。瀏覽器測試搜尋分類、52模型、七向、旋轉縮放、下載hash、390px排版。快取需native、renderer及每張PNG的SHA全相同。

人工看parts、三類表、examples、directions、undersides、style-checks，檢查腳、背板、吊架、屋簷。公開只放配方／工具／測試／單一總覽／小驗證JSON。大型native、GLB、PNG、viewer與來源對照放私有庫。各開draft PR，不推main、不自行合併。報告VERIFIED／UNVERIFIED；WebGL不等於真機Metal或App已採用。正式採用前仍需來源並排與實機效能、場景碰撞驗證。

## 傳統建築（決策669第二輪，以此取代第一輪）

1. 先登記#1579，查照片／參考庫，再定建築類型：現代透天平頂；老透天也平頂、另用老立面變體；兩層老街屋用高牌樓立面＋後方直脊兩坡；一般三合院用硬山兩坡＋馬背。翹角、燕尾留給廟宇，不把所有老房子套同一屋頂。
2. 具名建築：SOURCE記照片URL／作者／日期／授權，至少正面、側面；由門寬或OSM面寬估牆高、開間、屋脊、出簷。OSM從Taiwan全島PBF讀取、記way/relation ID／日期／ODbL。U形外框不能用包圍盒填中庭。透視觀察標誤差、遮蔽處標推估；沒有可靠外框的只做明確示意模型。
3. 照片定比例先列比值，再列遊戲尺寸。例如本輪三峽上層窗高／層高約0.5–0.65，模型1.7/2.95；大溪牌樓冠／層高約0.35–0.65，模型1.85/2.95。迪化街取分格、窗框節奏，不複製店招／花飾。比值是透視估計，誤差約±20%，不是實測。來源逐輪寫進README／SOURCE。
4. 廟宇重用Map3DChineseRoof，kitChineseRoof轉軸、只輸出plain色面。一般住宅用residentialPitchedRoof／residentialHardRoof；residentialHorseback是圓弧封閉山牆，近12弧段、遠6段。馬背新件在residential-kit，不能改台北地標的ChineseRoof／TaipeiPalaces幾何；既有地標測試及逐位元比對要過。
5. 近遠共用主牆色、屋頂種類與極值，遠景只減曲面細分與小零件；modern／old窄透天都不能加翹頂。老立面用磚紅＋淺帶；灰concrete雨遮0.55m出挑、0.06m厚，底邊封閉；冷氣直接重用610的addStub（8三角）。鐵窗、騎樓、水塔、頂加不重做。
6. 新配方明確呼叫model(for:part,far:false/true)；traditional:false才回退。既有單參數API的既有part保持原配方，因為地圖已使用civic-kit，不能藉改kit偷偷改地圖或突破其預算。新part無前版時SOURCE要說明fallback是簡化示意，不能冒稱舊版。地圖接入仍另派。
7. tools/civic-kit/rebuild-roofs.sh（或residential同名入口）輸出私有chinese-roof-kits-2026-11/revision-N。每模型一資料夾，三態×七向透明PNG、GLB、原生與自包含viewer。總覽前三欄近／遠／回退，第四欄用同角度、同公尺相機並排近遠，不各自fit。單張≤2MB、每模型≤21PNG；無ZIP/history。開新輪同PR刪前輪重檔，留PNG／README／SOURCE。
8. 每個新零件列近遠三角形成本；正側殿燕尾每端≤50三角。跑Swift6.4 WAE及兩個kit、Map3DLandmarksTests、Map3DTaipeiLandmarksTests等相關測試；人工看正／側／俯／下及剪影。素材staged tree與HEAD各跑asset_guard。兩PR維持draft，CI綠在#1579交規劃看總覽，看過才ready，不自行合併。
