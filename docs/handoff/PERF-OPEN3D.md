# PERF-OPEN3D

- 派工單：PERF-OPEN3D（遊戲規劃第 63 任派；作者 2026-11-13 貼給 Mac 本機 session）。分支 `claude/perf-open3d`，PR #2107。
- session：Mac 本機（接實機 iPhone 17 Pro）。2026-11-13 壓縮過 2 次：這個 session 到此為止，只做完 #2107 自己的收尾。
- 決策 [713](../decisions/713.md)。存檔版本、golden、fixture、GameCore：都不動。

## 做了什麼

- **B 段（決策 713），做完，實機量過**：每次開 3D 第一格停一秒，是畫第一格時在主執行緒把 13 座機場重鋪一次（實機 927–1,023 ms；L19 P2-4 的答案：幾乎全部）。修法：登機橋端點每座機場只算一次、機場在背景鋪（`Map3DAircraft.Layer`）。實機那一格 CPU 最長 932–1,030 ms → 9–18 ms。數字、Time Profiler、試過又拿掉的做法在決策 713。
- 新測試 `Map3DAircraftLayerTests`（4 個）；另有只在給 `PERF_SAVE` 時才跑的 `Map3DAircraftLayingReportTests`。

## 還留下什麼

- **A 段（#2098 PERF-FAR 實機驗收）：沒有結論。** perf-far `f6d82e3` 與 main `cfc051d` 都裝上實機、用「整個臺灣」存檔拉到最遠各量了，但遙控的拖曳每次落在不同地點（新竹一帶的三個地方），不是同地點，不能比。量到的（都是 60 fps 上下、thermal serious）：perf-far 最多 153 萬與 170 萬三角形（兩次，不同地點）、main 199 萬（第三個地點）。報告裡 main 的 267–277 萬是臺北上空，這三次都沒有開到臺北。已在 #2098 留言說明。
  - **可靠的做法**（MAP3D-CAP 驗收用過）：兩個分支各建 Debug 版，用 `devicectl device process launch --terminate-existing … -- -screenshot-3d-view 距離,方位,傾角 -screenshot-3d-at 緯度,經度` 把鏡頭擺到同一個座標，再讀畫面右上的讀數。Release 沒有這兩個參數。
  - MAP3D-CAP 合進 main 之後「存檔 B 開 3D 再量一次」：沒做。
- **C 段（只量不改）：全部沒做。** 存檔 B 開 600× 每 tick 花多久、花在哪、「tick 最多佔 60%」的限制佔多少；放涼後的 3D 最遠與 3D 600×；乾淨條件下過一次午夜（L19 P2-3）；示範模式鋪高鐵抽查；`FIX-L19-P3.md` 六項 UNVERIFIED 各看一眼。
- 決策 713 的「下一步」：手動、放涼的手機上再量第 1 次開 3D 的格距（遙控下是 121 ms）。
- 下一張單 COACH-3D（決策 708）：這個 session 壓縮過，不接；請規劃另派。

## 實機量法（這次確認能用的）

- 遙控 UI 測試：FPS-DEVICE 那支不進 repo 的 `ZZRemoteControlTests`，執行檔還在那個 session 的暫存目錄。指令用分號串：`launch`、`wait 秒`、`tapid 識別字`、`taplabel 文字`、`tap x y`、`drag x1 y1 x2 y2 …`、`pinch 倍率 速度`（`pinch 0.5 -1` 拉遠）、`shot 名字`、`dump`。常用的識別字：`start.saves`、`saves.row.<檔名>`、`whatsNew.done`、`map.open3D`、`map3D.close`、`map3D.stats`。
- **它不會安裝 App**：`xctestrun` 裡的 `UITargetAppPath` 改了也沒用，手機上是哪一版就測哪一版。換版本要先 `xcrun devicectl device install app`。（這次一開始沒發現，量到的「main」其實是手機上原本的 #2105 版。）
- 換過版本後第一次開會跳「這版新增」，要先 `tapid whatsNew.done`。
- Time Profiler：`xcrun xctrace record --template 'Time Profiler' --device <udid> --all-processes --time-limit 55s`（`--attach` 用 PID 或名字都接不上實機的行程）；存檔要等十幾秒；`xctrace export --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]'` 匯出後自己依執行緒加總。
- 3D 開在哪裡不是 2D 畫面的中心看得出來的，同一串拖曳與點按在不同次會落在不同地點；要同地點就用上面 Debug 的啟動參數。

## 這台 Mac 與手機上留下的東西（不在 repo）

- 手機存檔備份：`~/RailwayGameDeviceBackups/2026-11-13-before-perf-open3d/`（這個 session 一開始）與 `~/RailwayGameDeviceBackups/2026-11-13-before-perf-open3d-device/`（開始在手機上裝東西之前）。
- 手機上的 App 現在是 main `cfc051d` 的 Release（開發簽章，build 127）。這個 session 來回裝過 main、perf-far `f6d82e3` 與這個分支。存檔清單沒有新增或刪除；「繼續」（自動存檔）被量測時的遊戲覆蓋過，作者的「整個臺灣」仍是清單裡「2026年11月13日 04:39」那一筆（`save-2026-11-12 203909.json`）。

## UNVERIFIED

- A 段與 C 段的一切（見上）。
- 本機只跑了快的檢查（`swift build --build-tests -Xswiftc -warnings-as-errors`、`Map3DAircraftLayerTests`、`Map3DAirfieldsTests`、`FollowAircraftTests`、`ReviewL19FixTests`，實機 Release 與模擬器 Debug 建置）；其餘交 CI。
- `Map3DAircraftLayingReportTests` 沒跑過（要 Release 的測試建置）。
- 跟著飛機：在模擬器上試過（這個分支的 Debug 版、「整個臺灣」存檔、桃園機場）。暫停時開 3D，飛機在背景鋪完後出現、跟隨列出現、沒有被踢出；按繼續後時間往前走，跟隨仍在。**沒試到的**：跟隨途中機場重鋪（場景原點或機場數變了）的情形，只讀過程式；跟隨只能在 3D 裡點飛機開始、關 3D 就放開，所以「已經在跟、再開 3D」從畫面上走不到。另有一次不暫停、600× 開 3D，15 秒後畫面有飛機但沒有跟隨列（那時遊戲已過約 3.5 小時，可能那班飛機已結束），沒有查出原因。
- 實機的數字都是遙控測試下、手機 thermal serious 時量的；沒有手動、放涼的數字。
