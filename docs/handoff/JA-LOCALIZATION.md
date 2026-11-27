# JA-LOCALIZATION 交接（日文介面，決策 1034）

2026-11-27，規劃4 工作串「做遊戲日文介面」，分支 `claude/project-thread-eqi1v5`。

## 做完的（第 1 張 PR）

框架：`DisplayLanguage.japanese`、`DisplayTextTemplate`（英文句子的鍵）、`TranslationTable`（一種語言一個表檔，
`Sources/GamePresentation/Translations/`）、抽字與合併工具 `tools/translations/`。App 還選不到日文。

## 進行中

翻譯交給 Duet（作者 11-27）：4,413 句切成 17 批，放在專案共用資料夾 `japanese-ui/`（`PROMPT.md`、
`batch-01.md`…`batch-17.md`、`ids.json`、作者看的 `README.md`）。作者把 Duet 的回答交回串裡後：

```sh
python3 -I tools/translations/merge.py ja /mnt/project-files/japanese-ui/ids.json <回答檔…>
python3 -I tools/translations/extract.py --coverage ja
```

被退回的句子（`{n}` 或 `%@` 不對）列給作者請 Duet 重翻。`ids.json` 對的是 2026-11-27 的句子；之後新增或改掉的
句子用 `batches.py ja <資料夾>` 再抽一次（只列還沒有日文的）。

## 下一張（日文回來之後）

照決策 1034 §4：`project.yml` knownRegions 加 `ja`（重產 Xcode 專案）、`LanguageChoice` 加「日本語」、
日本地圖站名線名用日文、`GameBrand` 日文名、`switch` 英／中的幾處改成 `text(英, 中)`、退回英文句數的 Linux 測試。
日文商店頁等日文介面上線才貼（assets-2 `docs/research/STORE-COMPETITORS-2026-11-27.md` 第 9 節）。
