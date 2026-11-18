# ASSETS-REPO-2：第二個私有素材庫

## 進度

- 做完了（2026-11-18）：新庫 a91453/railway-assets-private-2 開張（#1，185 個小檔，舊庫來源 `bcd2a6b6`；#2 runner 預設先找新庫的 kit）；舊庫 a91453/railway-assets-private#160 寫了 `CLOSED.md`；a91453/railway-reference-private#150 的 `AGENTS.md` 改指這裡的 `docs/ASSET_REPOSITORIES.md`；這個 repo 的表、skill、`docs/HANDOFF.md` 開場的 `add_repo` 都改成新庫。Mac 已 clone 新庫、`studio.py init` 裝好 hook，工作室新任務用新庫。
- 已驗證：兩個素材庫的 guard 都綠；`next_repo.py seed`、`close` 實跑；studio-kit `tests.py` 86 個測試通過；Mac 上 doctor 對新庫全過。
- **只剩一件**：舊庫 #134、#143 與工作室在舊庫開工的東鐵綫第 4 輪都收完後，告訴遊戲規劃，由規劃請作者在舊庫 Settings 按 Archive（清單第 7 項）。

## 新 repo 建好後的清單

派工單 ASSETS-REPO-2，session_01YGNNuknSM2yzrpwkeQmuY3，三個 repo 的分支都是 `claude/project-thread-re5ii8`。

1. 新庫：作者建 repo 時勾「Add a README file」，`main` 就有第一個 commit；`seed`（會換掉那份 README）推到分支、開第一個 PR，不直接推 `main`。
2. 舊庫：`python3 -I tools/next_repo.py close --name a91453/railway-assets-private-2 --date <那天>`，開 PR。
3. 這個 repo：`docs/ASSET_REPOSITORIES.md` 兩列改狀態；`docs/HANDOFF.md` 的「先用 `add_repo` 加 …」（§ 新規劃開場那幾行）加上新庫，由遊戲規劃改。
4. `a91453/railway-reference-private` 的 `AGENTS.md` 寫「放到 railway-assets-private」那段改指 `docs/ASSET_REPOSITORIES.md`。
5. Mac（Remote Control；`~/Developer` 已授權）：clone 新庫到 `~/Developer/railway-assets-private-2`；用工作室資料夾的 `bin/studio.py init --repo` 加新庫的完整路徑裝 hook（指令格式照專案記憶 `studio-runner`：完整路徑、不接 `cd … &&`）；studio-kit 從新庫重裝（新庫的 `RUN-RUNNER.md` 安裝那行）。之後工作室新任務的 `--repo` 用新路徑；東鐵綫第 4 輪在舊庫做完。
6. 專案記憶 `private-repo-size`、`studio-runner`、`local-five-ai-studio`、`project-handoff-sop` 的路徑換成新庫（`docs/memory/` 的備份在新庫）。
7. 舊庫沒有開著的 PR、沒有在舊庫開工的工作室任務後，作者在 GitHub 舊庫 Settings 按 Archive（可以再取消）。

## 還沒驗證

- 新 repo 上 guard workflow 的第一次執行（要新庫有 PR 才會跑）。
- Mac 上 `studio.py init` 對新庫、`runner.py start --repo` 新路徑（要 Remote Control）。
