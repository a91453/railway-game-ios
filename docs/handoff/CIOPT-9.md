# CIOPT-9（137 發版後的 CI 優化）

- 派工：新專案「鐵道遊戲主規劃 2」的協調者（2026-11-18），137 發版後例行六件之一。
- session：工作串「做 137 版發版後 CI 優化」（雲端 Linux），分支 `claude/project-thread-fb69a9`。
- 號碼：決策不取新號（寫成[決策 775 的後來](../decisions/775.md)）；存檔、golden、GameCore、fixture 都不動。
- 數字：[CI_MEASURE_2026-11-18](../research/CI_MEASURE_2026-11-18.md)。

## 做了

- 完整 `ci.yml` 中位數 22.9 分（上一輪 25.1）、PR 的 Swift tier 21.9–26.1 分、full lane 67–114 分：都沒過 HANDOFF §1.1 的線。11-15～11-17 full lane 紅的四晚，每支都已由 REVIEW-L24、FULLLANE-135、FULLLANE-135-2、FULLLANE-136 修了，137 的 full lane 綠。
- PR 最長的一段是 iOS run。main 的 Xcode 編譯快取只在 nightly 存，main 白天合了 GameCore 之後，PR 的 iOS 建置要重編 GameCore（SANTA-FLIGHT 17.5 分，同類 PR 13.5 分）。新 workflow `.github/workflows/ios-compilation-cache.yml`：push 到 main 改到 GameCore、`Package.swift`、`Package.resolved` 或 Xcode 專案時，用和 `ios-build.yml` 一樣的指令建一次、存快取、刪掉 main 較舊的那份。

## 合併後要看的

1. 第一次被 push 觸發（或手動）的 `ios-compilation-cache.yml` run：摘要的 hit／miss 表、「Save the compilation cache」有沒有存到、prune 有沒有刪掉舊的。
2. 之後 main 又合了 GameCore 的那天，PR 的 iOS 建置是不是回到約 13.5 分（GameCore 全部 hit）。數字寫回量測 §6。
3. 兩個建置指令要一起改：`ios-build.yml` 的「Build for iOS Simulator」與這個 workflow 的同名步驟（參數不同，快取就對不上，看摘要表就知道）。

## 留下的（沒有人在做）

- GamePresentation 改一個檔就整個重編（整模組 -O，約 7–12 分）。要再省只能拆模組或讓 PR 的建置不用 -O（決策 624 說不行），都是大工程，這次沒做。
