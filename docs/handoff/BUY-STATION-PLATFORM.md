# BUY-STATION-PLATFORM：收購真實車站照真實鋪島式或岸式（決策 760）

- 派工：主規劃；工作串「收購時自動給正確島式或岸式」；雲端 thread session，branch `claude/project-thread-julwat`。
- 決策 760；存檔版本、golden、GameCore 不動。
- 做了：收購單一真實車站時，島式（含混合）鋪兩股隔 11 m、岸式（兩座側式）兩股隔 5 m，其餘照舊一股；型式表 `RealStationPlatformTypes.swift` 由 `tools/station-platform-types/make_swift_table.py` 產生。
- 還留下：混合站鋪三股（見決策 760「下一步」）；香港單站收購的型式表；`docs/handoff/STATION-BUY-STACK.md` 第 2 項（手鋪吸附真實中心線，3.15）沒動。
- UNVERIFIED：3D 畫面（島式月台有沒有畫出來）只在 Linux 測試量了兩股的距離，iPhone／Mac 的 3D 畫面沒看過，見 PR。
