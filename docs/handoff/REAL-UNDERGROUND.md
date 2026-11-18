# REAL-UNDERGROUND：收購的真實地下站鋪進隧道（決策 867）

- 派工：協調者，雲端工作串「把地下站鋪進隧道」，分支 `claude/project-thread-vs1idh`。
- 決策 867；存檔版本、golden schema、GameCore 不動。

## 做了什麼

香港、福岡的線照真實隧道鋪（決策 678 的規則多開兩張地圖，加三個小規則），3D 的地下站體同站不相鄰的月台各一個。
數字、價格、測試都在 `docs/decisions/867.md`。

## 還留下什麼

評分在 `a91453/railway-assets-private-2` `docs/priorities/REAL-UNDERGROUND.md`：

1. 台灣的小碧潭（七張）、機捷（環北、淡水河）開同一規則，各自量班次與機廠。
2. 福岡箱崎線中洲川端到吳服町缺隧道資料（舊購買順序時兩站留在地面）。
3. 舊存檔已買的線改建成地下。

## UNVERIFIED

- 沒有在 App、Simulator 或實機看過。下一版 TestFlight 請在香港買機場三綫，跟車進香港站、九龍看地下月台。
- 整天時刻表體檢（夜間）第一次跑到新鋪法時，看香港各格有沒有變。

## 怎麼量

```sh
REAL_UNDERGROUND_REPORT=/tmp/ug.txt swift test --skip-build --filter RealUndergroundTests/testReport
```
