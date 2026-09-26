# Roadmap

各階段只是方向，實際範圍會依前一階段的成果調整。只有 Phase 1 已實作。

## Phase 1 — GameCore foundation ✅

- Swift 6 Swift Package、與 rendering 分離的模擬核心
- 地圖、鐵軌、車站、最小列車模型
- 整數金額經濟、deterministic 遊戲時鐘
- Codable、XCTest、Linux CI

## Phase 2 — M4 iPad + Swift Playgrounds prototype UI

- 以 SwiftUI 顯示 grid
- 點擊 tile
- 鋪軌（選擇連接方向）
- 建站
- HUD：現金、遊戲時間與速度控制
- 由 UI 迴圈把真實時間換算成 tick 呼叫 `advance(ticks:)`
- GameCore 可能需要的補充：日期 / 時刻顯示用的換算、拆除車站

## Phase 3 — Train simulation

- 由 `TrackConnections` 推導 track topology / graph
- route
- pathfinding
- train movement（位置表示方式在此決定）
- station stop

## Phase 4 — Timetable

- departure / arrival
- dwell time
- service pattern

## Phase 5 — Passenger simulation

- population
- origin / destination
- demand
- transfer
- fare

## Phase 6 — City simulation

- residential / commercial / office
- land value
- station influence
- city growth

## Phase 7 — Company simulation

- revenue
- operating expense
- construction
- loans
- assets

## Phase 8 — Advanced rendering

依實際地圖大小與列車數量的效能量測，評估 SwiftUI、SpriteKit、Metal。不預先鎖定 Metal。

## 跨階段議題

- save/load：加入存檔版本欄位與 migration
- undo/redo：利用 `GameWorld` 的 value semantics 快照
- 大型地圖與大量列車：量測後再考慮 chunking、背景計算
