# REVIEW-L20-FIX 的第二個 PR（2026-11-13）

同一張派工單（REVIEW-L20-FIX，遊戲規劃第 64 任，session_01YGNNunGhyuC1Bbe73nFVND）。第一個 PR（P2-5，GameCore）的交接在 `REVIEW-L20-FIX.md`；兩個 PR 各自從 main 開，為了不改同一個檔，這個 PR 另寫一檔。

- 分支 `claude/review-l20-fix-3d`。只有 GamePresentation、App 的兩個檔與測試；GameCore、存檔版本、golden、fixtures 不動；不取新決策號。
- **P2-1**（決策 709 加一節）：研究過外觀的車站在遠景每一級都畫。`Map3DFarDetail.appendAlwaysDrawn`、`Map3DScene.swift` 一行。
- **P2-3**（決策 711 第 8 節）：預算分配加遲滯，上一格畫著的區塊在預算的 9/8 以內留著。`Map3DSceneBudget.shares(of:within:were:)`、`Map3DMetalView.swift` 的 `shareWas`。
- **P2-6**（決策 710 加一節）：太快、輔助接不了手時停車條寫「太快，先煞車」。`ManualDrive.isTooFastForAssist`、`Map3DStopBar.swift`。

## 還留下什麼

- P2-3 只做了遲滯。兩個預算仍然同值（100 萬）：要讓外圈在超過時也有城市，得動 709 的斜率或 711 最低一級的數字，兩個都要實機量（決策 711 第 8 節「沒選的」）。
- P3-13（預算分配是貪心的）、P3-14（份額變了不重畫太陽陰影）沒有做。
- 作者或有實機的 session 請看：(1) 臺北或板橋拉到 3 km 以上站房還在；(2) 標準以下的機型在臺北最遠視野平移，外圈不再一塊一塊換；(3) 手動駕駛輔助開著、太快進站時停車條的字，在 iPhone SE 寬與最大字級下擠不擠。

## UNVERIFIED

- 本機（Linux，Swift 6.4.0）：建置與相關測試類別。完整的 GamePresentation tier 由 CI 跑。
- `RailwayGameApp/` 的三處改動（`Map3DMetalView.swift`、`Map3DStopBar.swift`、`Map3DPreviewScreen.swift`）Linux 編不到，由 iOS CI 編；沒有在模擬器或實機看過。截圖驗收暫緩。
