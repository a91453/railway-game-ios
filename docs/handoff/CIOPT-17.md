# CIOPT-17：0.6.0 (148) 發版例行的 CI 量測與加速

## 進度

- 做到哪：#2747（rest 重排）、#2748（受影響測試選到基底類別）已合；MAC-RUNNER（決策 1014）是這個檔所在的 PR。
- 已驗證：#2747 自己的完整 tier，rest-1 12.6 分、rest-2 12.0 分（11-26 夜間是 19.9 分）。
- 下一步：開新的一串做下面的「只改發版說明的 PR」，本串已壓縮一次，依規則不再接新工作。

## 做了什麼

- 量測：`docs/research/CI_MEASURE_2026-11-26.md`。完整 `ci.yml` 慢的原因是 rest-1 偏重；PR 慢的原因是 macOS 排隊（截圖 run 佔掉 2–4 台）。
- #2747：rest 最重的六個類別搬進 campaign，權重照實測改。
- #2748：`affected-tests.py` 遇到沒有自己測試的基底類別（`SaveMutationChecks`），改選它的子類別。
- #2721 selected-6 逾時：查過了，原因是拉 `swift:6.4-noble` 映像花了 15.7 分，加上舊的 30 分 job 上限。main 的 f902947 已經修了，不是分片的問題。
- MAC-RUNNER：PR 的 iOS build 在 `chien-mac` 有空時用 Mac 跑，其他時候照舊用 hosted。runner 用 `cirunner` 帳號，2026-11-26 上線；fork 核准和 `RUNNER_STATUS_TOKEN` 都設好了。

## 還留下什麼（依序）

1. **只改發版說明的 PR 走快速路線**（作者 11-26 同意，「好」）。這種 PR 只動三樣：
   - `Sources/GamePresentation/WhatsNew.swift` 的條目
   - 刪 `Sources/GamePresentation/WhatsNewNext/*.txt`
   - 改 `.github/testflight-whats-new.md`

   這種 PR 只要跑 `WhatsNewTests`、`testflight-checks.yml` 和 `doc-numbers`，不跑 iOS build（現在改到 `WhatsNew.swift` 就會重建，多 30 分）。
   - 要改的地方：`ios-build.yml` 的 changes job，以及 `swift-shards.sh plan` 或 `affected-tests.py`。
   - 怎麼判斷：檔案清單只含這三種；`WhatsNew.swift` 的 diff 只在條目陣列裡，其他程式碼沒動。判斷不了就照舊全跑。
   - selftest 兩個情況都要有：只改條目的 PR 走快速路線，改到條目以外程式碼的 PR 照舊。
2. MAC-RUNNER 上線一週後量 PR 的 iOS 排隊時間和 Mac 上 build job 的時間，寫回決策 1014 的「下一步」。
3. `website-screenshots.yml` 也接 `pick-mac.yml`（等 #2726 合）。
4. `Map3DFarViewTests.testTheFarthestViewOfTaipeiIsWithinBudget` 一支要 287–440 s，見量測檔 §5。
