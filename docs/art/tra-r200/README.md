# R200／R216 一般白藍版本：獨立原生 studies

本輪交付獨立原生 studies；**未經使用者接受、未接營運、未驗裝置**。正式尺寸原報告、批次／端號及遮蔽側證據尚有缺口，不能稱工程復刻或來源全數核齊。producer、完整素材及實跑證據見本頁末與 verification.json。

## 身分與來源

R200 是臺鐵訂購的 Stadler SALi 柴電機車，整車由 Stadler Rail Valencia 在西班牙製造；不能把瑞士公司所在地稱為西班牙工廠所在地。34 輛 R201–R234。Cummins 是柴油機供應商、ABB 是牽引變流器供應商、TSA 是牽引馬達供應商，三者不是整車製造商。這些細節的官方原報告尚未成功取得，設備精確型號與交付逐車批次仍 **UNVERIFIED**。

本輪代表 R216，Blair 2024-12-12 竹南照片的白／深藍一般塗裝。2023-07-10 R201 見面會照片只支持可見五金，不把展示當營運；2023-10-28 R203／204 側面支持大分區。銘牌實照顯示 R201 製造年 2022，因此不能將二手百科概括的「2023起生產」當逐車製造紀錄。

首兩車抵臺 2023-06-11、6月13日迴送、7月10日見面會，與試運轉／驗收／2024年6月首航是不同事件。精確驗收日及首航日期，尚未取得臺鐵原始公告，不混成單一正式營運日期。來源逐件下載SHA／權利及阻擋紀錄見 [sources.json](sources.json)。原照片只在本機觀察，沒有公開、做貼圖或送生成服務。使用者附圖亦僅目視，原檔SHA與作者未取得。

## 幾何及契約

| 部件 | 本輪處理 | 證據／限制 |
|---|---|---|
| 車殼／雙駕駛室 | 全新獨立 loft，兩端斜面與切肩 | 實車正／側照；沒有沿用舊單駕駛室殼 |
| 白藍分色 | 真殼側面分段 | R216 全側實照；不是浮動色片 |
| 前窗、側窗、駕駛室門、燈 | 全新薄實體與斜面映射 | R201 原圖；框／雨刷簡化 |
| 台車、12輪、輪軸 | 全新配置 | Co′Co′；輪徑1m、中心±5.90m、各軸±1.50m為照片比例推估 |
| 底架／油箱／箱體 | 獨立幾何 | 遮蔽管線及精確箱位資料不足 |
| 屋頂 | 獨立長罩、三風扇及排氣 | 斜側照片；正交屋頂／內部BOM不足 |
| 連結器／排障器／管線／階梯 | 獨立 primitive 組合 | 近照支持；無品牌字／Logo |
| 生成 helper | StationKitBuilder.box、beam、cylinder、face、civicTube | 只調用現有 primitive，不修改 shared API，不搬其他車殼／台車 |

原生公尺、X縱向、Y向左、Z向上、軌面Z0、原點位機車中點。+X 定義為三風扇散熱端，-X 為長屋頂罩端；目前尚未用可讀駕駛室編號照片對應官方1／2端，**端號UNVERIFIED**。+Y左是站在-X看向+X的左側，非照片觀者左。前後展示用模型外部180°旋轉一次。

暫定連結器最外端±10.005m、殼端±9.45m；寬2.852m是車體，扶手外伸另列實際bounds，不能冒稱最大設備寬官方值。高度4.08m／長20.010m是二手as-built資料，與2021採購期20.000／3.900不同，待官方圖核。輪心Z0.50m。近遠景同位置，遠景減格柵／輪面／管線，不把單機叫四車EMU。

左右遮蔽側、逐端設備差異仍資料不足，暫用共通艙體，不捏造多種批次車鼻。原生完整機車各單檔，不需為湊分件建立假角色。

## 舊版／保護及營運

舊 Map3DTrainLocomotives.r200 是一駕駛室泛化近似，producer由 #910 head 86837eea 的實際歷史另核；#923 保留其第三版機車。不能稱它是已接受的R200原生前版。#710是2D車款設定，非本輪雙駕駛室幾何的接受證據。私有參考庫Q比例模型長度10.218m且engineeringDimensionsM=null，不取其網格／尺寸。**沒有本輪型態已接受前版**。

營運現有 r200ChuKuang → R200CK；舊機車尺寸被套入客車節距，且近遠及實車身份不足。本輪不替換映射、standard、燈光／控制或配車規則。合併僅 studies，玩家不會自動看到新機車。原生兩ID見Map3DR200.ids，工具可匯出。

既有莒光／PP等客車雖存在，但目前取得資料沒有可核對的R216代表性完整牽引編組與所有相容接點證據。因此沒有交付完整客貨列車，不使用錯誤莒光編組湊全列；單機不冒稱全列／動態已驗。正常營運牽引照片與相容性仍待補查。

## 驗證界線

目前所有技術輸出、故障驗收、全模型保護、獨立重建、viewer、下載、PNG、GLB importer、CI與交付均以實跑紀錄為準，未產生證據者UNVERIFIED。不可把編譯／自檢當使用者接受。

原生 helper 最近 producer：StationKitGeometry `6edd8ccaa8d35d19684c71acee1719f3ba1a79af`；CivicKitGeometry `f5e72843ff1412e318e4415eab6cd53714cc49c2`。只取閉合盒、管、樑與面朝向算法，未取其他車輛的車體／駕駛室／窗／台車組裝。所有 shared 檔案保持。

第一份原生七向實看發現屋頂底座遮住風扇、端面中央黑色通風區缺失，已回頭修正，未把該稿當完成版。近遠主包絡與位置共用，遠景刪風扇罩細分及正面格柵細條；主黑色通風區保留。這是製作者修稿，不是使用者接受的歷史版本。

五方自主選擇：玩家—保留一眼可讀的白藍雙端機車；鐵道迷—不用單駕駛室代用殼冒稱R200，缺證據明列；開發—獨立studies，保護營運及standard；美術—霧面原生頂點色，先修主形與可見設備；音樂—無變更。

最終裝配修正：新增台車枕梁、階梯立柱、扶手固定點與連結器吊座，端面扶手沿真實折面分段；連結器使用開口鑄件的簡化C形而非整塊方塊。這些支承形狀是遊戲模型的合理簡化，未聲稱原廠隱藏機構BOM。遠景省略側門小扶手，保留端面扶手、階梯、台車、主設備及共同尺度。

原生重建命令（Swift 6.4；Node 24、Pillow、Playwright／Chromium；Blender獨立匯入）：

```sh
tools/tra-r200/build.sh /absolute/output
NODE_GLOBAL=/path/to/node_modules/ CHROMIUM_PATH=/usr/bin/chromium node tools/tra-r200/review.mjs /absolute/output
python3 tools/tra-r200/curate.py /absolute/output /tmp/overview.png
blender --background --python tools/train-shape-refresh/glb-audit.py -- /absolute/output
```

輸出完整單機不需要assembly；沒有超限GLB掩蓋原生分件。完整素材中的交付spec／status／source-record以producer的輸入SHA追蹤，驗證報告另列，不事後改viewer狀態宣稱重建一致。

## 最終外觀自檢（不代表使用者接受）

已逐向開啟近遠景七向配色、白模、剪影與共同公尺相機總覽，對照已下載的R216全側及R201正面／窗門／連結器原照；照片未校準，不作透視像素尺寸宣稱。已符合的大結構：雙全寬駕駛室、白藍側面梯形分區、兩組三軸台車、兩端黑色前窗與下通風區、長罩／三風扇的屋頂端別。近遠保持同框，遠景保留主要設備位置；細格柵、雨刷與小側門扶手簡化。

仍不符合完整來源要求：未取得可確定官方1／2端的兩端原圖、反側全側／正交屋頂及實際營運牽引編組照片；沒有用同型相似照片冒稱全部已核。前罩、燈腔與連結器的圓角／精密鑄形、台車懸吊管線、屋頂細部都是模型化簡化。批次BOM、輪徑／軸距與設備寬度的官方數字不足。這些限制保留給後續核對，不能以技術通過抹去。

本輪普通機車一型一款，沒有捏造多個批次鼻形。完整客貨牽引展示未交付，原因及營運邊界見上文。

## 交付與證據

真正producer：`65464b23fc0b26058521d362555b9a0d8b550c98`。近5,484／遠2,648三角；原生各一完整機車，不需分件。

完整素材／自含旋轉縮放下載viewer：[素材庫 revision-1](https://github.com/a91453/railway-assets-private/tree/codex/tra-r200-native/game-art-previews/docs/art/tra-r200/revision-1)。兩庫draft互鏈及最新head CI見PR與#1579登記，base均main。

[實跑驗證](verification.json)、[35交付檔獨立重建一致](rebuild-verification.json)、[835既有payload／全部頂點欄位保護](protection.json)、[幾何](geometry-verification.json)、[真故障反例](r200-verification.json)、[Blender獨立匯入](glb-import-verification.json)、[最終HTTP viewer／下載](browser-verification.json)、[四態](status.json)。

最新幾何10項Swift6.4嚴格測試通過，另啟用記憶體報告：standard仍653模型／171.1MB。未改main全包共用檢查33項既有失敗、34實際鎖差異另列，不修他車／gate。其後main29d2279f只改兩份審查交接文件，Sources/tools/Package/規則未變。

技術VERIFIED；明確producer使用者外觀接受、營運、裝置UNVERIFIED。HTTP viewer已驗，file://被瀏覽器管理政策擋住，離線直開UNVERIFIED。沒有Simulator、真機Metal／效能／動畫證據。正式來源缺口與未交付牽引全列的限制不因技術通過而消失。
