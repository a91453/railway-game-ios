# 機廠車場零件組 · revision 2

決策 441 的現有 36 m／3 股檢修庫是造型基準；602 的文湖機廠是預覽情境。配方在 `Map3DDepotYardKit.swift`。不接地圖、不改營運、存檔或 golden。

## 組裝

內部 x 向前、y 向上、z 向右；公開原生模型與接點 x 向前、y 向左、z 向上，單位 m。`track-*-front/back` 位於軌道中心、軌面 z=0.45 m，法向 ±x。接長件另有 `seam-front/back`；首尾以每段 12 m 的接縫相貼。庫頭的開口面為 +x，庫尾封在 −x。檢修庫有 2 股、4 股；駐車棚可選 2–6 股。非軌道件的 `ground-anchor` 是放置基點，圍牆接縫在 ±2 m。遠景皆為單一方塊，沿用檢修庫的簡化方法。

建議長度：庫頭 + N 個中段 + 庫尾 = 12 × (N+2) m。各系統最長列車與 N：

| 系統 | 遊戲編組與長度依據 | 最長整列車 | 中段 N | 庫長 |
| --- | --- | ---: | ---: | ---: |
| 文湖膠輪 | `tools/wenhu/assembly.json` 四車中心 ±20.67、±6.89 m，節距 13.78 m | 約 55.12 m（估計，四節節距） | 3 | 60 m |
| 捷運鋼輪 | `Map3DC381.arrangement` 六車、`lengths` 車長 | 約 141.42 m（既有車模） | 10 | 144 m |
| 輕軌 | `Map3DKaohsiungCitadis` 五模組長度與四個 0.60 m 接頭 | 約 33.4 m（既有車模） | 1 | 36 m |
| 台鐵 | `Map3DEMU3000.placements` 十二車，頭尾 21.35 m、中車 20.3 m | 約 245.7 m（既有車模） | 19 | 252 m |

以上是遊戲編組可見長度，非量測車頭到車尾實長；採整個節距作保守包絡。一般玩家可買的 16 節通用列車另見 `TrainLength.maximumCars`，此表依本次四種系統的實景編組。中段可任意增加。

## 高度與供電

| 系統 | 供電與資料出處 | 本配方淨高（軌面至頂棚下） |
| --- | --- | ---: |
| 文湖膠輪 | VAL／370 使用導電軌，無架空線；`Map3DTrainSets` 文湖模型、文湖線系統資料 | 4.8 m（估計） |
| 捷運鋼輪 | 台北高運量為第三軌，機場捷運採架空線；這個通用件保留架空線空間 | 6.0 m（估計） |
| 輕軌 | 淡海／安坑 750 V 架空線與電池：`docs/art/new-taipei-light-rail/README.md` | 6.3 m（估計） |
| 台鐵 | 電化線使用架空線；EMU3000 車型見 `TrainTypeCatalog` | 7.2 m（估計） |

淨高不是工程許可值；車高、線高與電氣安全距離的同一來源未查得，故以上數字全部標「估計」。庫頭過樑底面位於表列淨高，屋簷高於過樑底面 0.625 m，屋脊再高 2.6 m；軌面在地面上 0.45 m。洗車機入口與駐車棚同樣依此淨高建模。四種外觀維持既有檢修庫的灰牆、鋼構、深色窗與霧面屋頂。

## 重建與授權

從公開配方 commit `c923763236d52e30ba5ca45f2e4d715549370cfc` 重建：

```sh
PATH=/workspace/swift-6.4/usr/bin:$PATH tools/depot-yard-kit/rebuild.sh ../railway-assets-private/game-art-previews/docs/art/depot-yard-kit-2026-11/revision-2
```

來源：本專案 `Map3DDepotFacilities.swift` 的原生檢修庫與車擋配色、`Map3DStationKitGeometry.swift` 的幾何 primitive，以及上表列車編組；模型與 PNG 由本專案程式自行生成，授權依 `railway-game-ios/LICENSE.md`（著作權所有）。未含第三方照片、Quaternius 或 Polyfork 檔案。實景照片僅供連結參考，不收錄檔案。

## revision-2 組景

四張組景都擺一列既有遊戲車模，使用原生公尺比例；檢修庫與駐車棚依列車長度接段。這些是審查用組景，並未接進地圖。文湖使用 `Map3DWenhuAPM256` 的走行輪中心 ±0.99 m 與導引輪位置重做導向面，不放鋼軌。其餘系統沿用鋼軌。台鐵開放留置線另加電車線桿、門型架與接觸線，門架節距約 55 m；配色沿用 `Map3DOverheadLine` 與 `Map3DStationKitPartGeometry`。

| 組景 | 既有車模及編組 | 組景檢修庫 |
| --- | --- | ---: |
| 文湖 | `Map3DWenhuAPM256` 四車，`tools/wenhu/assembly.json` 的 ±20.67／±6.89 m | 60 m |
| 鋼輪捷運 | `Map3DC381.arrangement` 六車，模型端到端約 141.42 m | 144 m |
| 輕軌 | `Map3DKaohsiungCitadis.Unit.allCases` 五模組，長度加四個 0.60 m 接頭約 33.4 m | 36 m |
| 台鐵 | `Map3DEMU3000.placements` 十二車，車長總和約 245.7 m | 252 m |

上表與組景都使用本輪選定的既有車模尺寸；其長度是遊戲模型資料，不是車端實測。台鐵完整組景原生網格超過 App 單件模型的 15,000 三角上限，只供離線審查；每件可放進遊戲的零件仍逐一通過該上限與原生讀回。

## 頂點預算

下表由 revision-2 `manifest.json` 匯出。四張審查組景：wenhu 69684 頂點；metro 50496 頂點；lightRail 43248 頂點；taiwanRail 138372 頂點。

| 系統 | 零件 | 股數 | 近景頂點 | 遠景頂點 |
| --- | --- | ---: | ---: | ---: |
| lightRail | fence | — | 144 | 36 |
| lightRail | gate | — | 432 | 36 |
| lightRail | guardHouse | — | 108 | 36 |
| lightRail | office | — | 432 | 36 |
| lightRail | parkingCanopy | 2 | 396 | 36 |
| lightRail | parkingCanopy | 3 | 504 | 36 |
| lightRail | parkingCanopy | 4 | 612 | 36 |
| lightRail | parkingCanopy | 5 | 720 | 36 |
| lightRail | parkingCanopy | 6 | 828 | 36 |
| lightRail | shedHead | 2 | 792 | 36 |
| lightRail | shedHead | 4 | 1152 | 36 |
| lightRail | shedMiddle | 2 | 648 | 36 |
| lightRail | shedMiddle | 4 | 936 | 36 |
| lightRail | shedTail | 2 | 684 | 36 |
| lightRail | shedTail | 4 | 972 | 36 |
| lightRail | washFrame | 1 | 288 | 36 |
| metro | fence | — | 144 | 36 |
| metro | gate | — | 432 | 36 |
| metro | guardHouse | — | 108 | 36 |
| metro | office | — | 432 | 36 |
| metro | parkingCanopy | 2 | 396 | 36 |
| metro | parkingCanopy | 3 | 504 | 36 |
| metro | parkingCanopy | 4 | 612 | 36 |
| metro | parkingCanopy | 5 | 720 | 36 |
| metro | parkingCanopy | 6 | 828 | 36 |
| metro | shedHead | 2 | 792 | 36 |
| metro | shedHead | 4 | 1152 | 36 |
| metro | shedMiddle | 2 | 648 | 36 |
| metro | shedMiddle | 4 | 936 | 36 |
| metro | shedTail | 2 | 684 | 36 |
| metro | shedTail | 4 | 972 | 36 |
| metro | washFrame | 1 | 288 | 36 |
| taiwanRail | fence | — | 144 | 36 |
| taiwanRail | gate | — | 432 | 36 |
| taiwanRail | guardHouse | — | 108 | 36 |
| taiwanRail | office | — | 432 | 36 |
| taiwanRail | parkingCanopy | 2 | 396 | 36 |
| taiwanRail | parkingCanopy | 3 | 504 | 36 |
| taiwanRail | parkingCanopy | 4 | 612 | 36 |
| taiwanRail | parkingCanopy | 5 | 720 | 36 |
| taiwanRail | parkingCanopy | 6 | 828 | 36 |
| taiwanRail | shedHead | 2 | 792 | 36 |
| taiwanRail | shedHead | 4 | 1152 | 36 |
| taiwanRail | shedMiddle | 2 | 648 | 36 |
| taiwanRail | shedMiddle | 4 | 936 | 36 |
| taiwanRail | shedTail | 2 | 684 | 36 |
| taiwanRail | shedTail | 4 | 972 | 36 |
| taiwanRail | washFrame | 1 | 288 | 36 |
| wenhu | fence | — | 144 | 36 |
| wenhu | gate | — | 432 | 36 |
| wenhu | guardHouse | — | 108 | 36 |
| wenhu | office | — | 432 | 36 |
| wenhu | parkingCanopy | 2 | 540 | 36 |
| wenhu | parkingCanopy | 3 | 720 | 36 |
| wenhu | parkingCanopy | 4 | 900 | 36 |
| wenhu | parkingCanopy | 5 | 1080 | 36 |
| wenhu | parkingCanopy | 6 | 1260 | 36 |
| wenhu | shedHead | 2 | 864 | 36 |
| wenhu | shedHead | 4 | 1296 | 36 |
| wenhu | shedMiddle | 2 | 720 | 36 |
| wenhu | shedMiddle | 4 | 1080 | 36 |
| wenhu | shedTail | 2 | 756 | 36 |
| wenhu | shedTail | 4 | 1116 | 36 |
| wenhu | washFrame | 1 | 360 | 36 |
