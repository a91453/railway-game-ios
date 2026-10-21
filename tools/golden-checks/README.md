# tools/golden-checks

用 Python 標準函式庫寫的獨立檢查，不需要安裝任何套件。除了 `doc_numbers.py`，其他每支都照決策本文的規則，獨立算出 `GoldenScenarios/` 裡某一份 fixture 的值，再和 fixture 檔比對（例如 `city_buildings.py` 對決策 74）。用法寫在各支檔案開頭的說明。

## doc_numbers.py：文件數字一致性檢查

`docs/OVERVIEW.md` 第 2 節「現況數字」寫的號碼是人手補的，這支工具負責比對它們和 repository 裡的實際值（`docs/HANDOFF.md` 第 2 節、§7.4）。它只讀檔案，不改任何東西。

```sh
python3 -I tools/golden-checks/doc_numbers.py            # 印出比對結果，一律 exit 0
python3 -I tools/golden-checks/doc_numbers.py --check    # 有差異時 exit 1
python3 -I tools/golden-checks/doc_numbers.py --selftest # 用暫存目錄裡的假 repository 測這支工具
python3 -I tools/golden-checks/doc_numbers.py --root <路徑>  # 檢查別的 checkout（預設是這支工具所在的 repository）
python3 -I tools/golden-checks/doc_numbers.py --index    # 整份決策索引：OVERVIEW §9 加上 docs/decisions/
```

### 比對的數字

| OVERVIEW §2 的哪一列 | 讀的是 | 和什麼比 |
| --- | --- | --- |
| 存檔版本 | 開頭的數字 | `Sources/GameCore/World/SavedGame.swift` 的 `SavedGame.currentVersion` |
| 存檔版本 | 「共 N 個」 | `SaveFixtures/` 底下的 `*.json` 個數 |
| golden | 「schema N」 | `Tests/GameCoreTests/GoldenScenario.swift` 的 `GoldenScenario.schemaVersion` |
| golden | 「N 個 JSON」 | `GoldenScenarios/` 底下的 `*.json` 個數 |
| replay | 開頭的「N 個」 | `ReplayFixtures/` 底下的 `*.json` 個數 |
| 決策 | 括號前最大的號碼（「1–217、219–265（…）」讀成 265）；括號前沒有號碼（「見決策索引（§9）」）就不比，表上寫「不列（見 §9）」 | `docs/ARCHITECTURE.md` 與 `docs/decisions/` 最大的 `### N.` |

只算目錄本身的 JSON，不算子目錄，和讀這些檔案的測試一樣。所以 `ReplayFixtures/Reports/` 裡的問題回報範例不算 replay fixture。

### 決策號的檢查

| 情形 | 算差異 |
| --- | --- |
| ARCHITECTURE 的同一個 `### N.` 出現兩次以上 | 是 |
| ARCHITECTURE 有 `### N.`，決策索引（OVERVIEW §9）還沒有這一列 | 否，只列出來（2026-10-21 起 PR 只寫 ARCHITECTURE 自己預約的那一節，索引由遊戲規劃合併後補） |
| 決策索引有一列，ARCHITECTURE 沒有對應的 `### N.`（索引自己寫「保留後沒有使用」的列除外） | 是 |
| 決策索引寫「沒有使用」，ARCHITECTURE 卻有這一號 | 是 |
| 決策索引同一號不只一列 | 是 |
| ARCHITECTURE 的標題或索引的列順序不對 | 否，只列出來 |
| 1 到最大號之間缺的號碼 | 否，只列出來 |
| 續篇標題（`### 204（續）.`） | 否，只列出來，不算重複 |
| `docs/decisions/<N>.md` 的第一個 `### M.` 不是 N，或檔裡沒有 `### N.` 標題 | 是 |
| `docs/decisions/<N>.md` 有第二個決策標題（續篇標題除外） | 是 |
| 同一號同時在 ARCHITECTURE 與 `docs/decisions/` | 是 |
| `docs/decisions/` 的決策不在 OVERVIEW §9 | 不算，也不列：329 起那個目錄就是索引（決策 329） |

程式碼區塊（```` ``` ````）裡的 `### N.` 不算。決策索引在 OVERVIEW §9（1–328），ARCHITECTURE 開頭也寫明索引在那裡；`docs/decisions/` 裡檔名不是號碼的檔（`README.md`）不讀。`--index` 印出整份索引：§9 的列加上 `docs/decisions/` 每個檔的標題。

### 輸出

先印一張 Markdown 表（項目、OVERVIEW §2 寫的、程式或檔案、實際值、一致／不一致／讀不到），再列出差異與附註，可以直接貼進 PR。讀不到的數字（檔案不見、OVERVIEW 的寫法改了）算差異。

### 什麼時候跑

- 改了存檔版本、golden schema 或 fixture 個數的 PR，更新 OVERVIEW §2 之後跑一次 `--check`。新增決策的 PR 只加 `docs/decisions/<N>.md`，不改 ARCHITECTURE 的最後、OVERVIEW 的決策列與 §9（決策 329），跑一次 `--check`。
- 改這支工具本身時跑 `--selftest`。

CI 不會自動跑它。工具放在這裡而不是 `.github/scripts/`，因為改 `.github/scripts/` 會觸發完整的 Swift tier（HANDOFF 第 2 節）。
