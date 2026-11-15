<p align="center">
  <img src="RailwayGameApp/Resources/Assets.xcassets/BrandMark.imageset/brand-mark-light.png" alt="" width="160">
</p>

# railway game ios

一款 iPhone / iPad 的鐵路與城市經營模擬遊戲。玩家鋪設鐵路、設立車站、規劃路線與班次，城市會沿著交通建設逐步成長：「鐵路是原因，城市是結果。」

A railway and city management game for iPhone and iPad. Lay track, build stations, plan lines and timetables, and watch towns grow around the railway.

## 遊戲內容

- 在空白地圖或真實的台灣地圖上鋪軌：曲線、高架、橋梁、隧道與坡度
- 設站、加月台、轉乘；建立路線、排班次，列車自動行駛與交會
- 經營鐵路公司：票價、貸款、成本、各路線損益、貨運與觀光
- 看城市沿著車站成長；挑戰、歷史情境與成就
- 開始畫面有教學與示範地圖

目前是早期開發版本，以內部 TestFlight 測試。

## 建置

- 遊戲核心（Swift 6，可在 macOS 或 Linux）：`swift build`、`swift test`
- iOS App（macOS + Xcode）：開啟 `RailwayGameApp/RailwayGame.xcodeproj`。這個專案由 `RailwayGameApp/project.yml` 以 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 產生，請改 `project.yml` 再重新產生，不要手改 `.xcodeproj`。

## 著作權

著作權所有（[LICENSE.md](LICENSE.md)）。這個儲存庫公開供閱覽，未經授權不得重製、改作、散布，或用來上架任何 App；自帶授權的檔案與第三方資料依各自的授權，從 OpenStreetMap、Overture Maps 整理出的資料檔依 ODbL 1.0 提供。資料來源列在遊戲內的「資料來源」頁。

All rights reserved; see [LICENSE.md](LICENSE.md). Files with their own licence and third-party data keep their own terms.
