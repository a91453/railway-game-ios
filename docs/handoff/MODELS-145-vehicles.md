# 145 模型接回 C 車輛

派工單「145 模型接回 C 車輛」，session_01JMHz9cUerFFHjALdweJv45，分支 `claude/models-145-vehicles`，PR #2596（草稿），決策 930。存檔版本、golden、replay 都不動。這一串在第 2 次壓縮後依規則停手，下面是接手要做的。

## 進度

- 做到哪：十款模型的程式、測試、鎖檔、決策 930 都在分支上（Edg、Rx、EMU100、山頂纜車、單軌、磁浮、懸吊式單軌、CT273、外島雙體渡輪、烏來車廂）。
- 已驗證：雲端 Linux `swift build --build-tests -Xswiftc -warnings-as-errors` 過；決策 930 §5 列的測試類別全過；`doc_numbers.py --check` 過。PR 的 CI 還沒看到結果。
- 下一步的第一個指令：`git fetch origin main && git log --oneline origin/main -3`（看 #2594「145 更新說明」合了沒）。

## 還留下什麼

1. **145 更新說明**：#2594（分支 `claude/whatsnew-145`）合進 main 之後，併 `origin/main`，在 `Sources/GamePresentation/WhatsNew.swift` 的 145 那筆與 `.github/testflight-whats-new.md` 各加十行（一款一行、玩家看得懂、不寫暱稱與商標）。144 已發（e6728ee），遊戲 PR 可以合了。
2. **合併**：併 main 後等新 head 的 `Swift CI (gate)` 與 iOS App Build 綠，轉 ready、合併；CI 紅就修（圖包的三個摘要與 960／6,818,118 是在這個分支量的，併進別人新加的模型後要照測試印出的值更新 `Map3DModelPackLockTests`、`Map3DModelPackSizeTests`）。
3. **#2118**：合併後留言，全部做完留「145 模型接回 C 完成」，並 `send_message` 給協調者 session_01JMHz9ZYaf6dBe9otGWsXhV。
4. 模型本身留下的（不擋合併）：決策 930 §4。
