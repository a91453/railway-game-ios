# E200 整列鳴日號風格：第一輪

本批是既有車型的遊戲塗裝，並非已確認的 E200 官方鳴日號塗裝，也不宣稱本編組車型與真車相同。新塗裝使用者外觀接受 **UNVERIFIED**。

## 接手與保護基準

本輪起點 main `5f067a7d87b0a38c908223f4b988afd230ae5aa2`。逐張查核 #1201（E200/700T）、#1217（營運）、#1306（客車）、#1326（客車營運）、#1416（共用工具）均 MERGED。素材舊 PR reference-private#70/#90 亦均 MERGED。E200 比較 producer `04b051b059004baea5744c444c48fdd06e3d8349`；客車比較 producer `ac4c1e1e2b33c09f6c866424828e9ed17a6534f8`。它們是原車比較基準，本變體首次交付，沒有虛構前一輪塗裝 producer。未找到可精確連結 producer 的使用者接受證據，接受基準標 **UNVERIFIED**，本 prompt 不是新變體的接受證據。

客車配方與 ac4c1e1e 無差異；E200 所在檔案後來有700T遠景及共用輪架函式修改，E200仍呼叫原 refreshElectric，未改其造型。需以最終實際 payload 稽核為準，不以最新 main 自動等同接受。

原 `refresh-e200`、`set-E200CK-{head,car,tail}`／`set-E200CKFar-{head,car,tail}`、所有 `chukuang-*` 與共用 E500CK/R100CK/R200CK/SUMMER，以及 MINGRI/STAR、其他模型均保護。新增只有 studies 六單元，standard常駐模型／頂點不增加。全原生payload與全部頂點欄位FNV的比較紀錄見驗證。

## 涵蓋單元與編組

| 新 ID | 原來源 | 角色 |
|---|---|---|
| e200mingri-style-head | lit(refresh-e200, front:true) | E200；近景 |
| e200mingri-style-car | chukuang-standard | 既有標準自動門客車；近景 |
| e200mingri-style-tail | chuKuangTail(false) | 同客車加既有尾燈；近景 |
| e200mingri-style-head-far | 同近景 E200 | 既有機車沒有獨立減面遠景，保持 |
| e200mingri-style-car-far | chukuang-standard-far | 既有遠景客車 |
| e200mingri-style-tail-far | chuKuangTail(true) | 既有遠景尾車 |

不含 conductor-study，因為 E200CK 沒有使用它。近遠均為 head + 六個 car + tail（目前 showcase 預設8車，最多12；營運可變，不宣稱固定真實編組）。八個中心X為70、50、30、10、−10、−30、−50、−70m，Y/Z均0，旋轉均0度，+X前，共同軌面Z0；尾車已有−X尾燈，未再翻轉。原／新完整原生組裝用同一份 `assembly.json`，沒有改節數或間距。

**原生展示限制**：E200CK 沒有 ownLengths，遊戲會把各單元沿長軸縮放成19.4m，再配0.6m間隙／20m節距。通用assembly禁止縮放，本批保留原生單元尺寸、相同20m中心節距；因此展示殼隙與遊戲縮放後的殼隙不同。這不是新的營運編組或已驗的動態連結器。原／新每個單元及同節距組裝幾何完全相同。

## 改色範圍

E200只改既有白色主殼、綠松車殼帶、白門葉與既有V形塗裝線；客車只改原主殼藏青／米色區、既有門葉及腰線。機車較寬橘面保留既有分區；客車較低橘腰帶在窗下，未把機車比例套滿窗區。客車灰屋頂與冷氣不染黑。

玻璃、燈／發光標記、格柵內部、屋頂絕緣設備／集電弓、台車輪胎車底設備、連結器與貫通道保持。沒有全域替色、外掛色片或新裝飾。保留三角數、順序與所有位置／法向／u/v/layer，沒有共面細分。只允許局部色值變更；資料欄與保護區由實際輸出檢查。

使用現有 TrainLivery.mingRi 橘 `#D1773D` 與黑 `#292F31`（非實車光澤漆）；玻璃及灰硬體沿原色。基礎sRGB橘／黑對比4.15:1（不代表所有打光像素或裝置均達標）。霧面頂點色與遊戲細節密度保持，沒有品牌字／商標或第三方幾何。

## 來源及人眼檢查

先查私庫既有 mingri/mingricoach：是短身風格模型，非照片／工程資料，僅看分色，未搬mesh、貼圖或尺寸。另下載開啟中央社2020-08-01 E405實照、雄獅E405另一端與全列照片；逐檔來源URL、日期、作者可確認程度、授權及SHA在素材庫 source-record.json，照片不重新散布。附圖混有實照、效果圖、模型及 CC BY-NC-ND 立面插畫，未確認者標待查，不搬圖素或描摹。

最終自檢紀錄與技術證據將補在 verification.json。側／正／俯／斜，原／新同相機同公尺尺度與同光線；白模剪影支持形體保持，不能取代使用者接受。無正交俯視實照者標資料不足，不用模型圖充當照片。

## 選用與四種狀態

既有 variant 是車號／解鎖自動選車型，沒有玩家獨立整列塗裝選用機制。本批依指示不新增規則或選用系統。只在 tools/train-models 以新ID選取並在素材 viewer 選模型；**合併後不會自動出現在遊戲，玩家目前不能選用**。原E200CK、MINGRI與列車包／解鎖／回退保持。

素材技術、明確producer的使用者外觀接受、營運接入、裝置驗證分開記錄在 status.json。後三者 **UNVERIFIED**；Linux WebGL／Blender或CI成功不代表裝置／外觀接受。無GameCore、存檔、fixtures、購車、班表、動畫修改，不合併／auto-merge／TestFlight。

重建與驗收：[專用工具](../../../tools/e200-mingri-style/README.md)。完整素材、viewer與互鏈draft PR連結待交付補入。
