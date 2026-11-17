# FULLLANE-135-2：135 full lane 剩下的三支紅（REVIEW-L25 P2-1、P2-2）

- 派工：遊戲規劃（#2118，2026-11-17），bug，要趕 136。
- session：session_01JMHz9ZHpeMj1RVpcasohgp（雲端），分支 `claude/fulllane-135-2`。
- 號碼：決策、存檔、golden 都不動。

## 做了什麼

### P2-1：橫拿＋最大字級，建造卡的 ✕ ✓ 膠囊跑出畫面（second 組兩支）

- 紅的：`RealWorldMapUITests.testThePlatformConfirmStaysAboveTheDockUnderATallBanner`（`map.build.confirm did not settle`）、`testTheUpgradePillStaysBesideTheTrackCard`（`The pill's ✓ cannot be tapped: (330, 476, 195, 47.7)`），main `89ed04b`，run 43936559208。
- 判斷：**畫面真的壞了，玩家會遇到**。second 組 xcresult 的兩段錄影（iPhone 17 Pro 橫拿）：鋪雙線和選月台位置時，膠囊是一條很窄、比畫面還高的直條，說明一個字一行（"o / f / s e c o n d / t r a c k ."），✓ 在畫面下方外面。
- 根因：決策 803 讓橫拿時每種建造的說明都放在 ✕ ✓ 旁邊（`.beside`）。旁邊有卡片、字又大時，膠囊最多只有 `minimumWidth`（160 pt）寬，✕ ✓ 加價錢就約 250 pt，說明那一欄分到的寬度是 0，只能一個字一行。134 時只有鋪軌用 `.beside`，所以那時是綠的。
- 修法：`BuildConfirmLayout.arrangement` 多一個 `roomBeside`（`wordsRoomBeside(pillWidth:buttonsWidth:)`：膠囊寬扣掉內距、間隔、量到的 ✕ ✓ 寬）。旁邊放不下最窄的說明（`minimumWidth`）時改回疊在按鈕上面（`.stacked`，134 的樣子）。App 量 ✕ ✓ 的寬（`MapBuildConfirm.buttonsWidth`）。有修正按鈕的拒絕（`.strip`）說明本來就橫在上面，不變。一般字級、空間夠時照舊放旁邊。
- Linux 測試：`BuildConfirmLayoutTests.testWordsWithNoRoomBesideTheButtonsStandOverThem`。

### P2-2：速度選單的觸控停在 600 倍（build 組一支）

- 紅的：`ShellLayoutUITests.testTheStatusBarKeepsItsWidthAsTheDaysGoBy`（`The touch did not choose 6000 times real time … Speed: 600 times real time`）。
- 判斷：**測試的問題，畫面沒壞**。App 自己的 trace（`ui-smoke-trace`）在那一刻記下 `touch began at (466, 351) view UIStackView` 接著 `touch cancelled`；前後幾秒 App 每次停兩秒（`longest gap 2089 ms`）。觸控被系統取消，速度沒變；玩家再點一次就好。
- 修法：`chooseSpeed` 沒選到就再選，最多三次；選單關了就再打開。每次沒選到在 log 印一行。

## 驗證

- VERIFIED（雲端 Linux，Swift 6.4）：`swift build --build-tests -Xswiftc -warnings-as-errors` 乾淨；`swift test --skip-build --filter BuildConfirmLayoutTests` 18 支全過。
- UI 測試：`ios-build.yml` 的 `only_testing` 跑這三支，結果寫在 PR。
- UNVERIFIED：實機沒看。
