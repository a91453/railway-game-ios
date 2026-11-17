# STUDIO-RUNNER：會展那一輪留下的筆記（還沒做）

工單本身是遊戲規劃在 #2118 開的 STUDIO-RUNNER（2026-11-16 21:55Z，評分與時機以那則為準：等 Mac 換到 Ultra 之後由新規劃派，**Mac 本機**）。
這份是本地派工 3 做 HKCEC-REDO 時，親手繞過 Orchestra 的每一處，給接這張單的 session 當清單。

## 為什麼

工作室（`~/AlongTheLine-Studio`，紀錄在素材庫 `local-studio-2026-11-10/`）疊在 Orchestra 上的東西，大多是在補 Orchestra 的缺口：

| 缺口 | 現在怎麼繞 |
| --- | --- |
| 開 session 選不了帳號 | 每個 Profile 各開一個「總機」終端機（`conductor.py serve --profile`） |
| 帶不了模型與強度 | 改 Profile 的設定檔；強度帶不了 |
| 叫人做事要作者按 Execute | 不用 request，改寫開場檔再關掉重開 |
| 只有 Orchestra 的終端機能開 session | 收件匣加總機 |
| 額度用完仍顯示「工作中」 | 協調者自己看記錄檔（會展第 2 輪停了一個半小時才發現） |
| 做完不通知、做的人交件後審查不會自己開始 | 協調者開背景看守、手動重開審查 |

認領、帳本、交接、Blender 鎖（`studio.py`）本來就是自己的，和 Orchestra 無關。Orchestra 真正提供的只有「在 worktree 開一個 AI」和「看得到每個 AI 在做什麼的畫面」。

## 要做的

一支啟動程式（取代 `conductor.py` 的 open／close／list，`studio.py` 照用）：

1. 在 worktree 直接開 Codex（`codex exec`）或 Claude（`claude -p`），開的時候指定帳號（`CODEX_HOME`／`CLAUDE_CONFIG_DIR`）、模型、強度，輸出寫進記錄檔。
2. 看記錄檔：額度用完就把沒 commit 的改動補 commit、換下一個帳號從那個 commit 接著開（開場檔前加「接手」一段）。
3. 做的人交件（帳本有交接單）就開審查；審查 needs-fix 就照開場檔開下一輪；做完、卡住、額度用完都留一行給協調者。
4. 狀態：一個指令列出每個位置在跑什麼、哪個帳號、最後一次寫檔是幾點。

先查：Antigravity 能不能不開視窗在背景跑；Codex、Claude 在背景跑時權限與核准怎麼設，才不會卡在等人按。

## 怎麼試

素材庫 `RUN-REMOTE.md` 排好的盲測（會展 revision-3、6、8 當考題，比 Hydrogen、Opus，建議加 Fable 高強度當第四組）就用新啟動程式跑。順了再把做與審的位置搬過來。
Orchestra 不拆，留給要作者插手的位置與看畫面。
