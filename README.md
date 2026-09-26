# Railway Game iOS

一款以 iPhone / iPad 為主要平台的鐵道與城市經營模擬遊戲。長期目標是玩法深度接近《A列車》系列的原生 Apple 平台遊戲。

## 目前狀態

**Early development — GameCore prototype.**

目前只有與畫面無關的模擬核心（`GameCore` Swift Package）與其測試。**尚未**有 UI、可遊玩的遊戲、列車運行模擬或城市模擬。

GameCore 目前能做到：

- 建立指定尺寸的方格地圖（1…1024 × 1…1024）
- 鋪設 / 拆除鐵軌（每格記錄連接方向）
- 建造車站（唯一、可保存的 Station ID）
- 購買列車（僅 ID 與名稱，不在地圖上運行）
- 整數金額的資金與建設成本
- 可暫停、1x、2x 的 deterministic 遊戲時鐘
- 所有核心狀態可 `Codable` 編碼 / 解碼

### 建設規則

| 動作 | 條件 | 成本 |
| --- | --- | --- |
| 鋪軌 | 位置在地圖內、該格為空、至少一個連接方向、資金足夠 | `ConstructionCosts.track` |
| 拆軌 | 該格必須是鐵軌（空格與車站都會被拒絕） | 免費，**不退款** |
| 建站 | 名稱非空白、位置在地圖內、該格為空、資金足夠 | `ConstructionCosts.station` |
| 購買列車 | 名稱非空白、資金足夠 | `ConstructionCosts.train` |

任何失敗都會丟出 `GameError`，且世界狀態（地圖、資金、車站、列車）完全不變。餘額永遠不會因建設變成負數。

## 技術方向

- Swift 6（language mode 6，最低 toolchain 6.0）
- Swift Package Manager
- SwiftUI（Presentation，未來）
- SpriteKit / Metal（Rendering，未來依效能需求評估）

## Architecture

| 層 | 狀態 | 職責 |
| --- | --- | --- |
| **GameCore** | ✅ 本階段 | 權威遊戲狀態與規則；不依賴任何 UI / rendering framework |
| Presentation | 未開始 | SwiftUI 介面、使用者輸入、HUD |
| Rendering | 未開始 | 地圖與列車的繪製、動畫 |

第一階段只實作 GameCore。Presentation 與 Rendering 只讀取 GameCore 狀態並送出指令，不持有另一份遊戲真實狀態。詳見 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，未來規劃見 [docs/ROADMAP.md](docs/ROADMAP.md)。

```
Sources/GameCore/
  World/     GameWorld、GridMap、GridPosition、MapTile/TileType、GameError
  Railway/   TrackDirection/TrackConnections、Track、Station、Train
  Economy/   Money、GameEconomy、ConstructionCosts
  Time/      GameClock、GameSpeed、GameTime
Tests/GameCoreTests/
```

## Building

```sh
swift build
```

## Testing

```sh
swift test
```

GameCore 只使用 Swift 標準函式庫，因此可在 macOS、iPadOS（Swift Playgrounds）與 Linux 上建置。CI 在 Linux 上以 Swift 6.0 與 6.4 執行 build 與 test。
