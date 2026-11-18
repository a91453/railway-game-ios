# TIMETABLE-CHECKUP（2026-11-18，#2432）

全日時刻表體檢（決策 844）第一次跑完每一條有時刻表的在售線，抓到的、以前沒記的問題。數字是 `main` `2cd9c94` 第二天整天（決策 844 §5、§6），每一格的上限在 `Tests/GamePresentationTests/TimetableCheckupTests.swift` 的 `budgets`：修好的工作串把那一格調低。尺同 NEXT_PRIORITIES §19；bug 排在前面。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 狀態、注意 |
| --: | --- | --: | --: | --: | --: | --: | --: | --- |
| 1 | bug：**HK-EAL-LMC-RUNS** 香港東鐵綫（落馬洲）單買，新局沒發 15/208、誤點 157；擬實 4/208、誤點 133；上水早上 07:47 前後 25 分鐘沒車（表定最長 12） | 3 | 3 | 1 | 3 | 1 | 2.40 | 未派；重現：`TIMETABLE_CHECKUP=1 TIMETABLE_CHECKUP_ONLY="hk EAL_LMC simple" swift test --skip-build --filter TimetableCheckupFullTests/testHongKongLines`（約 20 秒） |
| 2 | bug：**WENHU-DEPOT-OUT** 文湖線新局 30 班從機廠出來就誤點（最晚 29.9 分），另有已知的 6/532 沒發 | 3 | 3 | 1 | 3 | 1 | 2.40 | 未派；和 DEPOT-DAWN-QUEUE 同一類，交那一串一起量（`TIMETABLE_CHECKUP_ONLY="trtc:BR simple"`，約 8 分鐘） |
| 3 | bug：**HK-TKL-LHP-LATE** 香港將軍澳綫（康城）兩種規則都 92/270 班開出晚 5 分以上（最晚 22 分），沒有漏班 | 2 | 3 | 1 | 3 | 1 | 2.10 | 未派；兩站短線，先看折返時間排不排得進時刻表（`TIMETABLE_CHECKUP_ONLY="hk TKL_LHP simple"`，約 4 秒） |
| 4 | bug：**SANYING-CTRL-MORNING** 三鶯線新局早上 5 班誤點、1 班出庫誤點，鶯桃福德 07:15 班距 13.7 分（表定 8） | 2 | 3 | 1 | 2 | 1 | 1.95 | 未派；PR 體檢 `TimetableCheckupTaiwanTests/testTheSanyingLineMorning` 就重現（10 秒） |
| 5 | bug：**LIUJIA-LATE** 六家線兩種規則都 3 班誤點 | 1 | 3 | 1 | 2 | 1 | 1.65 | 未派；`TIMETABLE_CHECKUP_ONLY="tra:LIUJIA simple"`（1 秒） |

五方：
- **玩家**：東鐵綫與文湖線的漏班、晚開在早上尖峰看得到（3）；將軍澳綫、三鶯線晚幾分鐘，看運行圖才注意（2）；六家線 3 班幾乎看不出（1）。
- **開發**：每一項都有幾秒到幾分鐘的重現指令與現值上限，修好就調低（3）。
- **美術**：無（1）。
- **音樂**：無（1）。
- **鐵道迷**：港鐵與文湖線是高密度、準點出名的線，尖峰空窗與晚開最不像真的（3）；三鶯、六家班次疏，晚幾分影響小（2）。
