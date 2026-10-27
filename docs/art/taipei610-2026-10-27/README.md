# 台北捷運610 — 環狀線第一階段

Issue #1359，使用者指定名稱「台北捷運610」。白車頭正常塗裝，排除黃車頭公共藝術像素塗裝、渲染候選與未來擴建車。未經使用者接受。

建模前已讀官方《環狀線(第一階段)電聯車海外訓練報告》（臺北捷運，2019-03，2018受訓）[資料入口](https://data.taipei/dataset/detail?id=cf9e4089-ff3d-4ee4-b9f1-4215517f4b06)。PDF 002頁8/實體頁5為TC1-D3503外裝縮圖，列A–C–D–B與68.4m；PDF003頁19/投影片16確認2.65m、4節、750VDC第三軌。PDF003投影片38列彈性輪使用範圍710–660mm，本模型選710mm新輪。002實體頁33/39說明轉向架與Mersen集電器。原文件及附件均只在私庫，不公開圖素。

廠商HRI（日立軌道義大利，前AnsaldoBreda）與台灣車輛；17列68輛、2020開始營運。A/B兩端有操作台但採無人駕駛，本模型不添加傳統乘務門／獨立駕駛室側窗。四輛全部動力車；A/B有空壓機、C/D沒有。三雙扇客門／側、門間兩大窗、雙空調、第三軌集電靴。工程資料未完整公開左右管線／C-D設備站位，模型補全明標推估。

尺寸分類：官方圖端17.45m、中16.76m、全列68.4m為四捨五入值，不能把相加差異抹掉；本模型中心25.4775/8.38/-8.38/-25.4775m、端殼16.955m、中殼16.26m為造型推估，並非工程殼長。寬2.65m為官方，3.60m為二手規格，模型設備最高3.612m與車殼3.42m需區分；輪徑0.710m為官方範圍選值，軸距1.80m、轉向架中心端11.44m／中11.20m仍為照片比例推估。沒有現場實測或工程精度宣稱。

色票讀自Map3DPalette：concreteWalls[2]柔灰D3D4DA車體、[0]C9CCD5屋頂、player暖黃FFC86B識別邊與腰帶、playerRim藏青262C57罩面、glazing shade0.62玻璃、既有2B2E34橡膠與機械、tankStand設備、tunnelLamp燈。無紅色、綠松、品牌、車號或目的地文字。改色不保證免侵權。

目前沒有同車型獨立原生前版。私庫舊y100及公開fourCarMetro均須與實際610比例／配置分開，不作本型前版。公開配方獨立，不搬用EMU800/900、C341車殼／門窗站位；只用StationKitBuilder通用幾何與既有匯出工具。

營運查核：Map3DRealTrains的trtc BR/Y共用wenhu；一般L與fourCarMetro亦非610獨占接點。故本批只靜態註冊，**尚未接入營運，合併沒有營運列車自動換用**。不改GameCore、列車包、解鎖、fallback與其他模型。

外觀自檢、使用者接受、技術、CI、營運、人工Simulator及真機分開；最終記錄與PR連結於收尾補上。

接手私庫 `garage-blender-v1/y100.json` 明列Q-proportions、9.208m長／2.881m寬、51418三角；已查看其預覽，與官方17.45m端車及2.65m寬不符，不能冒稱本型正確原生殼；無可沿用車殼幾何。舊模型只留私庫作來源比較，不輸出假前版。E1000私庫#88的merge落在PP分支，接手main不是其祖先，不能宣稱main已有該包；本次不動原分支與內容。完整landing-audit在私包。

## 第一版驗收與限制（歷史；支承廣義自評已由第二版撤回）

外觀已實看各角色／完整四輛、近遠light七向，並查看四向配色／白模／剪影、門窗／輪組／集電與屋頂detail crop、已接受E500v3／EMU3000v5同公尺尺度比較。初版車門上白框過多、風擋上深色冠面不足已改；後續玻璃背襯的曲面端蓋方向錯誤被有向邊驗證抓到並修正。沒有同車型獨立原生前版；`before-operation-wenhu`從接手base真payload取得，明標接入前顯示，絕非610前版。

已符合（外觀自檢）：三雙門與兩門間雙主窗、無人駕駛觀景端、黃色U邊／腰帶與深色窗帶、雙空調、四車A-C-D-B、尾車一次反向、集電靴及支承、輪底貼軌，近遠保持主辨識。
仍有簡化：頭燈採分面橢圓燈座，車頭與下裙分面感、轉向架／軟管與集電器細節低於實車；內裝／機械運動未製作。資料不足：完整左右隱藏設備與工程站位、天線配置、軸距與轉向架中心工程圖、端殼和連結面長的精確定義。C/D補全箱體屬推估，不冒稱查證左右設備對稱。

技術：Linux Swift6.4 warnings-as-errors；2項專用XCTest通過。記憶體報告首次依契約skipped，之後設MOTION_BUDGET_REPORT=1實跑通過：385模型159.7MB、街景三緩衝0.6MB、台北384chunks場景143.9MB（CPU幾何帳，非Metal／FPS）。最新376份既有payload（373註冊＋3直接比較；初始374份查核亦保留）的完整位置／法線／顏色／layer保持；FNV亦含UV。原生讀回、有向封閉、正體積、退化面、刪面／反面、Swift與JS編組逐bytes、移車、玻璃真連通體埋入／浮起、輪胎與設備靜態接觸均另有私有證據。取樣不冒稱完整動態碰撞。

近/遠/light：A/B 3590/1662/1578，C/D 2824/1372/1252；四輛12828/6068/5660三角。每個遠景小於近景一半。M3DAssembly嵌入最終角色，不加共用預算；靜態註冊12單元，不改任何營運接點。

Viewer支援角色與方向、拖曳旋轉、縮放及PNG／GLB／原生下載；資料夾HTTP與自含HTML切斷瀏覽器網路後都實測。環境Chromium管理政策阻擋file://，直接檔案開啟未驗，請用`python3 -m http.server 8000`開`http://localhost:8000/viewer.html`，或同方式開自含viewer。不繞過該政策。

使用者接受：**未接受**。最新整合head CI：見公開draft實際checks，不以本機通過取代。人工Simulator外觀、真機Metal／效能／動畫：**UNVERIFIED**。本次沒有營運自動換用，不合併／auto-merge／TestFlight。

最終支承修正：輪頂新增每輪9個真輪冠樣點，以首命中朝向拒絕樣點埋入不透明框架；真候選6會在(-6.72,0.71,0.675)m失敗。收窄框架、外移軸箱／支架，補真軸承承托與次懸吊、空壓機／連結器支承；雨刷按實際鼻面貼合並加支點。外觀射線只排除實際薄橡膠雨刷／支點三角（鼻端、z1.75–2.40m、橫向<0.60m），不以寬鬆玻璃例外遮掩遮擋。屋頂／車下／集電設備皆取實際三角接觸距離，容差65mm、每實體最多40點；仍不等於全表面或動態碰撞。

完整模型含端部連結器的實際bounds長約68.69m，與官方四捨五入全列68.4m不同；模型端部伸出量／連結面定義為比例推估，不宣稱精確工程復刻。逐角色與全列bounds以最終manifest為準。

## 最終交付入口

[公開draft #1362](https://github.com/a91453/railway-game-ios/pull/1362) ↔ [私有draft #109](https://github.com/a91453/railway-reference-private/pull/109)。[完整交付／來源索引](https://github.com/a91453/railway-reference-private/tree/codex/taipei610-native-2026-10-27/Railway/game-art-previews/docs/art/taipei610-2026-10-27)。[固定producer ba9ef3e4](https://github.com/a91453/railway-game-ios/commit/ba9ef3e443114b182171671ea34affdbf57d01ed)；本文件／總覽整合head看PR最新commit，不混稱producer。

[最終ZIP遠端下載證據](https://github.com/a91453/railway-reference-private/blob/codex/taipei610-native-2026-10-27/Railway/game-art-previews/docs/art/taipei610-2026-10-27/remote-download-verification.json)：SHA256 `14e58d03adc54e2c2020ebcfb4a3d8b33161121adbf45cb353e6d0222c5e455b`，24,762,996 bytes，559成員；推送後從私庫GitHub API重新下載，核SHA、CRC、完整解壓與每個檔案bytes一致。包外另記最終viewer ZIP下載，避免自指雜湊。

## 第二版：使用者回報浮空／#1357

撤回第一版對「所有零件已有支承」的廣義自評：65mm近接取樣不能證明接觸。對真第一版ba9ef3e4的完整原生三角建立1mm容差的接觸圖後，A/B近遠light都找到三個無車體接觸路徑的實體：內風擋背襯、端部拉桿與連結器。新增四條背襯內框固定件與拉桿吊座，每個端車僅增加60三角；原車殼／玻璃／燈／門窗／輪組／屋頂／顏色的全部原三角逐bytes保留，C/D原生與GLB全bytes相同。真第一版完整包與SHA不動，新增私有revision-2與真正同相機前後。

新增獨立contact-graph.py對每個實際連通體逐三角邊／面求交與1mm共面接觸，所有元件必須沿接觸圖到車身，AABB只篩候選，不當支承證據。真前版紅；本版十二單元綠；移動真連結器／刪除真吊座也會被拒絕。只證靜態幾何連接，不宣稱工程受力或完整動態碰撞。

#1357（merge4d5c7994）已在第一版使用：共用匯出、遊戲模型光、日夜七向、預算與hash鎖。第二版再直接使用它的viewer.mjs建立「真第一版／第二版」同視角離線比較頁，保留可旋轉下載的原viewer。#1357沒有實作AO、統一夜間亮燈或金屬反光，本輪不擴到那些效果，也不改其他車。

本版外觀未經使用者接受；尚未接入營運。人工Simulator／真機Metal效能／動畫未驗。第二版固定producer、SHA與最新整合head於同PR更新，第一版連結保留作歷史。

第二版三角數：A/B近3650／遠1722／light1638，C/D保持2824／1372／1252；完整四車12948／6188／5780。固定producer `2a0c713fd923cf4b48a8b3dd1d3b1cbb6c254629`；[新版總覽／七向／GLB／原生／viewer與ZIP](https://github.com/a91453/railway-reference-private/tree/codex/taipei610-native-2026-10-27/Railway/game-art-previews/docs/art/taipei610-2026-10-27/revision-2)，[真正同相機前後detail crop](https://github.com/a91453/railway-reference-private/blob/codex/taipei610-native-2026-10-27/Railway/game-art-previews/docs/art/taipei610-2026-10-27/revision-2/true-before-after-drawbar.png)。
