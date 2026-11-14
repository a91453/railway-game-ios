# PLATFORM-BOOK

- 派工：遊戲規劃第 65 任；作者 2026-11-14 點頭依序做整合清單，第 4 項（五方 2.70）。設計在 `docs/research/OLD_RULES_INTEGRATION_DESIGN_2026-11-14.md` §3。
- session：雲端 thread session「實作月台分配」，分支 `claude/project-thread-khu6mz`。
- PB-1 做完：決策 738（`docs/decisions/738.md`）。行車控制＋寫實運轉下，要同一站同一座月台的停站班次照開始等的先後走（擴充決策 718 的 `turnOwed`，不存狀態）；車卡寫「排在 ○○ 後面等 ○○ 的月台」。存檔版本、golden schema 不動。
- 還留下：
  - PB-2（GameCore，升存檔）：`LineRoutePreference` 的指定月台改成有順序的清單（1–4 個），行車控制開時只在清單裡換（決策 57、228 的候選限在清單），清單都滿時在原站等；`deadlockedTrains()` 認出死結且原因是清單時，可用清單外的月台一次（設計頁 §3.6 第 1 點）。
  - PB-3（畫面）：路線編輯的備選排序、放不下與月台不夠的提醒（§3.4、§3.6）。
  - PB-4（量過再定）：月台安全餘裕。
  - 設計頁 §3.8 的 Mac 量測（後開始等卻先拿到月台的次數、等待秒數、死結分鐘數），改前改後各一次。
  - 130 的「這版新增」小卡要不要加一行，由寫發版說明的 session 決定（`WhatsNew.swift` 沒有動）。
- UNVERIFIED：本機沒有 Swift（swift.org 下載 403），建置與測試只在 CI；沒有在模擬器或實機上看過車卡那一句，也沒有在大地圖量過。
