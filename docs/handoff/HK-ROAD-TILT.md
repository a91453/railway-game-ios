# HK-ROAD-TILT：道路橫向找平（路床）

派工單 HK-ROAD-TILT（bug，2.60，`a91453/railway-assets-private-2` `docs/priorities/HK-ROADS.md` 第 1 項）與它的後續 ROAD-BED-TRIANGLES（bug，2.50，同庫 `docs/priorities/HK-ROAD-TILT.md`）。決策 865 與它的「後來（ROAD-BED-TRIANGLES）」。只改 GamePresentation；GameCore、存檔版本、golden、replay 都不動。

兩條工作串：「修香港山坡道路左右傾斜」（`claude/project-thread-lw0f37`，PR #2465，沒有合，第二次壓縮後停手）做了路床；「降低山坡路面三角形數」（`claude/project-thread-y8il8g`）接手把三角形降下來，兩者一起合。

## 進度

- 做完的：路床（`Map3DRoadBed.swift`）接到路面、人行道、中線、標線、街具、車流、橋與匝道的高度、國道縱斷面；路床留成折線，路面與擋牆只切在折點；立牆門檻 0.5 m；預覽工具會先呼叫 `mapGround()`。
- 量到的（預覽工具，Linux，**不是實機**）：路面左右高差 p95 香港薄扶林 3.29 → 0.00 m、台北 0.13 → 0.00 m、羅瓦涅米 0.38 → 0.00 m；三角形比沒有路床時香港 +20%（第一版 +55%）、羅瓦涅米 +10%（+56%）、台北 +0.02%（+22%）。數字與對照圖在決策 865。
- 已驗證（Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`Map3DRoadBedTests` 8 個與道路相關的既有類別通過（清單在 PR）。其餘交給 CI。

## 還留下什麼（評分在私有庫 `docs/priorities/HK-ROAD-TILT.md`）

1. **實機（Metal）沒看過，每幀成本沒量。** 下一版 TestFlight 請看香港山坡路（薄扶林、半山）與台北平地的路有沒有異狀。
2. **高擋牆（ROAD-BED-HIGH-WALLS，2.30）**：這次拍圖量過後決定不改半挖半填（決策 865「後來」有數字與理由）。香港薄扶林的牆高過 6 m 的佔 8%，最高 14.5 m 在圓環旁（場景座標 x −1103、z −300，鏡頭 `a:-1110:-326:170:30:62:62`）。要修先動路口撐高：圓環每一段都被相接的路撐到同高（`Map3DRoadBed.tallest` 9 m、`passes` 3），可以讓環上各段取自己的床高再沿環平滑；不要先做全面半挖半填（要切地面的三角形，三角形會更多）。
3. **高架匝道匯入主線的高低階（RAMP-MERGE-STEPS，2.15）**：匝道有跟著找平（地面匝道左右高差 p95 木柵 1.63 → 0.00 m、葵涌 1.73 → 0.00 m，接點沒有變差，數字在決策 865「後來」的「匝道」），但高架上匝道與主線並行匯入的一段，兩條路面各走各的高度、疊成階梯（木柵 `MAP3D_WORLD=island MAP3D_AT=24.9985:121.5800`，鏡頭 `r2:440:-637:150:30:57:60`），不同層的橋相接處還有 0.5–1.7 m 的高低差（葵涌 `MAP3D_WORLD=hongkong MAP3D_AT=22.3400:114.1320`，x 70、z 254）。改前就有。要動 `Map3DRoadBridge.swift` 的橋面高度（並行的橋併成一個平台，像地面的路那樣），和青馬塔那張單（TSINGMA-TOWERS，橋墩）同一個檔，先看 #2118 有沒有人在動。
4. **縱坡（HK-ROAD-GRADE，2.30）**：沒有變好（香港 secondary p95 17.8%、primary 17.7%）。
5. 小項（ROAD-BED-REST，1.95）：公司自己的公車路與種子街道沒有路床、斷頭路端面沒牆、`Map3DRoadTunnels` 洞口與 `bridgeDecks` 內部仍讀 `drawnGround`、高低差超過 2 m 的並行路各走各的。
6. 台北、羅瓦涅米只量了數字，沒拍改前改後的圖；海邊的路沒有單獨拍。

## 想再降三角形的話

香港還多的三萬一千個裡，擋牆一萬六千（45.4 km、7,820 片）、路面與人行道一萬五千。可以動的：

- `Map3DRoadBed.tolerance`（5 cm）：再大地面會從人行道邊穿出來（人行道只高出橫向最高地面 0.11 m），要一起調 `slack`。
- 擋牆在床每個超過 1 cm 的轉折都切一刀（`bent`）；牆頂可以改成自己的容許值（例如 5 cm，牆頂比人行道低 2 cm，會露出一條縫或凸出來，要看圖）。
- 固定點（路自己的點、過 64 m 網格線）不能拿掉：分開蓋的 chunk 要留一樣的折點，床上的每一片也不能超過一格。

## 量測怎麼重跑

補丁與腳本在專案檔案區 `handoff/HK-ROAD-TILT-measure.patch`（不在 repo 裡，已更新成合併後的樣子）。重點：

- 把 `tools/map3d-preview/Map3DPreviewDump.swift.txt` 複製成 `Tests/GamePresentationTests/Map3DPreviewDump.swift` 再套補丁；`MAP3D_TILT=1` 印出各級道路左右高差與縱坡的百分位、三角形數與混凝土三角形數。量完刪掉那個檔。
- `MAP3D_NO_BED=1`（補丁開頭寫的三行暫時開關）是「沒有路床」。
- 量測在跑的時候不要重新建置（它跑的是測試執行檔）。
- 香港：`MAP3D_WORLD=hongkong MAP3D_AT=22.2715:114.1290 MAP3D_REAL=1 MAP3D_BASEMAP=1 MAP3D_FOOTPRINTS=1 MAP3D_HEIGHTS=1 MAP3D_LANDCOVER=1 MAP3D_DAY=1 MAP3D_MINUTE=600`，鏡頭 `a:-1110:-326:170:30:62:62;b:180:472:170:120:85:62;c:200:460:70:120:86:55`（名字:x:z:距離:方向:看的高度:傾角）。羅瓦涅米、台北用各自預設的場景中心（不給 `MAP3D_AT`）。

## UNVERIFIED

- 實機與 Metal：沒有。
- 完整測試：只跑了相關的類別，其餘交給 CI。
- macOS／Xcode 建置：交給 CI。
