# 決策（329 起）

決策 1–328 在 `docs/ARCHITECTURE.md`，索引在 `docs/OVERVIEW.md` §9。**決策 329 起每個決策一個檔，放在這裡**（決策 329）。

- **檔名是號碼**：`329.md`、`330.md`……
- **第一個標題是 `### N. 標題`**，和 ARCHITECTURE 的寫法一樣，所以 `grep -rn '^### 330\.' docs/` 找得到兩邊的決策。
- **一個檔一個決策**。續篇用 `### N（續）. 標題`，寫在同一個檔裡；之後的修正照舊寫成「**後來**」段落，加在那個決策的檔裡。
- **號碼照 #231 登記**（CLAUDE.md Workflow）：取 main 與 #231 還沒釋出的登記裡最大的號碼加一。不用先在 main 放預約的檔：登記就是預約。兩個 PR 撞號時，兩個檔同名，第二個合併的會衝突，照登記先後改號。
- **不用改 OVERVIEW §9**：這個目錄就是 329 起的索引。要看整份索引（1–328 的列加上這裡的檔）：

  ```sh
  python3 -I tools/golden-checks/doc_numbers.py --index
  ```

- 1–328 的決策要補「後來」，照舊改 ARCHITECTURE 裡那一節。
- `python3 -I tools/golden-checks/doc_numbers.py --check` 會檢查：檔名和標題的號碼一致、一個檔只有一個決策、同一號沒有同時在 ARCHITECTURE 和這裡。
