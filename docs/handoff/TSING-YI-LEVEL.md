# TSING-YI-LEVEL：共站跟著已有月台的高度，旁邊車道的線也認得到橋（決策 875）

- 派工：協調者，雲端工作串「修青衣共站高度差」，分支 `claude/project-thread-69c8nd`。
- 決策 875；存檔版本、golden schema、GameCore 不動。

## 做了什麼

香港青衣的機場快綫與東涌綫月台原本差 9.5–11.6 m，現在三種購買順序都在同一座高架上、同一高度。
原因是機場快綫鋪在東涌綫旁 25 m 的車道，找真實的橋只找 20 m 內。改成三條不分地圖的規則：
旁邊車道的線找橋的範圍加上車道偏移；共站跟著公司已有月台的高度（高架上的也算）；鋪不上就照原來的鋪。
淡海濱海沙崙（照出售順序）也從差 3.2 m 變成同一高度。數字、價格、測試都在 `docs/decisions/875.md`。

## 還留下什麼

評分在 `a91453/railway-assets-private-2` `docs/priorities/TSING-YI-LEVEL.md`：

1. 竹中：六家線在高架、內灣線在地面，差 13.6／18.7 m。新規則試過會撞（六家線竹中端的路徑在站內和內灣線相交），照原來的鋪。
   要先改六家線竹中端的平面鋪法。
2. 機場快綫與東涌綫在青嶼幹線上高度還差最多 11.4 m（各自解坡度）。
3. 淡海舊順序（先藍海線、後綠山線，只有舊存檔）7 站仍差 9.5–17 m。
4. 已經兩條都買了的舊存檔不會變（決策 315）；要改得給改建的按鈕，和 REAL-UNDERGROUND 的舊存檔改建同一種工作。

## UNVERIFIED

- 沒有在 App、Simulator 或實機看過。下一版 TestFlight 請在香港買機場三綫，看青衣站（兩條線同一層）與青馬大橋上的兩條線。
- 機場三綫線組貴 4.5 %（機場快綫 +10.3 %，多了橋的建造費）、淡海藍海線 +6.3 %，沒有另外量整體經濟。
- 整天時刻表體檢只在本機跑了鋪法有變的 6 個世界（都和 `main` 的數字一樣，表在決策 875）；夜間的完整體檢第一次跑到新鋪法時，看香港各格有沒有變。
- 只買了機場快綫的舊存檔之後買東涌綫：沒有驗證（決策 875「還沒修」第 4 項）。

## 怎麼量

```sh
SHARED_STATION_REPORT=/tmp/shared.txt swift test --skip-build --filter SharedStationLayoutTests/testReport
# 一張地圖：SHARED_STATION_ONLY=hongkong（zhuzhong、danhai、rovaniemi、fukuoka）
# 整條線逐點的高度：SHARED_STATION_PROFILE=hkmtr:AEL,hkmtr:TCL
```
