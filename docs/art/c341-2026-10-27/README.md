# C341 原生靜態素材

本案依四張使用者附圖獨立製作；不沿用 EMU500 或其他列車車殼、車頭、門窗與底盤。共用 StationKit 基本幾何與原生序列化／渲染工具。尚無 C341 專用營運接點，`metroC381` 是泛用代表，因此本次僅靜態素材註冊與六輛場景展示，合併不會自動換用營運車輛。GameCore／存檔／fixtures／玩法不改。

## 建模前特徵與缺口

|項目|判讀與實作依據|
|---|---|
|名稱與使用|Siemens C341，板南線；Blair Yu 341型電聯車文字記36輛／6列，支持六輛。未取得官方工程文件，不把二手文字稱官方核定|
|單元與朝向|附圖4列DM/T/M；展示暫採DM-T-M-M-T-DM。兩端向外，後DM已原生轉180°；精確單元設備與成組方向仍需工程編組表核定|
|曲線|附件1–3：短直立端面、微傾雙風擋、中央逃生門、圓肩低弧頂；俯視只短距離內收，不做長鼻|
|分色|暖白與現有低彩藍腰帶；前端腰帶穿過雙圓燈座，窗罩藏青；無logo、廣告、真實車號與路線識別|
|門窗|附圖4支持每側四組雙門、三組成對獨立客窗與端窗；窄門窗、薄中縫與膠條；中車不留駕駛玻璃／燈|
|設備|兩架各兩軸、輪底Z=0。低車頂格柵與車底箱體比例補全；無架空集電弓，第三軌受電細部未知|
|左右頭尾|前／尾同型相反朝向。左右門窗對稱屬補全；隱藏側設備、受電靴位置、改造年代不能確認|
|尺寸|殼長23.10m、節距23.50m、寬3.18m、頂3.66m、台車中心距15.6m、軸距2.1m、輪徑0.84m、輪心橫距1.50m均為**比例推估**，非工程尺寸。輪心距不等於軌距，軌距仍未取得本型官方來源。設備頂3.772m。不得混稱連結面距／全車長|
|預算|單元目標≤2500三角，六輛目標≤15000；超限不得存單一M3DM，須改合法組裝交付|

## 附件逐圖

全部在本次訊息直接實際查看；原始本機檔與SHA未提供，不捏造。

1. 640×480，車站前斜視。雙風擋／中央逃生門／藍腰帶與圓燈，車底暗、月台遮擋右側；支持前端分區，不支持工程尺寸／完整門數。左上浮水印「2427junction」，作者未核定。
2. 1280×720，彎道略俯前斜視；可看肩弧、車頂格柵與門窗節奏，列車彎曲遮擋後段。圖中文字標C341，非工程圖；作者未知，不能只以標題確認所有後段單元。
3. 500×375，站台前斜近照；白肩包覆、中央門縫、窄駕駛側門及圓燈清楚，輪組／車頂遮擋。作者與年代未知；不支持另一側。
4. 766×400，DM/T/M左右側示意與小正面。K.Y.Chung／Nanyue Express，圖上CC BY-NC-ND 4.0。僅作門窗數與角色判讀，不複製圖素、不修改／重發布原圖，不當工程比例或攝影證據。

## 網路補查

存取日2026-10-27。只以文字與公開網址查詢，未將任何私有資料送反向搜尋或生成服務。

- https://blair-bus.blogspot.com/2011/03/341.html ，《341型電聯車》，Blair Yu，2013-08-16。文章與DSC00082.JPG外觀原圖實際開啟（640×360）；攝影記2013-08-16永春站，支持板南線C341低位圓燈／中央門／尾端標誌燈及36輛6列文字，不能支持完整屋頂／車底、工程尺寸或全部編組順序。照片標All Rights Reserved，僅暫存本機判讀，不隨包分發。照片URL與限制詳私庫source record。
- 原廠／官方優先搜尋：Google文字搜尋回傳JS跳轉頁、DuckDuckGo驗證頁、Bing本次回傳無關FedExForum結果，未當可用證據。metro.taipei/cp.aspx?n=AB56163F23A4076B 為404，不能支持尺寸。Wikipedia臺北／台北不同標題遇403或空條目，未當規格證據；train-collection候選URL代理403，未讀取，不推定內容。
- 私庫 `Railway/taiwan-rail-reference-clean/source/rail-3d/assets/garage-blender-v1/c341.json`：Q比例長10.208m、engineeringDimensionsM=null、單車示意；只沿用其公開照片來源線索，不採尺寸、編組或mesh。私庫原模型未作為已查看實車證據。

## 重建

Swift6.4，Node、Playwright/Chromium、Python/NumPy/Pillow、Blender。工具僅使用本機，不新增遊戲依賴。

```sh
PATH=/workspace/swift/usr/bin:$PATH swift build --build-tests -Xswiftc -warnings-as-errors -j 4
PATH=/workspace/swift/usr/bin:$PATH swift test --skip-build --filter 'Map3DC341Tests|Map3DModelFileTests|Map3DModelTests|Map3DBusesTests'
PATH=/workspace/swift/usr/bin:$PATH tools/c341/export.sh OUT
node tools/c341/render.mjs OUT
node tools/c341/clay.mjs OUT
python tools/c341/geometry-audit.py OUT
python tools/c341/support-audit.py OUT
node tools/c341/verify.mjs OUT
blender -b --python tools/c341/glb-audit.py -- OUT
python tools/c341/verify-png.py OUT
node tools/c341/standalone.mjs OUT
python tools/c341/bundle.py OUT PRODUCER_COMMIT
node tools/c341/browser-check.mjs OUT
```

實際最終結果與私有入口完成後補。Linux靜態渲染不代表真機Metal／效能／動畫／完整碰撞；未知設備需官方圖再核。使用者未認可任何本輪版本，不聲稱相似度。

## 最終交付與接手

素材 producer `91442833`（完整 SHA 見私包 source-record）；後續文件提交不改配方。公開 draft [#1323](https://github.com/a91453/railway-game-ios/pull/1323)、追蹤 [#1322](https://github.com/a91453/railway-game-ios/issues/1322)。

[私庫完整入口](https://github.com/a91453/railway-reference-private/tree/codex/c341-native-2026-10-27/Railway/game-art-previews/docs/art/c341-native-2026-10-27)：final 提供四獨立單元、六輛原生組裝／GLB、42張七向透明圖（含風格比較車）、白模／剪影、同尺度風格比較、真前後、viewer、ZIP、來源／SHA。revision-1/2/3 保留真正原生、GLB、配方、producer、預覽與完整ZIP；依本次明確要求優先於預設清理規則。原照片不隨包分發。

|單元|三角|編組中心X（m）|組裝旋轉|實際bounds（m，約）|
|---|---:|---|---|---|
|c341-dm|3894|58.75|0°|(-11.85,-1.626,0)～(11.77,1.626,3.712)|
|c341-t|3306|35.25、-35.25|0°|(-11.85,-1.626,0)～(11.85,1.626,3.712)|
|c341-m|3318|11.75、-11.75|0°|同T|
|c341-rear|3894|-58.75|0°，模型內已轉180°|(-11.77,-1.626,0)～(11.85,1.626,3.712)|
|完整六輛|21036|依上表|不再轉尾車|(-70.52,-1.626,0)～(70.52,1.626,3.712)|

全列超過15,000三角，使用專案既有工具 M3DAssembly v1 合法獨立M3DM組裝，**不輸出超限的單一M3DM**。此scene是素材工具契約，遊戲Map3DModelFile只讀單元，沒有新增App scene載入器。四單元註冊在route bus前，scene展示由工具生成，不註冊超限全列。車殼長23.10m、中心距23.50m、殼隙0.40m；內端風琴約至±11.7375m，約25mm接縫；連結器簡化為共享接合體，±11.75m是配對基準，端部幾何有示意重疊，不作動態碰撞。共同軌面Z=0。

外觀自檢：已符合本次遊戲化方向的圓肩短端面、拱形黑罩／雙窗與中央門、四雙門／成對獨立窗、腰帶連續、雙圓燈與上角標示燈；後DM低位光色獨立改為既有暖紅色票。仍有低面數分面、雨刷／門機／車底受電裝置簡化，不能當工程復刻。資料不足：官方長度定義／台車尺寸／完整頂底設備／左右差異／工程編組方向／改造年代。使用者未接受任何本輪造型，沒有相似度分數。

技術結果、實際同head CI與衝突狀態以issue最新留言及私包verification為準。組裝原生payload逐bytes核對Swift期望、全頂點顏色／法線核對；Float32長列平移使重算法線分量最大差約0.000353，容差0.0005，位置與顏色仍嚴格按組裝期望核對，不用此容差放過反面或缺面。幾何封閉／正體積、玻璃支承及可見性、燈背襯、輪底／移位等故障反例均分開驗證，非完整碰撞。

Linux WebGL2與Blender不代表真機Metal／效能／動畫已驗。直接file://開啟自含HTML被環境ERR_BLOCKED_BY_CLIENT阻擋；相同HTML經loopback已實測載入與下載，直接檔案啟動仍UNVERIFIED。兩庫只推自己的分支、不合併／auto-merge／TestFlight。
