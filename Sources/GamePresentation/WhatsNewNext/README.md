# 下一版的「這版新增」 The next build's news

Decision 415's amendment (WHATSNEW-NEXT-FILES, 2026-11-25). A pull request
with news for players adds **one new file** here and changes no other file
of the list, so two pull requests never touch the same line and never
conflict on the news (the single `WhatsNewNext.swift` of #2675 did: GitHub
does not use `merge=union`, so every merge made the others conflict).

功能 PR 要給玩家看的一行，在這裡**新增一個檔**，不改別的檔：兩張 PR 不會改到同一行，就不會衝突。

## How to add a line 怎麼加一行

- What the player can now do: `new/`. What works again: `fixed/`.
  新功能放 `new/`，修好的放 `fixed/`。
- File name: `<YYYY-MM-DD>-<a-few-english-words>.txt`, the day the pull
  request is opened, for example `new/2026-11-25-kyushu-shinkansen-sale.txt`.
  The release reads them in file-name order, so the oldest day comes first.
  檔名：開 PR 那天的日期加幾個英文字，`.txt`。照檔名排序，早的在前。
- Two lines, English first:

  ```text
  en: The Kyushu Shinkansen from Hakata to Kumamoto is on sale on the Japan map.
  zh: 日本地圖可以買九州新幹線（博多到熊本）。
  ```

  Say only what the player can do, in a sentence or so; the Chinese line
  is at most 60 characters (`docs/UI_THEME.md`, 玩家看的文字).
  只說玩家能做什麼，一兩句；中文不超過 60 字。

`WhatsNewTests.testTheNextBuildsLinesAreReadyToRelease` checks every file:
its name, the two lines, the length, no line twice, and no line that a
released entry already has (a merge can bring back a file the release
removed).

## At a release 發版時

Every release writes its card (owner, 2026-11-28: the card stopped at 148
while 150 to 153 went out); `tools/release/testflight-local.sh` refuses to
release while a line waits here or the newest entry is not the build's
(`docs/TESTFLIGHT_LOCAL.md`). 每一版發版前都寫卡片；這裡還有行、或最上面那則不是這一版，本機發版腳本會停下來。

The game-planning session runs `python3 -I tools/whats-new/next.py`, which
prints these lines as `Line(english:chinese:)` ready for the new entry at
the top of `WhatsNew.entries`, moves them there (rewording where needed),
then deletes the files with `python3 -I tools/whats-new/next.py --clear`
(decision 415). These files are not in the app: the card shows only
`WhatsNew.entries`.

發版時遊戲規劃跑 `tools/whats-new/next.py` 印出要搬進 `WhatsNew.entries` 的行，搬完用 `--clear` 刪掉這些檔。這些檔不進 App。
