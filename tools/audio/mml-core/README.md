# mml-core：MML Studio 的 JS 核心（複製）

`core.js` 是 `a91453/mml-tools` 的 `dist/core.js`，原樣複製，一個位元組都沒改（ARCHITECTURE 決策 219）。`mml_to_score.mjs` 用它把 MML 原稿讀成音符事件，再轉成《沿線》樂譜；整個 repo 只有這一份 MML 解析器，Python 和 App 都不解析 MML。

| 項目 | 值 |
| --- | --- |
| 來源 | https://github.com/a91453/mml-tools 的 `dist/core.js` |
| commit | `0a974f68c05112f2d871c5de837ae15d29fc9af2`（2026-09-29） |
| SHA-256 | `005950ad3837d8e80c98ef8052c8835aa9dcecd8937449f9ca8357bf8589373b` |
| 版本 | `VERSION` 0.1.0、`PROFILE` mobile-strict-2026-09-08 |
| 授權 | MIT，Copyright (c) 2026 a91453（同目錄的 `LICENSE`，原樣保留） |

`package.json` 只有 `"type": "module"`，讓 Node 把 `core.js` 當 ES module 讀；它不是 mml-tools 的檔案。

更新時：換成新的 `dist/core.js`，改這張表與 `make_game_audio.py` 的 `MML_CORE_COMMIT`，重跑轉換與 `make_game_audio.py`（它把新的 SHA-256 寫進 `tools/audio/manifest.json`），再跑 `--check`。
