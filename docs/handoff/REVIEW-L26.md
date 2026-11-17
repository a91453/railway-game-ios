# REVIEW-L26 ＋ HEALTH-136（2026-11-17）

## 進度

- 做到：審查草稿寫好（`docs/research/REVIEW_L26_2026-11-17.md`，RESULT_* 待填）；健檢六組的前 16–18 個世界跑完，容器重開後剩下的世界用 scratchpad `resume-health.sh` 重跑（輸出 `health/<組>-b.log`）。
- 已驗證：release 建置 1,820 s、0 警告；羅瓦涅米兩條同一局：六組都 0/14 沒發、0 誤點，第一天 4 次各一分鐘、第二天 0。
- 下一步：重跑完 → `python3 -I scratchpad/summarize.py scratchpad/health`；再跑有乘客四格（`DEPOT_RETURN_PEOPLED=1`，`DEPOT_RETURN_ONLY=tymc|wenhu`）與 `COACH_HEALTH=1 COACH_HEALTH_ONLY=tra`。
