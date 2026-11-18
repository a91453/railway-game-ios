# CIOPT-10（2026-11-18，#2427）

138 發版後的 CI 量測（[CI_MEASURE_2026-11-18](../research/CI_MEASURE_2026-11-18.md) §7）留下的一項；做了的寫在決策 719 的後來，交接在 `docs/handoff/CIOPT-10.md`。尺同 NEXT_PRIORITIES §19。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 狀態、注意 |
| --: | --- | --: | --: | --: | --: | --: | --: | --- |
| 1 | **LESSON-RESULT-JUMP** full lane 的 `LessonUITests` 三支（Again、Next、Keep Playing）各自從第一課的開線步驟鋪軌、蓋站、跑到過關（各 215–221 s），只為了按結果卡上不同的鈕；加一個 Debug 啟動參數直接開到第一課過關的結果卡，留一支照舊走完整條路 | 1 | 2 | 1 | 1 | 1 | 1.25 | 未派；要改 App 的 `DebugLaunch` 與 UI 測試，只能在 macOS 驗（`ios-build.yml` 的 `only_testing`）；lessons job 不在 full lane 的最長路徑上，省的約 6 分不會讓 full lane 早結束 |

五方：
- 玩家：無感（1）。
- 鐵道迷：無（1）。
- 開發：每晚少約 6 分 macOS、少兩次走同一條長路的機會出錯；但要加只給測試用的啟動參數（2）。
- 美術：無（1）。
- 音樂：無（1）。
