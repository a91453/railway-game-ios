# SHARED-STATION-LEVEL（同一站兩條線的月台分兩層、疊在一起）

## 做了什麼

- 派工：協調者，作者 138 羅瓦涅米截圖（2026-11-18）。session：工作串「修同站兩線月台分開」，分支 `claude/project-thread-cmq7wt`。
- 決策 848。存檔（108）、golden（77）、GameCore、fixture 不動。
- 收購第二條線經過公司已有線的端點站時，鋪在原有股道旁（隔一座島式月台）、同一高度（`RealLineSharedStation.swift`）。
  羅瓦涅米 KJA／MUL 兩種順序同一高度、相隔約 9.7 m；竹中六家線仍在高架但不在內灣線頭上。
- 新測試 `SharedStationLayoutTests`（羅瓦涅米、香港、台灣竹中），新 skill `.claude/skills/real-line-laying/`。

## 還留下什麼

- 已經買了兩條線的存檔不會自己改：疊著的月台要拆線重買才會變（收購是記錄好的指令，重播照舊）。要不要給舊存檔一個「重鋪共站」的按鈕，沒有評分，需要時再排。
- 線中間經過公司車站的共站（不是端點）沒有處理；目前三張地圖量過沒有疊。
- 玩家自己用軌道工具蓋的高架、在上面加月台併入同一站，仍是玩家的選擇，沒有檢查。
- 同月台換乘的玩法另有工作串（PLATFORM-TRANSFER，`docs/priorities/CROSS-PLATFORM-TRANSFER.md`）。
- UNVERIFIED：iPhone 實機畫面（下一版 TestFlight）。
