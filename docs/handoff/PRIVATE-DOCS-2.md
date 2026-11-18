# PRIVATE-DOCS-2：獨門文件搬到私有庫（2026-11-18）

#2437 搬了工作室流程；#2442（railway-assets-private-2 #17）搬了交接總表、優先清單、評分檔與 art-style 的畫風規矩；第三批（這個檔所在的 PR 與 railway-assets-private-2 的同名分支）搬完下面這些。公開端原路徑都留指路短檔，私有那份章節號不變。

分法：工作室、派工單、審查、建模教訓、色票與美術風格、作曲、規劃與優先順序放私有 `a91453/railway-assets-private-2`（`docs/studio/`、`docs/planning/`）；公開 repo 只留建置、測試、程式風格與純程式規則。拿不準就放私有。

## 第三批搬了什麼

| 公開端（留短檔） | 私有端全文 |
| --- | --- |
| `.claude/skills/music-review/`（留量測指令、檔案格式、程式上的坑） | `docs/studio/skills/music-review.md` |
| 14 個 kit skill：civic、coach-bus、coastal、commercial、detail、estate、low-floor-bus、midi-bus、park、recreation、residential、shuttle-bus、station、works（留重建指令與檢查；SKILL.md 留在原處才會自動觸發） | `docs/studio/skills/<kit>.md` |
| `.claude/skills/model-look/`（留拍圖工具、停的條件、交付；`references/`、`evals/` 整個搬走） | `docs/studio/skills/model-look/` |
| `.claude/skills/rolling-stock/`（留配方結構、註冊表、近遠景、預算、雜湊、工具；`measure.cjs`、`preview.cjs` 留在原處） | `docs/studio/skills/rolling-stock.md` |
| `docs/handoff/` 建模、色票、音樂的 18 份 | `docs/studio/handoff/` |
| `docs/research/MODEL_AGE_2026-11-17.md`、`MODEL_PALETTE_REVIEW_2026-11-15.md`、`PRIVATE_ASSET_INVENTORY_2026-10-28.md`，與 `docs/art/model-age-2026-11-17/` 的兩份附表 | `docs/studio/research/` |

## 還留在公開、為什麼

- `depot-work`、`real-line-laying`、`economy-balance`、`diagnosing-bugs`、`motion`、`ui-review`、`meshy-3d-generation`：程式規則、除錯與 UI 做法，或是外部 MIT 授權的 skill。
- `art-style/preview.cjs`、`rolling-stock/measure.cjs`、`preview.cjs`：工具與網頁版的程式讀它們。
- 其他 `docs/handoff/`：功能、效能、CI、資料的交接，是程式工作。
- `docs/research/MESHY_TRIAL_MODEL_SPEC_2026-10-17.md`：Swift 原始碼與測試的註解指向它。
- `docs/art/` 各模型的 README 與 `native-vehicle-modeling/`（車輛建模手冊）：檔案很多、被許多決策與工具 README 引用，這批沒動；要搬的話另開一件，逐份看引用。

## 注意

- 搬之前先 grep 引用處：測試、`tools/`、`.github/` 讀的檔留在原處或改成一般寫法。這批查過，被搬的檔只有註解與文件提到。
- 已經推上公開 repo 的舊內容還在 git 歷史裡，搬走只擋得住以後新寫的。
