# SHINKANSEN-SALE 交接（九州新幹線上架，決策 975）

派工單：私有 repo `docs/priorities/JAPAN-KUMAMOTO.md` 第 4 列（2.90）。三串接力：前兩串在分支 `claude/project-thread-qgz3bv`（草稿 #2681，已關），第三串在 `claude/project-thread-a1vwtu`（#2684）收尾。決策 **975**（`docs/decisions/975.md`）。存檔版本、golden schema 不動；GameCore 只動一行（`TrackGauge.ofRealLine`）。

**做完了。** 這份檔留給之後碰九州新幹線、日本地圖鋪線的人：做了什麼看決策 975，這裡只寫留下的事與怎麼重做。

## 玩家看到什麼

日本地圖的收購清單多一條「九州新幹線」（博多到熊本 7 站），單獨賣。買下時鋪 7 個高架站（月台 200 m）、高架與隧道、熊本站南邊的車輛基地 8 股，沿線 7 塊地跟著買（新局 4 → 11 塊），8 組 8 節高鐵車一天 86 班。和地鐵誰先買都買得成；博多是一座站兩層（新幹線高架、地鐵地下）。

## 留下的事

1. **KUMAMOTO-OPEN（`JAPAN-KUMAMOTO.md` 第 5 列）要量的**：只買新幹線的價錢是土地 39,060,000,000、建造 22,986,337,457、列車 4,176,000,000（現有規則算的，7 塊 16 × 16 km 的地占一大半）。新局買不買得起、地價與里程碑要不要調，這張單沒有碰。
2. **KYUSHU-SHINKANSEN-EXPRESS**（還沒評分）：通過中間站的「瑞穗」「櫻」、直通鹿兒島中央與新大阪的車。現在每一班都各站停，時刻是估計。
3. **機廠在熊本站南邊，不在富合的真實位置**（待售的線只到熊本站）。線往南開到新八代時搬過去；真實位置在 `tools/fukuoka-map/kyushu-shinkansen/depot.json`。
4. ~~新幹線先買、再買地鐵時，地鐵的博多偏約 33 m~~：**決策 995 修好了**（空港線在自己的隧道裡時，新幹線高架上的股道不算擋路）。各站月台也照真實鋪了（博多 6 股、新鳥栖 4 股、筑後船小屋 3 股、熊本 4 股），見 `docs/decisions/995.md`。
5. **車輛模型**是別的單：N700 系（#2683，決策 977）、800 系（決策 978）。這張單只定了節數 8 與車種 `.highSpeed`；`Map3DRealTrains.swift` 沒碰。
6. **實機要看**（發版後）：日本新局買九州新幹線、博多站兩層的樣子、熊本車輛基地、列車進出博多。雲端沒有 3D 預覽圖；要看可用 `tools/map3d-preview/README.md` 的 `MAP3D_WORLD` 與 `MAP3D_BUY=kyushushinkansen:KS`（這張單沒試過這個指令對福岡的支援）。

## 測試在哪

- `KyushuShinkansenTests`：地圖包裡的線、高鐵車月台長、單獨買並跑一天。
- `SharedStationLayoutTests.testTheKyushuShinkansensHakataStandsOverTheSubways`：地鐵之後與之前買，博多一座站兩層、不疊（`uneven` 只有博多是故意的）。
- `RealLineBoughtAgainTests.testTheKyushuShinkansenIsBoughtAgain`：刪掉再買回來。
- `TimetableCheckupAllBoughtTests.testFukuokaShinkansen`（每晚與手動的整輪才跑）：兩種規則 0 班晚點，預算在 `CheckupBudgets/Fukuoka.swift`。
- 量測探針（每座月台的位置、被拒絕的是哪一段、每分鐘的進路與趕車狀態）在提交 `c84d886` 的 `Tests/GamePresentationTests/KyushuShinkansenTests.swift`：`KS_PROBE=1`、`KS_WHERE=1`、`KS_DAY=simple|realistic KS_UNTIL=<秒> KS_WATCH=<秒>`。要再量就從那個提交拿回來。

## 怎麼重做資料（都在 repo 根目錄跑，逐位元可重現）

```sh
pip install osmium   # build_kyushu_shinkansen.py 一開頭就 import
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py times tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/build_kyushu_shinkansen.py merge tools/fukuoka-map/kyushu-shinkansen RailwayGameApp/Resources/MapPacks/fukuoka
python3 -I tools/fukuoka-map/extract_fukuoka_runs.py RailwayGameApp/Resources/MapPacks/fukuoka
```

說明在 `tools/fukuoka-map/README.md` 的「九州新幹線」一節。

## 不要做的事

- 福岡包的地面檔（高度、水域、陡坡、建物）**不要重生**；不要為了新幹線重跑 `build_fukuoka_rail.py` 整包（每重做一次 git 多 45 MB）。
- 改共站規則前讀 `.claude/skills/real-line-laying/SKILL.md`：博多的兩層是唯一的例外，條件是「線在自己真實的高架上、公司那一站的月台全在地下」。
