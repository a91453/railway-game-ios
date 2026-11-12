# FIX-L19-P3：REVIEW-L19 的小修（2026-11-12）

- 派工單：FIX-L19-P3（遊戲規劃第 63 任派），session_01YGNNuoH56N95FQktyrXZTu，分支 `claude/fix-l19-p3`。
- 不佔決策號；GameCore、存檔、golden、ReplayFixtures、SaveFixtures 都沒動。
- 依據：[REVIEW_L19](../research/REVIEW_L19_2026-11-12.md) 的 P3。測試在 `Tests/GamePresentationTests/ReviewL19FixTests.swift`。

## 修了

| 項 | 做法 | 驗證 |
| --- | --- | --- |
| P3-3 | 四種飛機外形只算一次（`Map3DAircraftStudies.shape`）；`Laid.add` 多一個 `lit`，白天（畫面不畫光暈時）不算飛機燈，Metal 畫面把 `lampsLit` 交給它 | Linux 測試；Metal 那一段 UNVERIFIED |
| P3-4 | 一個小時的航班只排一次，之後不因為換日（新一天的架次、換季的跑道方向）重排；跑道方向照航班自己那一天 | Linux 測試 |
| P3-7 | `Kept.hours` 超過 200 筆時只丟離現在超過 4 小時的（畫面用到前後 2 小時，互相最多差 4；報告建議的 3 會把正在用的丟掉，測試抓到）；停著的飛機（`days`）只留當天 | Linux 測試 |
| P3-9 | 跟隨列的機型名改叫 `AirCollection.name`；城市機場場景的說明用同一個名字 | Linux 測試 |
| P3-10 | 「這版新增」四行「真實地圖」→「實景地圖」，英文 "real map" → "real-world map"（`WhatsNew`、`HelpGuide` 一句）；「起飛滾行」→「起飛中」；機場致謝的「臺灣」→「台灣」（和旁邊幾則一樣） | Linux 測試 |
| P3-13 | 圖鑑飛機頁與觀光景點面板的 `airportDays()` 改在背景算（`AirCollection.airportDays(of:)`） | Linux 測試；畫面 UNVERIFIED |
| P3-14 | 要開哪個展示台、看哪一架合成一個值（`Exhibit.Shown`），`fullScreenCover(item:)` 直接讀它 | Linux 測試；畫面 UNVERIFIED |
| P3-15 | 把手拖曳記「從哪裡按下、那時在哪一格」（`ManualDrive.Lever.Drag`）；按下的位置不同就是新的一次拖曳，從現在的格子起算 | Linux 測試；畫面 UNVERIFIED |
| P3-16 (a) | 手指下有車站時，只有機身中段在手指下的飛機才跟（`followable(…tight:)`、`GameSession.stationUnderMap3D`） | Linux 測試；畫面 UNVERIFIED |
| P3-17 (a) | 集集、保安站房的站名牌讀遊戲裡那一站的名字（`StationKitBuilder.boardName`）：同名或不是中文名（英文版的 Jiji）照掛真名；玩家取了別的名字時，筆畫表寫得出來就寫，寫不出來只掛「車站」 | Linux 測試；3D 畫面 UNVERIFIED |

## 沒修（理由）

- P3-16 (b) 駕駛中底部那一疊在小螢幕放不下：報告建議交給改視角列的工作，這裡不動版面（要截圖）。
- P3-17 (b) 集集擴建側翼深度：會改 3D 模型的樣子，要照 `model-look` 看圖，不是小修。
- P3-17 (c) `hkmtr` 不在 `systemOrder`：香港開關是關的，開香港前補。
- P3-5、P3-1/2、P3-6、P3-11/12、P3-18、P2-3、P2-4：派工單明說不做。P3-8、P2-1、P2-2 已在 main 修掉。

## 還留下的

- 站名牌的筆畫表只有「集、保、安、車、站、〇」六個字，所以改名的站多半只會看到「車站」；要寫任意站名得有整套字的筆畫（另案）。
- 站改名之後，站名牌要等那一塊場景重建才會換（沒有另外觸發重建）。
- 停在機位一整天的飛機（不是航班的那些）午夜仍會換一批位置：那是每天重抽，不在 P3-4 的範圍。
- 場景原點換了（`Laid` 重建）時航班快取照舊整個重來，屬於 P2-4。
- `.github/testflight-whats-new.md` 第 32 行的「真實地圖」沒改：那個檔每版重寫，留給規劃的 WHATSNEW-128 一起改，免得衝突。

## UNVERIFIED（要 Mac／模擬器／實機）

1. 圖鑑 → 飛機：連點不同的飛機卡，展示台開的是點的那一架；機場清單照常出現（晚一點點出現是正常的）。
2. 觀光景點面板的機場那一節照常出現。
3. 駕駛：拖把手到一半切到別的 App 或拉下通知中心再回來，下一次拖不會跳格。
4. 3D 地圖：機場旁的車站點得到；點飛機機身中段仍然跟得上；夜裡飛機燈照常、白天沒有差別。
5. 集集、保安：真實站照舊掛「集集車站」「保安車站」；在那裡自己蓋一站（別的名字）掛的是「車站」。
