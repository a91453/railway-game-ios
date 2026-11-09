---
name: civic-kit
description: 公共建築、室內家具、台式廟宇與市場的原生 3D 配方、安裝接點與七向透明圖。
---

# 公共建築、家具、廟宇市場

先讀 CLAUDE.md、art-style、station-kit 與工作登記 #231。只延伸 Map3DCivicKit*.swift、tools/civic-kit、本skill、對應測試及文件；不要改既有車站、地圖放置或商店街。

48件：building12、furniture24、culture12；4個組景。內部 x前/y上/z右；輸出模型與connector是native x前/y左/z上，公尺。Map3DCivicKit.model(for:) 按需建置；Map3DModelPack(civicKit:) 不自動加入常駐standard。

新素材必須改輪廓、比例與組件布局，使用既有霧面色票。私有來源只取建模方法，不能原樣複製factory、模型、貼圖、標誌或文字；來源SHA與改造對照只放私有庫。不得把私有原始資產送外部生成服務。

地面件腳底z=0；wall件背板x=0；ceiling件最高點z=0向下吊掛。寫字桌desktop接點z=.80，先放桌再將桌燈mount對齊desktop。壁鐘、窗簾、投影幕、吸音板必須貼實體牆，不當落地物。天花投影機先有承重橫樑或天花。窗戶附背板，走廊附立柱。屋簷封閉底面與裙邊；不能用大幅抬高掩蓋穿插。廟門紅柱、燕尾屋脊與廟埕為重新組合的遊戲造型，非實測名勝。

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
tools/civic-kit/rebuild.sh /path/to/railway-reference-private/Railway/game-art-previews/docs/art/civic-kit-2026-10-21
```

沿用station-kit的native、GLB、renderer；52模型、364張384px透明圖。Swift6.4 warnings-as-errors；21項指定XCTest、4項既有Node編碼測試；逐頂點native讀回、完整GLB重編、圖片SHA/非空/不裁邊、分類、安裝面、桌面、窗戶背板、預算與決定性都要通過。瀏覽器測試搜尋分類、52模型、七向、旋轉縮放、下載hash、390px排版。快取需native、renderer及每張PNG的SHA全相同。

人工看parts、三類表、examples、directions、undersides、style-checks，檢查腳、背板、吊架、屋簷。公開只放配方／工具／測試／單一總覽／小驗證JSON。大型native、GLB、PNG、viewer與來源對照放私有庫。各開draft PR，不推main、不自行合併。報告VERIFIED／UNVERIFIED；WebGL不等於真機Metal或App已採用。正式採用前仍需來源並排與實機效能、場景碰撞驗證。

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
