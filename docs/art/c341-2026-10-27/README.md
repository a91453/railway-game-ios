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
