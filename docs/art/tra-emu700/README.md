# 臺鐵EMU700：立體鼻罩續修、四角色近遠與完整八車

使用者於2026-11-03明確回覆「他的車頭嘴巴還是很醜」，因此前稿producer `553b3a2207bf87e6d02819d687b673860055a84a` 的車頭外觀**未通過**。撤回先前「沒有已知必須重做外觀故障」的較寬自評。這次實際改幾何與殼面分色；新候選的使用者接受仍UNVERIFIED，不能由作者看圖或CI代替。

真正幾何producer：`cd01a6f906770731874b0b447325052e3afd67f9`。公開／文件head及素材commit另見[公開draft #1730](https://github.com/a91453/railway-game-ios/pull/1730) ↔ [素材draft #45](https://github.com/a91453/railway-assets-private/pull/45)，不回填為幾何producer。

## 修正與來源

上一輪53f264bc候選雖消除了553的階梯色界，作者重新對照實照後確認鼻罩仍偏平、下鼻像直板，撤回外觀可收尾的判斷；使用者同意繼續修正，53並未有使用者接受。本次直接重建橘色罩面中央前凸與下緣收回、低部肩面的環向曲率，以及兩段向內收的薄藍色下裙。近遠橘色曲面與色界完全相同，遠景僅簡化下裙細分。罩面是原生殼的一部分，沒有浮動色片、重殼或照片貼圖。

實看第一版斜視發現縮回下裙後引桿框露到罩外，已將真實引桿框退入罩後0.14m，連結面／車長／assembly位置不變。保留罩後與下方真空腔；以九條正面射線檢查框架遮蔽，修改實際引桿頂點使其前移時必須拒收。
親看來源仍為已下載且固定SHA的實照：實車參考照片，其中DSC07789、DSC07787及2011正斜視；實車參考資料的技術／角色頁另有普通連結器罩及升罩試車照片，後者只供分辨狀態，未套成一般營運。原照、逐張日期／車號／授權／下載檔名／SHA及支持部件見[source-record.json](source-record.json)。照片著作權屬原作者，只在本機合法觀察，沒有發布原照、照片貼圖、第三方幾何、私有來源內部路徑或送外部生成服務。

橘色區中央1.35–1.86m、下燈與鼻罩曲面是有實照支持的模型配適值，**不是透視像素換算出的官方尺寸**。mouth.mjs驗實際原生色界、六個近遠車端、閉罩與空腔、五條曲面剖面及九條引桿遮蔽射線；修改最終真實頂點，分別壓平橘色罩面深度、壓平藍色下裙、前移引桿及移除真鼻罩三角形作故障；不構成完整外觀接受或工程碰撞認證。

[完整素材與自含旋轉縮放下載viewer](https://github.com/a91453/railway-assets-private/tree/codex/tra-emu700-native-2026-11-02/game-art-previews/docs/art/tra-emu700/revision-1)，其中mouth-before-after sheet以同一公尺相機及光線比較上一輪未接受的53候選與本候選；553使用者否定紀錄仍保留；前稿原生SHA與相機固定在mouth-comparison.json。角色sheet是完整單車；車頭細部比較明示為裁切鏡頭，不用它冒充完整單車視圖。

EMC兩個未接受study ID改為`tra-emu700-emc-cab`／`tra-emu700-emc-cab-far`，讓既有遮蔽規則辨識真實駕駛端，不再虛構車頭前方的鄰車。這只改本型ID與自有引用，共用遮蔽不變；舊ID不保留重複別名，各前稿由其真正producer及素材git恢復。

## 身分、批次與代表期

正式型式為臺鐵EMU700通勤交流電聯車，「阿福號」僅作搜尋線索。原廠[日本車輛產品頁](https://www.n-sharyo.co.jp/business/tetsudo/pages/ztaiw_emu700.htm)、[2005採購公告](https://www.n-sharyo.co.jp/business/tetsudo/topics/tp050609.html)及[台灣車輛產品頁](https://www.trsc.com.tw/train/tran-58acf525031f4)支持製造與尺寸。台灣車輛為主契約者、日本車輛設計／技轉、住友商事參與商務／當地化；2007–2008是當時計畫，不等於逐車實際驗收。實車參考資料記前三個四車子單元701–703共12輛日製、704–740共148輛由台灣車輛生產；分供合約及逐組交付／驗收表未取得。東芝牽引／輔助系統、Nabtesco HRA軔機、FAIVELEY CX弓有技術文字或實照圖說，責任細分仍待原廠文件。

台灣車輛頁的ED／EMA／EP／EMB表頭與本型其他角色原文矛盾，沒有直接照抄；採EMC／EP／ET／EM交叉定義，官方完整編組圖仍待補。2007-08-28啟用、翌日營運、2015電軔優先及2016無階化的文字與來源差異均在source-record，不能當逐組驗收日期。

本包為量產一般塗裝、無階化後739+740的**2020歷史代表**。照片可讀EMC740、EM740，其餘號由編組表支持；文章另記2020-10-05的739+740配對運用。沒有同日八號皆可讀照片，也沒有指定列2026營運證據。原型舊黑面、試車、701+702京急彩繪與模型作品排除，不捏造批次鼻形變體。

## 八車、尺度與共用範圍

全列+X端為EMC739：

`45EMC739 / 45EP739 / 40ET739 / 45EM739 | 45EM740 / 40ET740 / 45EP740 / 45EMC740`

EMC為駕駛動力車、EP為受電弓拖車、ET為無障礙廁所拖車、EM為中間動力車，4M4T。前四不轉、後四僅assembly轉180度一次；EP在2／7，弓肘朝本子單元駕駛端。中央為EM–EM半永久連結，非兩個駕駛頭；其獨有設備仍不足，維持已知的簡化端門／風擋及連結器，不捏造專屬寬度。

原生公尺，單元+X朝本子單元駕駛端、+Y左、+Z上、軌面Z0。EMC連結面距20.743m、其他20.3m，名義全列163.286m；殼端退讓產生間距，不另加展示縫，也不平均車長。正式車寬來源2.889／2.890m，採2.889；車頂3.7m，AC約3.95m，升弓包絡另列，不能混為殼高。台車中心距14.3m、軸距2.3m、新輪0.86m／磨耗0.78m、軌距1.067m；原點對稱配置軸位±8.3／±6m與輪心Z0.43m，端部絕對站位仍為假設。完整配置／bounds見configuration.json及素材manifest。

| 部件 | 共用／獨立／未知 |
|---|---|
| Primitive與轉軸 | 沿用StationKitBuilder.box／beam、Model.flat及已記錄的構面／clip方法；原producer與範圍見source-record；無他EMU整殼 |
| EMC嘴形／下鼻／鼻罩 | 本型獨立立體殼面；53作者重審不合格，553被使用者否定；本候選外觀接受未驗 |
| 其餘EMC門窗、輪組、設備 | 原本EMU700配方接續；嘴形之外不任意改位置或車型 |
| EP／ET／EM各近遠 | 六單元對53前稿逐bytes保護，且與553相同，角色門窗與受電弓保持 |
| 台車／車底／屋頂設備 | 主要設備有實照支持但合理簡化；隱藏BOM、正交屋頂與完整管路未知 |
| 中央特殊件與近期同列 | 資料不足，未宣稱已證實 |

單車共同固定20.8m框、全列163.286m框，相同相機／光線；車頭細部另用固定公尺裁切鏡頭並明示。互動viewer逐項auto-fit只供檢視，不能拿來定量比較。夜景為靜態未啟動燈具，非營運頭尾燈驗收。

## 重建、驗證與選用

先fetch本分支，在明確producer的兩個checkout執行（Swift6.4、Node≥22、既有Chromium/Playwright、Python/Pillow、Blender）：

```sh
git worktree add --detach /tmp/emu700-before-src 53f264bc2410449e3af15b07d0a2c9aaffa68455
git worktree add --detach /tmp/emu700-candidate-src cd01a6f906770731874b0b447325052e3afd67f9
cd /tmp/emu700-before-src
tools/train-models/run.sh /tmp/emu700-before-run --ids tra-emu700-emc-cab,tra-emu700-emc-cab-far
cd /tmp/emu700-candidate-src
pwd
git rev-parse HEAD
tools/tra-emu700/build.sh /tmp/emu700-candidate-run
node tools/tra-emu700/render.mjs /tmp/emu700-candidate-run
node tools/tra-emu700/render-mouth.mjs /tmp/emu700-candidate-run /tmp/emu700-before-run
python3 tools/tra-emu700/sheets.py /tmp/emu700-candidate-run
```

其餘命令見validation-commands.md；結果見verification.json、producer-verification.json、preservation.json、visual-review.json與素材mouth／duplicate報告。真實頂點／連通固體／assembly故障不以標籤或toy fixture代替。射線與同位同向面檢查有明列覆蓋範圍，不宣稱完整自交／工程碰撞或動態證明。

上游main `efb96529`已獨立merge；相較82e5e894僅TestFlight說明文件、runtime來源不變（未啟動TestFlight）。海風／山嵐配方與營運接入保留；其新增或修正不算本輪。保護以未改該main的實際standard+studies完整inventory為基線，含未入鎖者，逐native bytes／十欄FNV及既有索引比對；本型仍僅studies，standard增量0。不改GameCore、存檔、fixtures、班表、購車／解鎖、動畫、控制、共用palette／loader／格式／gate。

實際選用仍僅studies；現有配車沒有可靠EMU700型式／角色／方向契約，合併後不自動替換營運列車。詳細路徑及缺口見integration.json。四態仍UNVERIFIED：技術分項有報告，但file://受管理政策阻擋；沒有本候選使用者接受；營運未接入；本車Simulator外觀／裝置Metal／效能／動態未驗。Safari／Firefox未驗。指定2026同列、逐組驗收時序、正交屋頂、完整車底BOM、中央特殊件、精確端部軸位仍缺。

完整包私庫11張PNG加公開1張總覽，共12張；同一revision-1取代前稿重檔，不新增ZIP／history／backup。原始前稿由git與producer恢復。自含viewer不壓縮，單檔仍≤50MiB；PNG≤2MiB、素材PR≤200MiB。原創配方／原生／GLB與文件依公開庫LICENSE.md，Copyright © 2026 a91453，著作權所有；原照維持原作者權利。
