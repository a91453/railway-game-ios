# R100／藍皮解憂原生模型

本輪獨立製作 R100 機車的兩種有實車依據塗裝，以及藍皮解憂號必要客車角色。
**橘色 R122 是有年代界線的一般營運外觀，2026 年現役原色狀態 UNVERIFIED。**
藍色 R123 以 2023-01-22 正式營運照片為代表。交通部 2025 年底汰換表是計畫；
2026-05-22 實拍仍有 R122／R129 藍皮牽引，不能把計畫寫成全型已退。

正式身分、批次／日期與設備供應商見 [IDENTITY.md](IDENTITY.md)、
逐張原文／照片權利及 SHA 見 [sources.json](sources.json)、
客車與編組證據見 [blue-sources.json](blue-sources.json)。
[接手查核](TAKEOVER.md) 記真正舊 producer、PR 與認領界線。

## 模型與幾何

- R100 是美國 GM-EMD G22U，R101–R139，共 39 輛；A1A-A1A、四個動力軸，
  每架中央為惰軸。不是 R200 的 Co-Co，也不是兩端對稱駕駛室。
- `Map3DR100` 獨立建立偏置駕駛室、低短罩、高長罩、窄機艙與兩側走道、
  台車／十二輪、油箱、平台／階梯／扶手、散熱／排氣／燈／門窗。
  塗裝是殼面本身的分色；沒有照片貼圖、第二層車殼或真實商標。
- 橘／藍共用同型主比例與機構生成方法；兩款基色、灰頂／海軍藍頂、
  白腰帶與端面分色依來源處理。未有證據的設備批次差異不另造車鼻。
- 客車為全新 `Map3DBreezyBlueCoaches`：混合 40TPK32200、策展與長椅
  35TP32850、旋轉椅 35SPK32700；不同門位、窗節奏、台車及車底設備。
  四種官方角色不代表固定四輛編組；不沿用 `blue-seven` 都市電車。
- 實際沿用的是專案 `StationKitBuilder` 的 primitive、`face`／`beam`／
  `box`／圓柱與 `Model.flat` 轉換方法；未抽改共用 helper，未移植第三方幾何。
  舊 R100／R135 `hoodUnit`、EMU500 全角色、R200、所有他車與回退另作全量保護對照。

尺寸、軸位、原點、左右定義、連結面、平移／旋轉與合理簡化見
[`configuration.json`](../../../tools/tra-r100/configuration.json)。
正式 15.800 m 長度的量測基準未明；模型連結面是明文展示契約，不能當原廠圖面。
原生公尺、+X 短端／駕駛室端、+Y 朝 +X 時的左側、+Z 向上、軌面 Z=0。
官方端號、遮蔽管線／精確台車站位等未知，不用透視像素冒充工程尺寸。

## 編組與遊戲選用

[`formation.json`](../../../tools/tra-r100/formation.json) 可從本輪合法單元重建近遠景完整配置；
列出來源日期、順序、中心位置、方向、軌面、連結間隙與缺口。
凡客車實號／端別／機車改造差異未證，配置名稱及 metadata 明標 UNVERIFIED。
**有完整可組裝幾何，不等於已完成有全部車號與方向的可靠實車代表編組。**
不把缺失車號補成猜測，不把藍機車單體叫作完整藍皮交付。

橘色新機車只接既有精確 `R100CK` 身分與近遠景，使用原生車長，不伸縮至舊 19.4 m。
既有莒光客車、尾車、節數、配車身份、TrainPack 與回退保持；
沒有把所有柴油／莒光／貨運牽引換成本型。單機與多節的選用、方向及燈端由專用測試核對。
合併後選擇既有 R100 莒光身分可出現此橘色機車；沒有新增解鎖、車號比例或隨機塗裝。

`BLUE` 可變車數身份尚無本輪所需的實號、特殊客車順序與方向契約，
因此其既有代用機車／客車保留。本輪藍色機車、客車與配置先作 studies；
藍皮完整營運接入 UNVERIFIED。即時臺鐵營運映射不按 R100／Blue 字串猜測配車。
Linux 靜態與邏輯驗證不代表動態行駛、裝置 Metal 或真機接受。

## 重建與交付

真正 producer 是素材 `manifest.json` 的 `producer_commit`，
也是 `DELIVERY-SPEC.json` 固定來源／狀態／配置／渲染工具 SHA 的 commit。
不把後續文書 head 冒充模型 producer。沒有已接受的準確 R100 前版；
舊共用代用殼 producer `6d231766e212cd8a2618507b2ea00b39d496899d` 只作同尺度代用比較。

在 producer 的獨立 checkout 執行（Swift **6.4**、warnings-as-errors）：

```sh
export PATH=/path/to/swift-6.4/usr/bin:$PATH
export NODE_GLOBAL=/path/to/node_modules/
export CHROMIUM_PATH=/usr/bin/chromium
tools/tra-r100/build.sh /tmp/r100-run
node tools/tra-r100/review.mjs /tmp/r100-run
blender -b -t 1 -P tools/taichung-green/import-glb.py -- /tmp/r100-run
python3 tools/tra-r100/curate.py /tmp/r100-run /tmp/r100-overview.png
python3 tools/tra-r100/deliver.py /tmp/r100-run DEST/tra-r100/revision-1 PRODUCER
node tools/train-models/browser-check.mjs DEST/tra-r100/revision-1 --report-dir /tmp/r100-browser
```

共用 `run.sh`／assembly-spec／GLB／audit／viewer／deliver 保持。
單元不超過 M3DM v1 的 15,000 三角；整列是合法單元組成的 M3DAssembly，
不是超限單檔。完整素材在 railway-assets-private：
`game-art-previews/docs/art/tra-r100/revision-1/`，整輪最多 20 張透明 PNG sheet，
公開僅一張總覽；每張 ≤2 MiB，單檔 ≤50 MiB，新增 ≤200 MiB，沒有 ZIP／history。

驗證證據另存 `verification.json`、`protection.json` 與素材的原生／GLB、
幾何反例、獨立 Swift assembly、Blender importer、PNG 解碼、viewer 下載 SHA、
獨立 producer 重建及全量 runtime inventory 比對。HTTP 與 file:// 分開記錄。
原始照片只供合法觀察，沒有納入公開庫、照片貼圖或外部生成服務。

## 四態與外觀界線

[`status.json`](status.json) 分開記素材技術、使用者外觀接受、營運接入及裝置，
並分辨橘機車、藍機車、各客車與整列配置。作者看圖、技術通過及 CI 不代表使用者接受。
兩端／左右／俯底／斜、白模／剪影、近遠與共同尺度圖均由最終原生頂點製作；
逐向已符合、仍不符合、合理簡化與資料不足記在最終 `visual-review.md`。
Simulator、真機 Metal、效能、動畫與實際動態運行仍須各自驗證，不能由 WebGL 外推。

本輪不推 main、不合併、不開 auto-merge、不啟動 TestFlight。
