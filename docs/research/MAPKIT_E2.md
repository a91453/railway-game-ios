# CX-3：E2 實景模式的 MapKit 調查

查閱日期：**2026-10-02（UTC）**。目標平台為 iOS／iPadOS 17 以上；本文件只做調查，不實作 E2，也不新增架構決策。專案前提來自 [ROADMAP 的 Stage E](../ROADMAP.md#stage-e--大地圖與實景模式) 與 [ARCHITECTURE](../ARCHITECTURE.md)：GameCore 只有整數世界座標，1 單位 = 1/64 公尺，西北角為原點，x 向東、y 向南；經緯度轉換與地圖呈現在 GameCore 之外。

**證據標記**：**文件明寫**指來源直接陳述；**推論／建議**指依 API、條款或下列模型推導，並非 Apple 的保證；**未確認**指找不到明文、連線失敗或尚未實測。每項結論後的 `[Sxx]` 對應文末的來源網址與個別查閱日期。**VERIFIED** 是本次在 Linux 工作環境完成的查閱或計算；**UNVERIFIED** 不代表通過實機、法律授權或 App Review。

## 最重要的三個結論

1. **推論／未確認：原生 MapKit 的整合不需 API 金鑰，公開資料未列原生按用量收費；但不能承諾「無限制」。** MapKit JS 有獨立的權杖與每日免費配額；原生搜尋仍可被限流。Apple 保留限制、撤銷服務的權利。ROADMAP 引述的 Apple DTS「正常操作速度」說法，本次無法取得原文核實。[S01][S02][S03][S04][S05][S06]
2. **文件明寫／未確認：標誌與法律連結要保持可見、可操作；不能建立永久的 Apple 地圖資料庫或自行下載離線圖磚。** 特別是條款把搜尋回傳的經緯度也算作 Map Data；原點隨存檔保存的需求，必須先釐清座標來源的保存權利。App Store 截圖與宣傳使用地圖的概括授權，本次也未確認。[S01][S07][S08]
3. **推論／建議：選完整 WGS84 ENU 轉換，放在畫面層。** 16,000 公尺見方、原點在西北角時，最遠角的 ENU 曲率模型誤差約 **0.048 公尺**；單一原點比例校正的球面 Mercator，相對 WGS84 參考點仍約 **84–88 公尺**。台北、高雄的 Detailed City Experience 與 Flyover 均未列於 Apple 當前清單，不能把全城 3D 當 E2 保證。[S10][S19][S20][S21][S22]

## 1. 費用、金鑰與限流

| 問題 | 調查結果與證據層級 |
| --- | --- |
| SwiftUI `Map`／`MKMapView` 要金鑰嗎？ | **推論（API 與官方完整範例支援）**：不需另發 MapKit JS key、JWT 或 Maps Server API token。原生範例直接 `import MapKit`、建立 `Map`，`MKMapView` 也沒有要求傳入服務金鑰。這不免除上架所需的開發者資格與協議。[S02][S03][S11] |
| 原生地圖是否收費、有每日配額？ | **查核結果／未確認**：已查閱的原生 API、Maps 入口與協議未列按地圖顯示次數收費的價目或固定每日配額；因此 E2 可先按「無另列原生 MapKit 用量帳單」規劃。**沒有找到可援引為永久免費承諾的明文**，也不能以「未公布配額」推成無限使用。Attachment 6 §2.7、§4 明寫 Apple 可限流或撤銷存取。[S01][S02][S03][S11] |
| MapKit JS 有何差別？ | **文件明寫**：給網站與跨平台網頁使用；每日每份 Apple Developer Program membership 免費 **250,000 map views、25,000 service calls**，更多容量需聯絡 Apple。官方範例透過 `authorizationCallback` 提供 JWT；網站用量可在 JS dashboard 查看。這些數字**不是**原生 `Map`／`MKMapView` 的配額；也不是每位玩家各有 25,000 次。[S04] |
| Web Snapshots／Server API 呢？ | **文件明寫**：Web Snapshots 另列每日每 membership **25,000 unique requests**；Maps Server API 是另一組 REST 服務。E2 原生畫面不必為此改走 JS／Web Snapshots，不能混用各服務的限制或宣稱超額自動付費。[S02][S04] |
| `MKLocalSearch` 的限流？ | **文件明寫（封存文件）**：Apple《Enabling Search》說「There are no request limits per app or developer ID」，同段也說建立大量請求的 App 可能被 throttling，搜尋必須連網。**現行文件明寫**：`MKError.Code.loadingThrottled` 可因短時間頻繁請求發生。**未確認**：目前每秒／每分鐘數字、計數範圍、重設時間與穩定的重試等待值；不能把封存說明當現行服務契約。[S05][S06][S09] |
| `MKLocalSearchCompleter` 的限流？ | **文件明寫**：應重用長壽命 completer；更新 `queryFragment` 後，它會短暫等待輸入穩定才發出搜尋。**未確認**：沒有找到獨立 QPS／每日配額，也沒有文件保證 completer 與 search 共用或分開計數。[S12][S06] |

**建議（推論）**：選地點畫面只保留一個 completer；搜尋建議被點選後才建立一次 `MKLocalSearch`，取消過時請求、忽略舊結果，並讓結果與對應 Apple 地圖一起顯示。限流或網路失敗時顯示可重試狀態，延後重試並設次數上限，不批次解析城市或在遊戲 tick 中呼叫搜尋。自行加入的 debounce／退避時間是產品策略，不能寫成 Apple 公布的限制。[S01，Attachment 6 §2.4][S05][S06][S12]

**未確認（連線限制）**：Apple Developer Forums 搜尋頁回傳瀏覽器安全驗證，無法核實 ROADMAP 所述 DTS 原文；一般搜尋引擎也未取得可用的原文。此處以可取得的封存官方指南、現行錯誤 API 與協議為依據，不捏造「50 次／分鐘」等數字。[S05][S06][S29]

## 2. 條款、標示、保存與宣傳

### 適用文件與遊戲用途

**文件明寫**：Apple Developer Program License Agreement（下稱 ADPLA）§3.3.3(v) 把使用 MapKit 的 App 連到 **Attachment 6：Additional Terms for the use of the Apple Maps Service**。本次讀到的公開 ADPLA／Schedule 1 更新日為 **2026-08-18**。另讀 Apple Maps Terms of Use；原生開發者權利以 ADPLA 與 Attachment 6 的相關條文為主要依據，不能用一般使用者條款取代開發者協議。[S01][S07]

**文件明寫**：Attachment 6 §1.1 限定使用公開 MapKit／MapKit JS／Server API，§1.2 限於 App 功能所需；§2.6 禁止「僅為存取 Apple Maps Service」向使用者收費。ADPLA §3.3.3(i) 禁止定位 API 用於自動／自主控制真實車輛、緊急或救命用途；§3.3.3(iii) 要求自己的覆蓋資料正確對齊 Apple 地圖。Attachment 6 §1.2 的 fleet management、asset tracking 等商業限制，文字限定於 **非 Apple 硬體上的 MapKit JS**。[S01]

**推論**：在 iPhone／iPad 上把玩家自建的虛構鐵道疊在地圖上的經營遊戲，未落入上述明列禁止用途；查閱條文沒有列「遊戲不得使用」。正常遊戲售價也不等於單獨販售地圖存取。這是用途判讀，**不是 Apple 對本遊戲的核准**；不要宣傳成真實導航／列車調度工具，不要把地圖存取單獨設為付費商品。[S01，§3.3.3、Attachment 6 §1.2、§2.6、§4]

### Apple 標誌與法律標示

**文件明寫**：Attachment 6 §2.1 不得移除、遮蔽或變更 Apple、合作夥伴與授權者的著作權、商標、logo、法律文件與超連結；§4 明列遮掉 logo／embedded links 可導致撤銷服務。Maps Terms §1.3(ii) 也有相同方向的要求。[S01][S07]

**建議（推論）**：HUD、工具列、列車標記、覆蓋層及底部面板都要避開 MapKit 內建的 Apple Maps 標誌與法律入口，並保留點選區域。驗收要涵蓋 iPhone／iPad、橫直向、分割畫面、深淺色與面板展開；不要只在另一頁補寫「© Apple」就遮掉原有標示。[S01，Attachment 6 §2.1、§4]

### 不能把地圖資料變成遊戲資料

**文件明寫**：ADPLA 的 **Map Data 定義含 imagery、terrain、latitude and longitude coordinates、transit、POI、traffic**。Attachment 6 §2.2 禁止 bulk download、extract／scrape／reutilize 與次生／衍生資料庫；§2.3 禁止未授權複製、衍生或利用資料改善另一個地圖服務；§2.4 要求 Apple Map Data 在對應的 Apple 地圖上顯示。不能把 Apple 搜尋結果帶到 E3 的 MapLibre 底圖。[S01]

**文件明寫**：§2.5 **不是毫無例外的零快取**：只允許為合法使用／改善效能所需的「temporary and limited」快取、預取或保存，之後必須刪除；其他保存要 Apple 明確書面允許。Maps Terms §1.3(vi)、(xiii) 同樣限制抽取、資料庫及未授權快取。[S01][S07]

**推論／建議**：MapKit 管理的暫存不能當成可下載、備份或永久攜帶的遊戲資產。玩家自行建造的鐵軌、車站與列車仍是本遊戲資料；不要從 Apple 的道路、地形高度或 POI 抽取初始路網、人口或地形進 GameCore。自行生成的座標／幾何可以暫存呈現結果，但不要把它與 Apple 圖磚、POI 回應或 snapshot 混成存檔資料。[S01，Map Data 定義、§3.3.3(iii)、Attachment 6 §2.2–2.5]

**原點保存的待釐清事項（未確認）**：技術上存經緯度比存 `MKMapPoint` 可攜，Apple API 文件也這樣建議；但這不是 Attachment 6 的永久保存授權。若原點直接取自 `MKLocalSearch` 回傳的 `MKMapItem`，其經緯度可能屬 Map Data，**未找到「只存一組原點即可永久保存」的明文例外**。E2 應保留「原點隨存檔保存」需求，先以有保存權利的獨立座標來源（例如有授權的城市清單，或使用者自行輸入的座標）設計；若要保存 Apple 搜尋回傳座標，須釐清／取得其書面授權。從 Apple 地圖點選取得的座標也不能未經確認就宣稱不受條款約束。[S01][S19]

### App Store 截圖與宣傳

**文件明寫**：Attachment 6 §2.3 沒有概括授權任意出版／公開展示 Map Data；`MKMapSnapshotter` 文件明寫可擷取系統底圖與影像，且不會自動包含 App 自訂的 overlays／annotations；這是影像產生 API 的說明，沒有明列上述宣傳用途的授權。Schedule 1 對 Apple 使用 App 截圖行銷的授權，是開發者授權給 Apple，不能反過來解讀成 Apple 授權所有地圖素材給開發者。[S01][S13]

**未確認**：本次查閱的條款與 snapshot 文件，沒有找到明確涵蓋「把含 Apple 地圖的遊戲畫面用在 App Store 截圖、App preview、官網、社群或付費廣告」的完整授權。故答案是 **本次無法確認可直接使用**，也不斷言一律禁止。保留 logo／法律標示是必要義務，**不足以單獨證明宣傳使用已獲授權**。[S01][S07][S13]

**建議（推論）**：正式宣傳前釐清使用範圍；Apple 提供 Rights and Permissions 詢問入口。未釐清時可用空白模式製作宣傳素材，不匯出地圖圖磚或把 snapshot 當可自由再利用素材。本研究不要求為文件 PR 另行取得授權。[S08][S01，Attachment 6 §2.3]

## 3. iOS 17 以上的功能與限制

### 地圖樣式、地形與台灣 3D

| 功能 | 原生做法 | 限制與證據層級 |
| --- | --- | --- |
| 標準地圖 | SwiftUI `.mapStyle(.standard(elevation: .flat))`；UIKit `MKStandardMapConfiguration`。 | **文件明寫**：標準樣式可設定 elevation、POI、traffic 等；不是任意圖層／樣式編輯器。[S03][S14] |
| 衛星／影像 | `.mapStyle(.imagery(elevation: .realistic))`；`MKImageryMapConfiguration`。 | **文件明寫**：imagery 可使用 satellite 或 Flyover imagery。**推論**：覆蓋度、解析度與更新時間不由遊戲控制。[S03][S14][S01，Attachment 6 §3] |
| 混合 | `.mapStyle(.hybrid(elevation: .realistic))`；`MKHybridMapConfiguration`。 | **文件明寫**：影像加道路與文字標籤；不保證當地有 Flyover。[S03][S14][S10] |
| 真實地形高度 | 上述樣式的 `.realistic`；UIKit 設 configuration 的 `elevationStyle = .realistic`。 | **文件明寫**：使地圖呈現 elevation。**未確認／推論**：未找到公開 API 可取出任意點的 DEM 高度、地形 mesh 或建築 mesh；呈現地形不能用來計算 GameCore 的坡度、碰撞或軌道高度。台灣各區實際地形呈現仍需實機確認。[S14][S01，Attachment 6 §2.2–2.5] |
| 自訂列車／車站 | `Annotation` 的 SwiftUI view 或 `MKAnnotationView`；軌道用 overlay。 | **文件明寫**：自訂 view 標記與平面圖形覆蓋層。**推論／未確認**：未找到把自訂 3D mesh 放進 MapKit 地形場景的公開 API；不能保證列車依真實地形／建築遮擋，或把高架的 z 高度精確疊到地形。[S03][S15][S16] |

**文件明寫／範圍判讀**：Apple 的 Feature Availability 分開列 **Detailed City Experience** 與 **Flyover**。本次 Detailed City Experience 清單沒有台北或高雄；Flyover 清單有 **Taichung, Taiwan（台中）**，沒有 Taipei／Kaohsiung。台北出現在其他功能（例如 Look Around）的清單，不能拿來證明 Flyover 支援。[S10]

**未確認**：Apple 未提供可據以確認台北、高雄每棟一般 3D 建築的完整覆蓋表，也未在上述清單承諾第三方 App 在任意縮放、相機高度與裝置上取得相同 3D 外觀。「不在 Detailed City Experience／Flyover 清單」**不等於完全沒有任何一般 3D 建築**。本次沒有 iPhone／iPad 實機或 iOS Simulator，不能宣稱已看見台北／高雄的 3D 建築。[S10][S11][S14]

**建議（推論）**：E2 先保證能用平面背景、鐵軌與標記操作；realistic／傾斜視角是地區與裝置可用時的呈現選項。台北、高雄要各測標準、影像、混合，以及近／遠縮放；不要把「每座台灣城市都有完整 3D」列為 MapKit 能滿足的驗收。[S10][S14][S01，Attachment 6 §3]

### 相機與觸控座標

**文件明寫**：iOS 17 的 `MapCamera` 有 `centerCoordinate`、`distance`（中心到相機的距離，公尺）、`heading`（相對真北的角度）、`pitch`（視角，度）。可用 `MapCameraPosition.camera(...)` 驅動 `Map(position:bounds:...)`，搭配 `MapCameraBounds` 限定地區與距離範圍；`onMapCameraChange` 接收相機變動。[S03][S17]

**文件明寫**：UIKit 的 `MKMapCamera.pitch` 說 0 度朝正下方，正值往地平線傾斜；最大角度可依相機高度被限制，沒有固定最大值。該頁另警告 legacy `mapType = .satellite／.hybrid` 把 pitch 限為 0。iOS 17 應優先查驗上述 configuration 與 SwiftUI styles 的 realistic 路徑，不能照舊 `mapType` 寫法就保證斜視 Flyover。[S18][S14]

**未確認／建議**：SwiftUI `MapCamera.pitch` 的短版文件沒有承諾固定的 60／80／90 度上限；不可把 UIKit 的限制數字或某台裝置的觀察硬編碼成通用承諾。實作後以相機回報的狀態為準，對極近距離、傾斜與旋轉做對齊驗證。[S17][S18]

**文件明寫／建議**：`MapReader`／`MapProxy` 提供 view 點與經緯度間轉換。用它或 `MKMapView.convert` 處理點選與標記位置，再經下面的 ENU 轉為世界座標；相機有 pitch／heading 時，不可只用「螢幕像素乘縮放值」回推地面位置。這些都是畫面層工作。[S23][S11][S17]

### 上千條線的自訂覆蓋層

**文件明寫**：SwiftUI `MapPolyline` 可呈現自己的座標資料並套 `StrokeStyle`；`Annotation` 可放 SwiftUI view。UIKit 的 `MKOverlayRenderer` 可自訂繪圖，`draw(_:zoomScale:in:)` 可能分塊、在多個背景執行緒同時呼叫，實作必須可並行安全。`MKMultiPolyline` 明確適合將多條同樣樣式的線集合，交給 `MKMultiPolylineRenderer`。[S03][S15][S16][S24]

**未確認**：Apple 沒有在這些文件承諾 1,000／5,000 條線的影格率、最大頂點數、Annotation 數量或 SwiftUI 與 UIKit 的效能勝負。**本次沒有效能實測**，不能稱「上千條線沒問題」或直接指定必須換 renderer。[S15][S16][S24]

**建議（推論）**：

- 先剔除視窗外物件，依縮放簡化線段／隱藏細節；以穩定 ID 更新有變更的幾何，避免每個 tick 重建全路網。遊戲自己的衍生幾何快取與 Apple Map Data 的快取要分清楚。[S01，Attachment 6 §2.5][S16][S24]
- 靜態軌道與移動列車分開更新；SwiftUI 原型若出現更新或繪圖瓶頸，評估 `MKMapView`，按樣式與空間分組 `MKMultiPolyline` 或自訂 renderer。renderer 只讀不可變的呈現快照，不能從背景繪圖 callback 修改／並行讀寫活躍的 `GameWorld`。[S16][S24；專案 ARCHITECTURE 的權威狀態規則]
- E2 實作時量測 1,000／5,000 條可見線、每條 16／128 頂點、100／1,000 台移動列車；組合三種底圖、pitch 0／45 度，測平移、縮放、建造預覽。記錄幀時間、主執行緒時間、記憶體與點選延遲，涵蓋最低支援 iPhone 與 iPad。這是**建議測試矩陣，不是已通過的資料**。[S15][S16][S17][S24]

### 離線

**文件明寫**：iOS 17 以上的 **Apple Maps App** 可以下載離線地圖；支援地區與功能有限。支援文章的操作對象都是 Maps App。[S25]

**查核結果／未確認**：已查閱的 MapKit 公開 API 沒有找到讓第三方 App 管理、預先下載或打包 Apple 底圖的受支援離線 API，也沒有找到保證第三方可沿用 Maps App 下載區域的明文。因此 **E2 不可承諾離線 Apple 底圖**；偶爾顯示系統暫存不構成離線功能。禁止自行永久預取圖磚的條款也不能用 Maps App 有離線功能來排除。[S11][S01，Attachment 6 §2.5][S25]

**建議（推論）**：斷網時保留玩家世界與操作，提供空白背景／連線狀態，等待底圖恢復；選地點搜尋要顯示網路失敗。要可保證離線地圖時，改評估有適當資料授權的 E3。[S05][S25][S26]

## 4. 世界座標與經緯度換算

### 比較定義：位置誤差，不是底圖的定位精度

**文件明寫**：Apple 的封存指南說 MapKit 使用 Mercator 投影、`MKMapPoint` 是該投影的 x／y；現行 API 提供依緯度取得 map points／meter 的函式，並建議保存經緯度而非 map point。[S19][S20]

**推論／模型假設**：以下使用水平面、海拔 0 的 **WGS84 橢球**（`a = 6378137 m`，`f = 1/298.257223563`）。以原點出發、距離 `r = hypot(e,n)`、方位角 `atan2(e,n)` 的 WGS84 geodesic 終點為比較基準；誤差是候選終點到此基準的**地表距離（公尺）**。這是明確定義的「世界平面半徑與方位」比較，不是 Apple 地圖內容、衛星影像或測量資料的絕對精度。[S21][S22]

本題取邊長 **16,000 公尺**，`e = worldX / 64`、`n = -worldY / 64`，所以 `0 ≤ e ≤ 16000`、`-16000 ≤ n ≤ 0`。原點在西北角，最遠東南角為 **22,627.417 公尺**，不能用中心原點的 8 公里半邊估誤差。實際 ROADMAP 上限是 16,384 公尺；其東南角 ENU 誤差約 0.051 公尺，見下方重算方法。[S21][S22；專案 ROADMAP Stage E]

### (a) 完整局部切平面 ENU

**推論／數學做法**：使用 geodetic latitude（不能把地心緯度當 geodetic latitude），先把原點轉為 WGS84 ECEF `O`。由原點經緯度建立東、北、上單位向量 `E/N/U`。對 `e,n` 求 `P = O + eE + nN + uU` 與海拔 0 橢球的近端交點；以二次式解出靠近 0 的 `u`，再將 ECEF 轉回經緯度。反向則將地表經緯度轉 ECEF，以 `E/N` 的內積取得 `e,n`。這才是此處的 **ENU／局部正射投影**，不是只用固定「每度多少公尺」線性加經緯度。[S21][S22]

**推論／計算**：球面近似的徑向地表距離是 `R·asin(r/R)`，相對平面 `r` 的差約 `r³/(6R²)`；完整 WGS84 計算如下。另一種常見作法固定 `u=0`，再把 ECEF 轉 geodetic 丟掉海拔，其地表位置誤差約 `r³/(3R²)`，在東南角約 **0.095 公尺**。兩者必須分清楚。曲率造成的 `u` 約負 40 公尺／`u=0` 點的橢球高約正 40 公尺，**這不是水平誤差，也不是遊戲地形高度**。[S21][S22]

### (b) MKMapPoint／球面 Web Mercator 與原點比例

**推論／模型假設**：以標準球面 Web Mercator 模型 `X=a·λ`、`Y=a·ln(tan(π/4+φ/2))` 分析比例失真，MapKit 的 map point 單位再乘固定世界寬度比例；畫面 y 向南時等同把本式 Y 反號。Apple 文件說明 Mercator 與比例 API，**沒有在本次來源中明定內部全部常數或等同 EPSG:3857 的逐位元公式**，所以以下是可重現的投影模型數字，不宣稱是在 Linux 跑出 `MKMapPoint` 的實機結果。[S19][S20][S22]

- **不校正比例（推論）**：球面投影比例 `k=sec φ`；22° 約 **1.0785**、25° 約 **1.1034**，投影距離膨脹約 **7.85–10.34%**。反過來把投影上的 1 公尺直接當遊戲的地表 1 公尺，會把地表長度縮短；東南角位置偏差達約 **1.69–2.15 公里**。[S19][S20][S22]
- **單一原點比例校正（推論）**：令 `ΔX=e/cos φ₀`、`ΔY=n/cos φ₀` 再反投影，概念上類似在原點只取一次 points／meter。即使先把地球視為球體，16 公里內的比例變化仍約 **0.10–0.12%**，東南角位置誤差約 **16.2–18.7 公尺**；與真實 WGS84 橢球比較，球面與橢球的南北尺度差又使誤差達 **83.7–88.1 公尺**。不能只報原點的 `cos φ₀` 就稱所有點都等公尺。[S20][S21][S22]
- **分東／北原點尺度校正（推論）**：用 WGS84 的卯酉圈半徑 `N₀`、子午圈半徑 `M₀`，令 `ΔX=a·e/(N₀cos φ₀)`、`ΔY=a·n/(M₀cos φ₀)`，可排除原點球面／橢球尺度差，但有限地區的投影方向與比例變化仍留下約 **16.2–18.7 公尺**。每點重新套比例若沒有一致的前後轉換定義，還會出現路徑依賴；它不是本題要保存的固定座標映射。[S21][S22]

### 計算結果（每個位置的誤差，單位：公尺）

**VERIFIED — Linux，Python 3、GeographicLib 2.1、pyproj 3.8.0；模型推論，非 MapKit 實測。** 另以 250 公尺間距取樣兩個緯度的四條邊，ENU 最大樣本均在東南角。本表用 WGS84 geodesic 當參考，經度固定 121°；東／北原點尺度校正欄不是球面參考。三個非原點角列出所有邊界的端點；ENU 最遠誤差在東南角。沒有把第三方地圖的內容定位誤差混入。[S21][S22]

| 原點緯度 | 邊界點 `(e,n)` | ENU 橢球交點 | ENU 固定 `u=0` | Mercator 未校正 | Mercator 單一 `cos φ₀` | Mercator 東／北分別校正 |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 22° | 東北 `(16000,0)` | 0.0168 | 0.0335 | 1158.1 | 11.1 | 8.1 |
| 22° | 西南 `(0,-16000)` | 0.0170 | 0.0339 | 1236.8 | 76.8 | 8.0 |
| 22° | 東南 `(16000,-16000)` | **0.0477** | 0.0954 | 1690.0 | **88.1** | 16.2 |
| 25° | 東北 `(16000,0)` | 0.0168 | 0.0335 | 1490.4 | 13.4 | 9.4 |
| 25° | 西南 `(0,-16000)` | 0.0169 | 0.0339 | 1562.8 | 69.4 | 9.2 |
| 25° | 東南 `(16000,-16000)` | **0.0477** | 0.0953 | 2154.6 | **83.7** | 18.7 |

### 推薦與 deterministic 邊界

**建議（推論）**：採 **WGS84 ENU 橢球交點方案**。在台灣與 16 公里範圍內，曲率模型誤差不到 0.05 公尺，遠小於原點固定尺度 Mercator 的數十公尺；不依賴特定底圖供應商，E3 可沿用同一組玩家世界座標。0.05 公尺仍大於 1/64 公尺，不能稱地表距離與世界長度逐單位完全相等；它是適合遊戲呈現的投影取捨。`MKMapPoint` 留給覆蓋層繪圖／可見範圍，不能成為權威世界座標。[S19][S20][S21][S22]

**建議（推論；遵守專案 deterministic 規則）**：

1. 換算是一個只由「原點、投影版本、整數世界座標」決定的純函式；不得讀網路、定位、搜尋結果、時間或相機狀態。經緯度來源的授權另依第 2 節處理。[S01][S21；專案 ARCHITECTURE]
2. 原點應以固定精度整數（例如 10⁻⁹ 度）存入 App 的存檔中繼資料，並保存／識別投影版本；讀檔不能再次搜尋或重新地理編碼。這是 E2 的設計建議，本 PR 不新增 schema／決策。[S19][S21；專案 ROADMAP Stage E]
3. 前後轉換固定 WGS84 常數、運算順序、迭代次數與最後的捨入規則；反向世界座標以最近 1/64 公尺、平手規則明定後再送 GameWorld 指令。每軸量化最多 0.0078125 公尺，兩軸位置量化最多約 0.01105 公尺，與投影誤差分開記錄。[S21][S22；專案 ARCHITECTURE]
4. **`Double` 搭系統 `sin/cos/atan/log` 並不等於跨 OS／CPU 逐位元 deterministic。** 若換算必須跨裝置一致，E2 要固定並版本化數學實作（例如固定點／明定精度的近似與迭代），不把 Apple 的投影函式作權威轉換；用固定輸入／預期輸出向量驗證正反轉換、捨入邊界與讀檔。下列 Python 程式只是研究重算工具，**不是可直接移入 App 的 deterministic 實作**。[S21][S22；專案 ARCHITECTURE 的 deterministic 要求]
5. MapKit／Core Location／Apple 平台 API 留在 App adapter；平台無關的純座標數學可在 Presentation。任何經緯度、`MKMapPoint`、DEM 或地圖供應商資料均不得進入 GameCore，GameCore 仍只以既有世界整數做長度、行車與建造判定。[S01][S19；專案 ARCHITECTURE]

### 重算程式（僅研究用，不新增專案相依）

以下在專案外的 Python 環境安裝 `geographiclib==2.1`、`pyproj==3.8.0` 即可重算上表；`L=16384` 可檢查 ROADMAP 的上限。ENU 的近端根使用避免相消的寫法；投影數值精度與地圖內容精度是不同問題。[S21][S22]

```python
from math import sin, cos, tan, log, exp, atan, atan2, sqrt, hypot, radians, degrees, pi
from pyproj import Transformer
from geographiclib.geodesic import Geodesic

a = 6378137.0
f = 1 / 298.257223563
b, e2 = a * (1 - f), f * (2 - f)
to_xyz = Transformer.from_crs(4979, 4978, always_xy=True)
to_ll = Transformer.from_crs(4978, 4979, always_xy=True)
L = 16000

def enu(lat, east, north, intersect=True):
    p, lon = radians(lat), radians(121)
    o = to_xyz.transform(121, lat, 0)
    E = (-sin(lon), cos(lon), 0)
    N = (-sin(p)*cos(lon), -sin(p)*sin(lon), cos(p))
    U = (cos(p)*cos(lon), cos(p)*sin(lon), sin(p))
    q = [o[i] + east*E[i] + north*N[i] for i in range(3)]
    u = 0
    if intersect:
        w = (1/a**2, 1/a**2, 1/b**2)
        A = sum(w[i]*U[i]**2 for i in range(3))
        B = 2*sum(w[i]*q[i]*U[i] for i in range(3))
        C = sum(w[i]*q[i]**2 for i in range(3)) - 1
        u = -2*C / (B + sqrt(B*B - 4*A*C))
    lon, lat, _ = to_ll.transform(*[q[i] + u*U[i] for i in range(3)])
    return lat, lon

def merc(lat, east, north, mode):
    p = radians(lat)
    N = a / sqrt(1 - e2*sin(p)**2)
    M = a*(1-e2) / (1 - e2*sin(p)**2)**1.5
    sx = sy = 1
    if mode == "cos":
        sx = sy = 1/cos(p)
    if mode == "axes":
        sx, sy = a/(N*cos(p)), a/(M*cos(p))
    x = radians(121) + east*sx/a
    y = log(tan(pi/4 + p/2)) + north*sy/a
    return degrees(2*atan(exp(y)) - pi/2), degrees(x)

for lat in (22, 25):
    for east, north in ((L, 0), (0, -L), (L, -L)):
        ref = Geodesic.WGS84.Direct(lat, 121,
                                    degrees(atan2(east, north)), hypot(east, north))
        candidates = [enu(lat, east, north), enu(lat, east, north, False)]
        candidates += [merc(lat, east, north, m) for m in ("raw", "cos", "axes")]
        errors = [Geodesic.WGS84.Inverse(ref["lat2"], ref["lon2"], *q)["s12"]
                  for q in candidates]
        print(lat, east, north, [round(x, 4) for x in errors])
```

## 5. E3：MapLibre Native iOS 與 OpenFreeMap 對照

| 項目 | 文件明寫／推論與限制 |
| --- | --- |
| MapLibre Native 授權 | **文件明寫**：**BSD 2-Clause**，可使用、修改並散布原始碼／二進位。原始碼保留 copyright、兩條條件與 disclaimer；二進位散布須在文件或附帶資料重現這些內容。**建議**：App 的第三方授權頁附完整文字；不能只寫「MapLibre 免費」。相依套件與地圖資料還要另外核對授權。[S26] |
| OpenFreeMap 收費與金鑰 | **文件明寫（官方 repo／網站原始稿）**：公開服務免費，map views／requests 沒有數量上限，不需註冊或 API key，亦提供自行架設與每週 planet downloads。**推論**：可作商用遊戲底圖；查閱的 ToS 未另禁止商用，但仍須遵守 ToS 與資料授權，免費不等於所有資料可無條件重用。[S27][S28][S30] |
| OpenFreeMap 使用條款 | **文件明寫（官方網站原始稿，更新日 2026-09-09）**：整合服務者須滿 18 歲且有簽約能力，不限制只是觀看地圖的終端使用者年齡；不得非法使用、干擾服務、侵犯智財，或未經允許以自動化方式蒐集資料。匈牙利法、布達佩斯個別仲裁；服務與條款可變更。**未確認**：官網／圖磚端點回 403，無法確認目前部署的頁面是否與此原始稿完全相同。[S28] |
| 標示 | **文件明寫**：官方要求 `OpenFreeMap © OpenMapTiles Data from OpenStreetMap`，其中 `OpenFreeMap` 可省略，因此最低文字為 **`© OpenMapTiles Data from OpenStreetMap`**。官方說 MapLibre 會自動加入；**建議／未確認**：iOS 實際樣式來源、attribution 控制項與可點連結仍須驗證，不能沿用網頁範例就隱藏原生標示。OSM 要求 credit 及告知 ODbL，連到著作權頁。[S27][S30] |
| SLA | **文件明寫**：ToS 是 as-is／as-available／with-all-faults，不保證正確性、可用性或特定用途，且可不預告停止。**結論（推論）**：沒有可依賴的可用率／復原時間 SLA；免費不限量不是營運保證。[S28] |
| 離線與 3D | **文件明寫**：MapLibre iOS 有 `MLNOfflineStorage` 管理 offline packs；樣式規格有 `fill-extrusion`。**推論／限制**：renderer 能做不等於資料源允許任意批次下載，或每座城市都有完整高度。OpenFreeMap ToS 的自動蒐集限制要與官方 planet downloads／自行架設方式一起評估，不能直接對公開圖磚服務暴力預抓。[S26][S27][S28][S31] |
| 能否取代全部 Apple 功能？ | **文件明寫**：OpenFreeMap README 列出不提供 search／geocoding、directions、satellite hosting、elevation lookup 等。**推論**：E3 若要衛星、真實地形或搜尋，需另找有授權的資料／服務；切換後不能把 Apple POI／搜尋結果搬到新底圖。[S27][S01，Attachment 6 §2.4] |

**建議（推論）：以下需求確定成立時，MapKit 可能不夠用，才進入 E3 的評估。**

- 必須可控地離線下載、保存或自行架設底圖；需要可重現的底圖版本，而非依賴 Apple 在線資料與快取。[S01][S25][S26][S27]
- 要完整自訂配色／圖層／標籤，或以可取得、可補齊的建築資料做 `fill-extrusion`；不能接受台灣城市的 3D 覆蓋未知。MapLibre 仍不會自動補出所有城市的建物高度。[S10][S14][S31]
- 上千條線與列車的實機量測顯示 MapKit 的呈現／更新路徑達不到產品目標。先確認瓶頸，再比較 MapLibre，不先宣稱換 SDK 就比較快。[S15][S16][S24][S26]
- 必須自行控制 3D 軌道、列車 mesh 與地形遮擋時，還要評估獨立 3D renderer；`fill-extrusion` 不能直接等同 Phase 8 的完整鐵道 3D。[S15][S16][S31；專案 ROADMAP Phase 8]

E3 的加入仍須另外評估依賴與架構紀錄；本任務不修改 ROADMAP／ARCHITECTURE。[專案 AGENTS.md、ROADMAP Stage E]

## 查核狀態與 E2 待實測事項

- **VERIFIED — Linux 工作環境**：讀取 AGENTS.md、CLAUDE.md、Stage E 與相關架構規則；查閱下列成功連線的官方內容；由官方 repo 原始稿核對 OpenFreeMap ToS／標示；執行上表數值計算。官方文件 API 的動態頁另以 Apple 提供的 documentation JSON 讀取。[S01–S28][S30][S31]
- **UNVERIFIED — 網路／資料缺口**：Apple DTS 原文、原生 MapKit 永久免費的明文承諾、目前數字化搜尋限流、App Store／宣傳的完整地圖素材授權、Apple 搜尋原點永久保存的例外、OpenFreeMap 官網部署條款一致性。[S01][S04–S08][S28][S29]
- **UNVERIFIED — 需 macOS／iOS 實機**：台北／高雄 3D 建築與地形、相機可達角度、遮擋與觸控對齊、大量線段／列車效能、斷網行為、MapLibre iOS 標示控制項與跨裝置 deterministic 轉換。沒有執行 Swift／Xcode build 或遊戲測試，本 PR 只有研究文件。[S10–S18][S23–S26][S31]

會影響 E2 設計的限制是：**原點座標的保存權利、Apple 標示與搜尋結果顯示義務、沒有可承諾的離線底圖、台灣 3D 覆蓋未知、自訂 3D／地形高度資料不可取得的查核缺口，以及上千條線必須實機量測**。座標轉換需版本化並留在畫面層，不能讓底圖改變 GameCore 的 deterministic 結果。[S01][S10][S14–S26；專案 ARCHITECTURE]

## 來源（網址與查閱日期）

下列日期均為本次實際查閱／嘗試連線日，非來源發布日。GitHub 原始稿固定到本次取得的 commit；不能把原始稿等同已部署官網或法律上已獲個別授權。

| 編號 | 來源與網址 | 查閱日期／取得狀態 |
| --- | --- | --- |
| S01 | Apple：[Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)，Definitions、§3.3.3、Attachment 6、Schedule 1。 | 2026-10-02；HTTP 200，公開 HTML 全文。 |
| S02 | Apple：[Maps for developers](https://developer.apple.com/maps/)。 | 2026-10-02；HTTP 200。 |
| S03 | Apple WWDC23：[Meet MapKit for SwiftUI](https://developer.apple.com/videos/play/wwdc2023/10043/)，範例與逐字稿。 | 2026-10-02；HTTP 200。 |
| S04 | Apple：[Maps on the web](https://developer.apple.com/maps/web/)，JS dashboard、配額與 JWT 範例。 | 2026-10-02；HTTP 200。 |
| S05 | Apple 封存指南：[Enabling Search](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/EnablingSearch/EnablingSearch.html)。 | 2026-10-02；HTTP 200；封存文件，不當作現行配額契約。 |
| S06 | Apple：[MKError.Code.loadingThrottled](https://developer.apple.com/documentation/mapkit/mkerror/code/loadingthrottled)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S07 | Apple：[Apple Maps Terms of Use](https://www.apple.com/legal/internet-services/maps/terms-en.html)，§1.3、§2、§4。 | 2026-10-02；HTTP 200。 |
| S08 | Apple：[Rights and Permissions](https://www.apple.com/legal/contact/rights-permissions.html)。 | 2026-10-02；HTTP 200；只確認詢問入口，沒有取得個別許可。 |
| S09 | Apple：[MKLocalSearch](https://developer.apple.com/documentation/mapkit/mklocalsearch)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S10 | Apple：[iOS and iPadOS Feature Availability](https://www.apple.com/ios/feature-availability/)，Maps 的 Detailed City Experience／Flyover／Look Around 清單。 | 2026-10-02；HTTP 200。 |
| S11 | Apple：[MKMapView](https://developer.apple.com/documentation/mapkit/mkmapview)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S12 | Apple：[MKLocalSearchCompleter](https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S13 | Apple：[MKMapSnapshotter](https://developer.apple.com/documentation/mapkit/mkmapsnapshotter)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S14 | Apple：[MapStyle](https://developer.apple.com/documentation/mapkit/mapstyle)、[Elevation](https://developer.apple.com/documentation/mapkit/mapstyle/elevation)、[MKStandardMapConfiguration](https://developer.apple.com/documentation/mapkit/mkstandardmapconfiguration)、[MKImageryMapConfiguration](https://developer.apple.com/documentation/mapkit/mkimagerymapconfiguration)、[MKHybridMapConfiguration](https://developer.apple.com/documentation/mapkit/mkhybridmapconfiguration)。 | 2026-10-02；各官方 documentation JSON HTTP 200，MapStyle availability 為 iOS 17。 |
| S15 | Apple：[MapPolyline](https://developer.apple.com/documentation/mapkit/mappolyline)、[Annotation](https://developer.apple.com/documentation/mapkit/annotation)。 | 2026-10-02；各官方 documentation JSON HTTP 200。 |
| S16 | Apple：[MKOverlayRenderer](https://developer.apple.com/documentation/mapkit/mkoverlayrenderer)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S17 | Apple：[MapCamera](https://developer.apple.com/documentation/mapkit/mapcamera)、[distance](https://developer.apple.com/documentation/mapkit/mapcamera/distance)、[heading](https://developer.apple.com/documentation/mapkit/mapcamera/heading)、[pitch](https://developer.apple.com/documentation/mapkit/mapcamera/pitch)、[MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition)、[MapCameraBounds](https://developer.apple.com/documentation/mapkit/mapcamerabounds)。 | 2026-10-02；各官方 documentation JSON HTTP 200，availability 為 iOS 17。 |
| S18 | Apple：[MKMapCamera.pitch](https://developer.apple.com/documentation/mapkit/mkmapcamera/pitch)。 | 2026-10-02；官方 documentation JSON HTTP 200。 |
| S19 | Apple：[MKMapPoint](https://developer.apple.com/documentation/mapkit/mkmappoint)、[封存指南：Displaying Maps](https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/MapKit/MapKit.html)。 | 2026-10-02；官方 documentation JSON／封存 HTML HTTP 200。 |
| S20 | Apple：[MKMapPointsPerMeterAtLatitude](https://developer.apple.com/documentation/mapkit/mkmappointspermeteratlatitude(_:))、[MKMetersPerMapPointAtLatitude](https://developer.apple.com/documentation/mapkit/mkmeterspermappointatlatitude(_:))。 | 2026-10-02；各官方 documentation JSON HTTP 200。 |
| S21 | ESA Navipedia：[Transformations between ECEF and ENU coordinates](https://gssc.esa.int/navipedia/index.php/Transformations_between_ECEF_and_ENU_coordinates)。 | 2026-10-02；HTTP 200。 |
| S22 | GeographicLib：[Python API／Geodesic](https://geographiclib.sourceforge.io/html/python/code.html)、[WGS84 constants](https://geographiclib.sourceforge.io/html/python/_modules/geographiclib/constants.html)、[Geodesics on an ellipsoid](https://geographiclib.sourceforge.io/html/python/geodesics.html)。 | 2026-10-02；各 HTTP 200；表內 Mercator／ENU 誤差為本文依公式計算。 |
| S23 | Apple：[MapReader](https://developer.apple.com/documentation/mapkit/mapreader)、[MapProxy](https://developer.apple.com/documentation/mapkit/mapproxy)。 | 2026-10-02；各官方 documentation JSON HTTP 200。 |
| S24 | Apple：[MKMultiPolyline](https://developer.apple.com/documentation/mapkit/mkmultipolyline)、[MKMultiPolylineRenderer](https://developer.apple.com/documentation/mapkit/mkmultipolylinerenderer)。 | 2026-10-02；各官方 documentation JSON HTTP 200。 |
| S25 | Apple Support：[How to download maps to use offline on your iPhone](https://support.apple.com/en-us/105084)。 | 2026-10-02；HTTP 200；文章發布日 2025-12-15。 |
| S26 | MapLibre Native：[BSD 2-Clause LICENSE.md](https://github.com/maplibre/maplibre-native/blob/ba9fc57bc88725d7602fd652e601384e9f2e3183/LICENSE.md)、[iOS guide](https://maplibre.org/maplibre-native/docs/book/platforms/ios/index.html)、[MLNOfflineStorage](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre/mlnofflinestorage)。 | 2026-10-02；LICENSE raw／guide／官方 DocC data HTTP 200。 |
| S27 | OpenFreeMap：[README（免費、限制、Attribution、下載）](https://github.com/hyperknot/openfreemap/blob/91062b73ebdec84ca1e287da1026ba756a2f9907/README.md)、[官網首頁原始稿](https://github.com/hyperknot/openfreemap/blob/91062b73ebdec84ca1e287da1026ba756a2f9907/website/content/index/whatis.md)。 | 2026-10-02；官方 repo raw HTTP 200。 |
| S28 | OpenFreeMap：[Terms of Service 官網原始稿](https://github.com/hyperknot/openfreemap/blob/91062b73ebdec84ca1e287da1026ba756a2f9907/website/content/policies/tos.md)、[官網](https://openfreemap.org/)、[quick start](https://openfreemap.org/quick_start/)。 | 2026-10-02；官方 repo raw HTTP 200；官網與 quick start HTTP 403，部署頁未確認。 |
| S29 | Apple：[Developer Forums 的 MapKit limits 搜尋](https://developer.apple.com/forums/search/?q=MapKit%20limits)。 | 2026-10-02；回傳安全驗證頁，**未取得 DTS 原文**。 |
| S30 | OpenStreetMap：[Copyright and License](https://www.openstreetmap.org/copyright)。 | 2026-10-02；HTTP 200。 |
| S31 | MapLibre：[Style Specification — layers／fill-extrusion](https://maplibre.org/maplibre-style-spec/layers/#fill-extrusion)。 | 2026-10-02；HTTP 200；功能須另核對 iOS SDK support。 |

補充取得限制：EPSG registry／epsg.io 與 PROJ 網頁本次回 403，未用其內容當已核實的來源。球面 Web Mercator 模型在第 4 節自行列出公式與假設；沒有用未讀到的網頁替 Apple 內部常數背書。
