# JA-LOCALIZATION 交接（日文介面，決策 1034）

2026-11-27，規劃4 工作串「做遊戲日文介面」，分支 `claude/project-thread-eqi1v5`。

## 做完的（第 1 張 PR）

框架：`DisplayLanguage.japanese`、`DisplayTextTemplate`（英文句子的鍵）、`TranslationTable`（一種語言一個表檔，
`Sources/GamePresentation/Translations/`）、抽字與合併工具 `tools/translations/`。App 還選不到日文。

## 做完的（第 2 張 PR，決策 1034 §6）

17 批日文都收齊合進去；語言選單有「日本語」；日本地圖站名、福岡與九州的線名、中性品牌有日文；帶數字的句子
改成依句型比對翻譯（Swift 一定選 `String` 多載，原本這些句子都是英文）。

## 還沒做的（下一個接手的串）

1. **日本 App Store 文案**（作者 11-27 交來，`/mnt/project-files/japanese-ui/store/ja-copy.md`）：和三語商店文字
   草稿放在一起（assets-2 `docs/research/STORE-COMPETITORS-2026-11-27.md`、`docs/handoff/APP-STORE-FREE.md`），
   核對說明文提到的功能與路線和遊戲現況一致（九州新幹線範圍、山陽博多—小倉要不要補），App 名稱沒有「鉄道」時
   照文件註記把關鍵字「運行」換成「鉄道」。日文介面上線（下一次 TestFlight）時一起用。
2. `switch` 英／中的幾處（路網摘要、班距、存檔摘要、新車到港、新聞，約 8 處）日文還走英文，改成 `text(英, 中)`。
3. 香港等其他地圖的線名日文仍是英文（站名有站名檔的 `ja`）。
4. 發行用的品牌（祕密 `GAME_BRAND_JSON`，作者的）可加 `"japanese": "…"`；沒有就照英文名。
5. 之後新增或改掉的句子：`python3 -I tools/translations/batches.py ja <資料夾>` 抽出還沒有日文的，給 Duet 譯，
   `merge.py` 合回（下面的指令）。

## 翻譯流程（留著給之後新句子用）

翻譯交給 Duet（作者 11-27）：4,413 句切成 17 批，放在專案共用資料夾 `japanese-ui/`（`PROMPT.md`、
`batch-01.md`…`batch-17.md`、`ids.json`、作者看的 `README.md`）。作者把 Duet 的回答交回串裡後：

```sh
python3 -I tools/translations/merge.py ja /mnt/project-files/japanese-ui/ids.json <回答檔…>
python3 -I tools/translations/extract.py --coverage ja
```

被退回的句子（`{n}` 或 `%@` 不對）列給作者請 Duet 重翻。`ids.json` 對的是 2026-11-27 的句子；之後新增或改掉的
句子用 `batches.py ja <資料夾>` 再抽一次（只列還沒有日文的）。
