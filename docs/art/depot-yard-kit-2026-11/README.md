# 機廠車場零件組 · revision 1

決策 441 的現有 36 m／3 股檢修庫是造型基準；602 的文湖機廠是預覽情境。配方在 `Map3DDepotYardKit.swift`。不接地圖、不改營運、存檔或 golden。

## 組裝

內部 x 向前、y 向上、z 向右；公開原生模型與接點 x 向前、y 向左、z 向上，單位 m。`track-*-front/back` 位於軌道中心、軌面 z=0.45 m，法向 ±x。接長件另有 `seam-front/back`；首尾以每段 12 m 的接縫相貼。庫頭的開口面為 +x，庫尾封在 −x。檢修庫有 2 股、4 股；駐車棚可選 2–6 股。非軌道件的 `ground-anchor` 是放置基點，圍牆接縫在 ±2 m。遠景皆為單一方塊，沿用檢修庫的簡化方法。

建議長度：庫頭 + N 個中段 + 庫尾 = 12 × (N+2) m。各系統最長列車與 N：

| 系統 | 遊戲編組與長度依據 | 最長整列車 | 中段 N | 庫長 |
| --- | --- | ---: | ---: | ---: |
| 文湖膠輪 | `tools/wenhu/assembly.json` 四車中心 ±20.67、±6.89 m，節距 13.78 m | 約 55.12 m（估計，四節節距） | 3 | 60 m |
| 捷運鋼輪 | `Map3DRealTrains.formation` 最多六車；`Map3DRealTrains.carPitch` 為 20 m | 約 120 m（遊戲顯示節距） | 8 | 120 m |
| 輕軌 | `Map3DRealTrains.formation` 淡海、安坑兩節模型；`Map3DTrainSets` 注記五模組約 34 m | 約 34 m（遊戲註記） | 1 | 36 m |
| 台鐵 | `Map3DRealTrains` EMU3000 十二車；`TrainTypeCatalog` 的 EMU3000 節距 20.3 m | 243.6 m（12 × 20.3） | 19 | 252 m |

以上是遊戲編組可見長度，非量測車頭到車尾實長；採整個節距作保守包絡。一般玩家可買的 16 節通用列車另見 `TrainLength.maximumCars`，此表依本次四種系統的實景編組。中段可任意增加。

## 高度與供電

| 系統 | 供電與資料出處 | 本配方淨高（軌面至頂棚下） |
| --- | --- | ---: |
| 文湖膠輪 | VAL／370 使用導電軌，無架空線；`Map3DTrainSets` 文湖模型、文湖線系統資料 | 4.8 m（估計） |
| 捷運鋼輪 | 台北高運量為第三軌，機場捷運採架空線；這個通用件保留架空線空間 | 6.0 m（估計） |
| 輕軌 | 淡海／安坑 750 V 架空線與電池：`docs/art/new-taipei-light-rail/README.md` | 6.3 m（估計） |
| 台鐵 | 電化線使用架空線；EMU3000 車型見 `TrainTypeCatalog` | 7.2 m（估計） |

淨高不是工程許可值；車高、線高與電氣安全距離的同一來源未查得，故以上數字全部標「估計」。屋簷另外高 0.5 m，屋脊再高 2.6 m。洗車機入口與駐車棚同樣依此淨高建模。四種外觀維持既有檢修庫的灰牆、鋼構、深色窗與霧面屋頂。

## 重建與授權

從公開配方 commit `8ccd8c06d7e84e920332b0f842dc98cc030ba944` 重建：

```sh
PATH=/workspace/swift-6.4/usr/bin:$PATH tools/depot-yard-kit/rebuild.sh ../railway-assets-private/game-art-previews/docs/art/depot-yard-kit-2026-11/revision-1
```

來源：本專案 `Map3DDepotFacilities.swift` 的原生檢修庫與車擋配色、`Map3DStationKitGeometry.swift` 的幾何 primitive，以及上表列車編組；模型與 PNG 由本專案程式自行生成，授權依 `railway-game-ios/LICENSE.md`（著作權所有）。未含第三方照片、Quaternius 或 Polyfork 檔案。實景照片僅供連結參考，不收錄檔案。

## 頂點預算

下表由 revision-1 的 `manifest.json` 匯出。場景圖為文湖與台鐵的組裝示意；台鐵完整最長列車須依上表追加中段。

| 系統 | 零件 | 股數 | 近景頂點 | 遠景頂點 |
| --- | --- | ---: | ---: | ---: |
| lightRail | fence | — | 144 | 36 |
| lightRail | gate | — | 432 | 36 |
| lightRail | guardHouse | — | 108 | 36 |
| lightRail | office | — | 432 | 36 |
| lightRail | parkingCanopy | 2 | 324 | 36 |
| lightRail | parkingCanopy | 3 | 396 | 36 |
| lightRail | parkingCanopy | 4 | 468 | 36 |
| lightRail | parkingCanopy | 5 | 540 | 36 |
| lightRail | parkingCanopy | 6 | 612 | 36 |
| lightRail | shedHead | 2 | 792 | 36 |
| lightRail | shedHead | 4 | 1152 | 36 |
| lightRail | shedMiddle | 2 | 648 | 36 |
| lightRail | shedMiddle | 4 | 936 | 36 |
| lightRail | shedTail | 2 | 684 | 36 |
| lightRail | shedTail | 4 | 972 | 36 |
| lightRail | washFrame | 1 | 252 | 36 |
| metro | fence | — | 144 | 36 |
| metro | gate | — | 432 | 36 |
| metro | guardHouse | — | 108 | 36 |
| metro | office | — | 432 | 36 |
| metro | parkingCanopy | 2 | 324 | 36 |
| metro | parkingCanopy | 3 | 396 | 36 |
| metro | parkingCanopy | 4 | 468 | 36 |
| metro | parkingCanopy | 5 | 540 | 36 |
| metro | parkingCanopy | 6 | 612 | 36 |
| metro | shedHead | 2 | 792 | 36 |
| metro | shedHead | 4 | 1152 | 36 |
| metro | shedMiddle | 2 | 648 | 36 |
| metro | shedMiddle | 4 | 936 | 36 |
| metro | shedTail | 2 | 684 | 36 |
| metro | shedTail | 4 | 972 | 36 |
| metro | washFrame | 1 | 252 | 36 |
| taiwanRail | fence | — | 144 | 36 |
| taiwanRail | gate | — | 432 | 36 |
| taiwanRail | guardHouse | — | 108 | 36 |
| taiwanRail | office | — | 432 | 36 |
| taiwanRail | parkingCanopy | 2 | 324 | 36 |
| taiwanRail | parkingCanopy | 3 | 396 | 36 |
| taiwanRail | parkingCanopy | 4 | 468 | 36 |
| taiwanRail | parkingCanopy | 5 | 540 | 36 |
| taiwanRail | parkingCanopy | 6 | 612 | 36 |
| taiwanRail | shedHead | 2 | 792 | 36 |
| taiwanRail | shedHead | 4 | 1152 | 36 |
| taiwanRail | shedMiddle | 2 | 648 | 36 |
| taiwanRail | shedMiddle | 4 | 936 | 36 |
| taiwanRail | shedTail | 2 | 684 | 36 |
| taiwanRail | shedTail | 4 | 972 | 36 |
| taiwanRail | washFrame | 1 | 252 | 36 |
| wenhu | fence | — | 144 | 36 |
| wenhu | gate | — | 432 | 36 |
| wenhu | guardHouse | — | 108 | 36 |
| wenhu | office | — | 432 | 36 |
| wenhu | parkingCanopy | 2 | 324 | 36 |
| wenhu | parkingCanopy | 3 | 396 | 36 |
| wenhu | parkingCanopy | 4 | 468 | 36 |
| wenhu | parkingCanopy | 5 | 540 | 36 |
| wenhu | parkingCanopy | 6 | 612 | 36 |
| wenhu | shedHead | 2 | 792 | 36 |
| wenhu | shedHead | 4 | 1152 | 36 |
| wenhu | shedMiddle | 2 | 648 | 36 |
| wenhu | shedMiddle | 4 | 936 | 36 |
| wenhu | shedTail | 2 | 684 | 36 |
| wenhu | shedTail | 4 | 972 | 36 |
| wenhu | washFrame | 1 | 252 | 36 |

組景頂點：scene 11376；scene 11376。
