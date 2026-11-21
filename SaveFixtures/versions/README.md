# 存檔版本說明（一版一檔）

決策 910：`SavedGame.currentVersion` 每升一版，就在這裡加一個 `<N>.md`，寫第 N 版加了什麼、只讀得到前一版的程式碰到它會怎樣、更早的存檔要不要轉換。原本寫在 `Sources/GameCore/World/SavedGame.swift` 開頭的清單，每升一版都改同一段，平行的 PR 常在那裡衝突，所以一版一檔。

- 檔案照原文搬來，英文。新版可以用中文或英文。
- 81、88、96 版原本的清單就沒有寫說明，這裡也沒有（`SaveVersionNotesTests` 記著這三個空號，其他版本缺檔就紅）。
- 存檔本身照舊放在上一層 `SaveFixtures/`，規則看那裡的 README。
