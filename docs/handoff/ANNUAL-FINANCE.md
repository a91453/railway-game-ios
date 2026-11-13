# ANNUAL-FINANCE（2026-11-13）

- 派工：遊戲規劃第 65 任（`NEXT_PRIORITIES_2026-10-12.md` §29.4 第 4 項）。雲端 thread session（同 DT-DEADLOCK）。分支 `claude/project-thread-6j98ei`。
- 這個 PR 只寫設計：`docs/research/ANNUAL_FINANCE_DESIGN_2026-11-13.md`。決策號、存檔版本、golden schema 都沒用。

## 做了什麼

- 盤點 GameCore 已有的稅與年度結算（設計頁 §1）。
- 讀作者舊版的年度財務規則（只讀、只取規則；設計頁 §2）：消費稅、年度營業稅、資產稅、延後繳稅、結算順序都有；年終考核與車站維持費舊版沒有。
- 設計：`annualTaxes` 開關底下的消費稅（每月、延後一個月）、鐵道設施資產稅（年底算、隔年第 120 天付）、照月台長度的車站維持費；所有遊戲都有的年終考核卡。重打的分 2.40。

## 還留下什麼

- 實作三個 PR：AF-1、AF-2（GameCore，各升存檔一次）、AF-3（畫面，第三級截圖），切法在設計頁 §4。
- 三個起點數值與考核門檻要照設計頁 §5 量過才定；這個 session 沒有量（雲端沒有 Swift）。
