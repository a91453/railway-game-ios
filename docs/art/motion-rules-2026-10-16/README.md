# 介面動態的規則（決策 253）

`curves.png` 不是 App 的錄影。它用 SwiftUI 彈簧的公式（`spring(duration:bounce:)`：反應時間是 duration，阻尼是 1 − bounce）和 ease 曲線算出幾種寫法的動態。要比的是形狀：多快到位、有沒有超過、多久停下。圖是用 Python 腳本畫的，腳本放在 scratchpad，不放進 repo（和 art-style skill 的做法一樣）。

| 寫法 | 內容 |
| --- | --- |
| **A（選定）** | 照 LottieFiles motion-design-skill 改寫的 `MotionRule`：<br>- 小東西冒出來 0.25 秒，彈簧 bounce 0.2，稍微超過一點；<br>- 卡片進來 0.28 秒減速、離開 0.2 秒加速；<br>- 好消息跳一下，bounce 0.2；被拒絕左右搖三次、±6 點，一次比一次小。<br>減少動態效果時只留淡入淡出、時間減半，版面直接讓位。 |
| B（main 現在） | 每個 View 自己選：<br>- 名牌與建造泡泡 bounce 0.3；<br>- 狀態訊息不管好壞都用 bounce 0.5 跳一下，減少動態效果時也跳；<br>- 卡片與面板進出都是 0.2–0.25 秒、兩端平滑；<br>- 減少動態效果時大部分照樣滑動。 |
| C（沒選） | SwiftUI 內建的預設：`.bouncy`、`.smooth`、`.snappy`，都是 0.5 秒。比 LottieFiles 手機版的表慢一倍：卡片要半秒才到位，名牌超過的地方明顯，而且晚了 0.1 秒才超過。 |
| D（沒選） | 減少動態效果時全部直接出現，什麼都不淡入。這是參考庫的做法：`island_city_reference_clean` 的 `.card-in{transition:none}`，`street_scene_reference_clean` 把所有轉場設成 0.01 毫秒。LottieFiles 與 Apple 的建議是留著淡入淡出，東西出現或消失才看得出來。 |

看不到的部分要在 Simulator 或實機上看：
- 教學卡片打開與收合時從小一點長回來；
- 細節卡與面板從邊上滑進來；
- 減少動態效果打開時的樣子。
