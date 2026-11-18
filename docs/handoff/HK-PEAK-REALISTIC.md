# HK-PEAK-REALISTIC（2026-11-18）

- 派工：新專案協調者（`docs/priorities/HK-PEAK-CONTROL.md` 第 2 列、`docs/priorities/TIMETABLE-CHECKUP-ALL.md` 第 1 列 HK-AIRPORT-3-LATE、原本的 HK-EAL-LMC-RUNS）。雲端 Linux，分支 `claude/project-thread-9t5yav`，決策 849 加「後來」一節，沒有新決策號。
- 存檔版本不動（108）、golden schema 不動（77）；`GoldenScenarios/`、`ReplayFixtures/`、`SaveFixtures/` 沒有動。

## 做了什麼

- 決策 849「後來」：有閉塞區間（擬實）時，離下一站 14 km 以內、決策 294 不管的區間，也用決策 849 的進站號誌：整條路空著才出發的車只訂到下一站咽喉前，離號誌 1 km 內才拿進站的路。條件和新局規則一樣（折返或終到的站、不含空車、班次都跑全線且每站都停的路線）。`ApproachLocking.swift`、`RouteReservation.swift` 共三行。
- 落馬洲支綫漏班的成因：上水到落馬洲 7 km 一段，兩端各只有一組咽喉，出發就整段訂路等於單線輪流。新局那一半由 #2440 修好（15 → 0），擬實這一半這張修（4 → 0）。
- 時刻表體檢擬實：東鐵綫（落馬洲）、南港島綫、東涌綫、三條機場線一起買沒發全部歸零，將軍澳綫（康城）與六家線誤點歸零；機捷、文湖、高雄輕軌與其餘世界不變。數字在決策 849「後來」的表，`budgets` 已照表調低。
- HK-AIRPORT-3-LATE：沒有二分，同一個成因，修完是沒發 0、誤點 25（原上限 3、57），結案。

## 還留下什麼

- 東涌綫擬實還有 19 班晚開、尖峰空窗 +11 分；南港島綫擬實 91 班晚開（5 到 11 分）。沒有評新項目：都在原本 HK-PEAK-CONTROL 評分檔的範圍。
- TCL-DEPOT-CLAIM（新局規則，東涌綫收班兩次 1 分鐘死結）照舊未派。
- 改這一支的人要量 `hk SIL realistic`：路不空也先開到號誌前會讓它沒發 10 → 30（決策 849「後來」、depot-work skill 的表）。

## UNVERIFIED

- iOS 實機、畫面：沒看（雲端沒有 Xcode）。
- 量測是 Linux debug（GameCore -O）；新局規則只抽量 `tymc:A simple`、`hk SIL simple`、`hk TCL simple` 與 PR 版體檢（規則在沒有閉塞區間時一行都沒變）；CI 的 shard 由 PR 的 CI 跑。
