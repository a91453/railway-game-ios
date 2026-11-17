# DOCNUM-CI＋CONFLICT-WATCH

## 進度

- 做到哪：PR 已開（見 #2118 的登記），等 CI。
- 已驗證：`swift-shards-selftest.sh` 全過（261 個 ok）；`conflict_watch.py --selftest` 過；對真 repository 的 `--dry-run`：open PR 2 張，#2355 衝突、#2364 可合；`doc_numbers.py --check` 差異 0。
- 下一步的第一個指令：在 PR 的檢查列表看 `Decision and document numbers (doc_numbers.py)` 有跑、`Swift CI (gate)` 等它。

## 派工

- 派工單：NEXT_PRIORITIES §29.29 第 1、2 列（兩列都是 bug，一張 PR）。規劃 session_01JMHz9ZJWaKh8kjuNDLtvar 派工。
- session：session_01JMHz9YzPuJx6TUnmdk2nXR；分支 `claude/docnum-ci-conflict-watch`。
- 決策 830（`docs/decisions/830.md`）。存檔版本、golden schema、GameCore、GamePresentation 都不動。

## 做了什麼

- **DOCNUM-CI**：`ci.yml` 新工作 `doc-numbers`；`swift-shards.sh decide` 多印 `docs=`（`doc_paths`），`swift-shards.sh gate` 多判 `DOCS_NEEDED`／`DOCS`。gate 名字沒改。
- **CONFLICT-WATCH**：`.github/workflows/conflict-watch.yml`＋`tools/ci-watch/conflict_watch.py`（含 `--selftest`、`--dry-run`）。
- `ios-build.yml` 的 paths-ignore 與 key 排除加上 `conflict-watch.yml`。CLAUDE.md 的 workflow 段落、`docs/decisions/README.md`、`tools/golden-checks/README.md` 同步。

## 還留下的（合併後要確認）

1. **CONFLICT-WATCH 第一次真的跑**（UNVERIFIED，只有合併後才會發生）：合併這張 PR 的那一次 push 就會觸發。
   - 到 Actions 的「Conflict watch」看那一次 run：Self-test 綠、log 列出每張 open PR 的狀態（`merges`／`conflicts; told`／`already told`）。
   - 那時還和 main 衝突的 PR（例如還沒併 main 的 #2355）應該多一則 github-actions[bot] 留言，開頭「和 main 衝突，CI 不會跑，請併 main。」，沒有 at 符號；下一次 push 不會再留第二則（log 寫 `already told`）。
   - 若 run 紅在留言那一步、錯誤是 403：權限不夠，把 `conflict-watch.yml` 的 `permissions` 加 `issues: write` 再試（GitHub 文件說 PR 上的 issue comment 用 `pull-requests: write` 即可，但這只有真的跑才知道）。
   - 也可以在 main 上手動跑（workflow_dispatch）看目前的 open PR。
2. **衝突的訂閱 session 真的被叫醒**：看下一次有 PR 衝突時，那個 session 有沒有收到留言事件、自己併 main。收不到（例如 bot 留言不送給訂閱者）就在 #2118 回報，改成別的叫法。
3. PRIO-FILES（§29.29 第 3 列）未派；做的時候 `swift-shards.sh doc_paths` 要認新目錄。
