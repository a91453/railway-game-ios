# EMU3000 第五版：保留側面，修正正面變形

[Issue #1226](https://github.com/a91453/railway-game-ios/issues/1226) · [公開 draft #1229](https://github.com/a91453/railway-game-ios/pull/1229) ↔ [私有 draft #77](https://github.com/a91453/railway-reference-private/pull/77)。實際 producer、私庫提交及最新同 head CI 分別記在 PR／issue。使用者明確表示第四版「側面對了、正面大變形」；第四版原先正面已符合的自評撤回。本頁是第五版製作方自檢，不代表使用者接受。

![最終實際原生模型](overview.png)

只修改端車前艙橫向截面、黑罩分色、風擋／燈罩及雨刷貼合。暖白車身、炭黑罩、細綠松肩線保持；沒有把側面插畫硬拉成立體或加裝飾蓋偏差。真正第四版 producer `4b6352d8f3bb27b6ff312e7d375ad8da124eea41`／private `7dfa636acf43575012720b7daf46ae66b1b66acb` 完整 `revision-4` 不動，新包為 `revision-5`，另保存真實原生 history/4b6352d8。

本 PR 含營運近／遠景替換接點，未合併不改 main／已安裝 App；合併後使用新 set 的列車才顯示。私包為靜態幾何，App 不讀私有 GLB，門／輪／弓沒有動畫。Claude 的列車包解鎖與 classic 回退分派保持；不覆蓋 #1227 共用 builder／#1233 舊車清單。

## 參考與特徵

已讀 AGENTS、CLAUDE、HANDOFF、art-style、diagnosing-bugs、跨 AI 原生車輛手冊與工具 README；fetch 最新遠端／工作登記，續用自己的 codex/ 分支與獨立 worktree。原 base public85d9aa35／private81e935fd；700T、E200、N700S-G 及其他模型保持。

| 類別 | 本輪特徵／保持內容 | 資料缺口 |
|---|---|---|
| 單體／編組 | ED 頭尾、12節6M6T、六EM／一ET／三EP，弓3/7/10 | 非12節僅遊戲排列 |
| 側面 | 保留已符合的圓隆艙頂、連續下降斜鼻、短圓下角及門窗 X／高度位置 | 原生實際殼面切101平面比前版，非工程尺寸 |
| 正面 | 上寬下收的連續圓U罩、白色兩肩／下巴，縮窄正視側窗投影，圓形燈 | 新 ED 正面示意＋日立實車照片；工程橫斷面仍不足 |
| 俯／斜 | 鼻肩較飽滿、上部轉角圓收；避免頭燈隨角度參數拉成長條 | 比例推估，不說圖片像素是工程尺寸 |
| 頭尾／左右 | 尾單元實際180°、只兩個下紅標示燈，中間車無駕駛窗／燈 | 未取得另一側精確設備配置 |
| 相對尺寸 | pitch ED21.35m／其餘20.3m、寬2.91m、全列245.7m、軌距1.067m | 維基／私有catalog次級資料；操作手冊原PDF未取得 |
| 高度 | 殼身3.49m、端車圓頂約3.68m、設備最高bounds保持 | 虛擬模型量測／比例推估；原資料高度定義歧義未解 |
| 門窗／設備 | 先前修好的薄門縫與實體玻璃保持；側窗按新截面貼合；中間設備全同 | 乘務門輪廓位置保持，側向投影隨真正曲面變化 |
| 走行 | 每節兩架各兩軸、8輪胎貼軌，輪架／下設備／連結器payload保持 | 隱藏動力、輪徑／軸距與弓接觸高度為估計 |

原10張圖、前輪各新ED／EM側圖與本輪兩張重附 ED 正面（D3732175、DBF082D8）均實際打開。新圖為 K.Y.Chung／Nanyue Express 插畫局部，原標 CC BY-NC-ND4.0；只觀察結構與輪廓，不自動描線／取像素／重散布。日立 img_03 是實車正面，img_02 是設計視覺圖，不混稱照片。原圖／mesh／貼圖／品牌字不公開、不隨包散布、不送外部生成服務。

來源：[日立設計](https://www.hitachi.co.jp/rd/research/design/product/taiwan_tra/index.html)、[維基EMU3000](https://zh.wikipedia.org/wiki/台鐵EMU3000型電聯車)、私庫 Railway/taiwan-rail-reference-clean/source/memories/tainan-2026-10-16/fleet/catalog.json。手冊索引讀到但原PDF未取得；猜測 TrainCollection URL404不當證據。每張參考的 SHA／尺寸／查看用途列私包 reference-review.json。既有已接受車只比較色票／霧面／細節密度；沒有複製其車體、底盤、車頭、門窗或編組，沒有新增依賴／外部模型程式碼。

## 幾何修正與外觀

第四版的正面問題是側窗正視露出過寬、燈罩經角度參數映射後拉長、黑罩下緣在粗三角內變成折角。第五版保持各縱向截面的上／下高度與鼻長，獨立調橫向寬度及上肩圓收。黑罩直接以凸圓弧半平面切入實際殼面三角，跨三角傳遞切點，避免 T 接縫／重疊片；分色不改殼面的側面包絡。

風擋／燈座在正面實體座標定義，再切進真正朝前殼三角並沿X做封閉薄實體；遠景也不拿大面跨凸殼，防止玻璃被殼蓋住。圓燈在實際前平面保留合理寬高；雨刷有支點，鼻縫仍投到真實車殼。原門葉以白殼作葉面，門縫／玻璃分段貼合，沒有恢復厚灰框或外掛門板。

| 檢查項 | 本版外觀結論 | 證據／限制 |
|---|---|---|
| 已符合的側面輪廓 | 已符合保持目標 | 真第四版同相機／公尺尺度，實際殼101切面上下包絡差小於20微米 |
| 正面黑罩／肩部／白下巴 | 已符合本輪製作方修正目標 | 最終原生正／側／上／斜配色、白模與剪影皆查看；不是作者認可 |
| 風擋／圓燈／側窗投影 | 已符合本輪修正目標 | 原生正面及近遠LOD；玻璃射線另列技術證據，不取代看圖 |
| 車門完整／薄縫、中間車／走行保持 | 已符合保持目標 | 16單元射線／七向，12中間payload全同，走行設備保持 |
| 毫米級工程截面、背面設備／另一側 | 資料不足 | 不捏造相似度分數／工程復刻或使用者接受 |
| Metal／真機效能、門輪弓動畫 | UNVERIFIED | Linux WebGL不代表真機／效能／動畫 |

真前後在 previews/revision-4-vs-5.png，車頭局部 chin-before-after.png，同相機／公尺尺度；style-comparison.png 只比較已接受車風格。main85d9aa35 的原模型及舊20m pitch／19.4m顯示縮放另存，不能冒充舊App截圖。history/first-pass 是真正未提交初稿，不當作Git發版或已接受版本。

## 單元與接入

真實12節 ED1–EM1–EP1–EM2–ET1–EM3–EP2–EM4–EM5–EP3–EM6–ED2，素材 ed–em–ep3–em–et–em6–ep7–em–em–ep10–em–tail。ED10暗主窗、EM／ET13、EP3為12、EM6兩留白後10暗、EP7一服務留白後11暗、EP10為13。非12節保留1–16選擇，但不是認證真短編組；背景TRA的EMU800分類不改。

公尺 +X前/+Y左/+Z上，輪底0；helper x前/y上/z右經flat只轉一次，GLB(x,z,-y)。8角色各近遠合法M3DM v1／GLB；完整編組為自含合法單元 M3DAssembly JSON／GLB，不造超過15,000三角上限的單件原生檔。尾車已轉180°，組裝只平移；translation／gap／共同基準／實際bounds與三角看manifest。

近景頭尾8962、整列74676，遠景頭尾3834、整列33716三角；較第四版整列約增加0.8%／1.8%，來自圓弧分色與真正貼合殼面的風擋，12中間單元不增加。專用近／遠上限調為9200／4000，不提高410共用2k／4k預算；500m切遠景、900m後原盒形。未宣稱真機成本已驗。GameCore每節20.3m與顯示全列245.7m的2.1m總差保持原交接限制。

## 技術驗證與交接

[工具與重建命令](../../../tools/emu3000-refresh/README.md)。模型變更後全量重新輸出／看圖；程式、模型、PNG、viewer、ZIP同一實際已提交producer，bundle逐檔與git show核對。CI記錄查詢時間與同head，不借前版綠燈。

- VERIFIED／Linux Swift6.4 warnings-as-errors及相關測試；圓燈回歸在真第四版先紅4項，修後綠。測實際模型投影，不只核配方常數；原車門遮擋／埋玻璃、近遠GameWorld→TrainMotion→frame及原節數維持。
- VERIFIED／原生讀回、法線、封閉有向邊、正體積、原生GLB同幾何、Swift／JS組裝逐bytes，拒收缺面／反面／偏移組裝變異。
- VERIFIED／近遠頭尾風擋正面射線，排除真正薄雨刷的預期遮擋；把實際連通風擋埋入120mm必須拒收，圓燈依實際發光連通體投影寬高檢查。
- VERIFIED／16單元車門射線、實際玻璃背襯／8輪胎貼軌淨空／屋頂取樣支持；浮玻璃／升輪拒收。101側包絡切片保持、端車只改x≥6.2、走行／總bounds不變、12中間及168既有非EMU模型payload全同。
- VERIFIED／獨立Blender GLB匯入、168七向透明PNG及全部PNG完整解碼不裁邊，24件viewer載入／旋轉／縮放／原生GLBPNGZIP實際下載比SHA，ZIP全解壓逐bytes。
- UNVERIFIED／真機Metal、FPS/GPU/記憶體、動畫、完整表面動態碰撞、真接觸網、工程內構與另一側、file://直接導覽。離線以同HTML setContent實測。

完整包在私庫 Railway/game-art-previews/docs/art/emu3000-refresh-2026-10-25/revision-5/：原生／GLB／七向／單元／編組／白模剪影／同尺度風格與真前後／viewer／來源／SHA／ZIP／verification。公開只放配方、必要接點、工具、測試、文件與這一張總覽。Mac／實機接續查LOD、彎道、雙向、門邊及成本；不覆蓋別人的列車包或classic清單。GameCore／存檔／golden／save／replay／玩法不動，不推main／合併／auto-merge／TestFlight。
