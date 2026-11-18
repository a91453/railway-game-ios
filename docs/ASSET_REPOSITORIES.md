# 素材庫在哪（Asset repositories）

新素材放哪**只寫在這裡**（決策 842）。規則檔與 skill 寫「目前收新素材的素材庫」時指的是這張表標「收新素材」的那一個；換庫時只改這張表，不去改每一份 skill。

| Repository | 狀態 | 期間 | 放什麼 |
| --- | --- | --- | --- |
| `a91453/railway-assets-private` | **收新素材** | 2026-10-28 起 | 預覽、截圖、模型與 viewer、工作室紀錄（`local-studio-2026-11-10/`）、宣傳片原片、`branding/`、規劃記憶備份（`docs/memory/`） |
| `a91453/railway-assets-private-2` | 準備中：作者建好空 repo 後由 `tools/next_repo.py` 帶小檔過去，然後這一列改成「收新素材」、上一列改成「已關閉」 | — | 同上 |
| `a91453/railway-reference-private` | 參考資料，不放素材 | — | 參考網站原始碼與資料快照（`CLAUDE.md` 列的那些）；2026-10-28 之前的素材已搬走 |

## 規矩

- **一個收新素材的庫**。大小到 3.5 GB（素材庫 `tools/asset_guard.py` 印的數字，每個 PR 都印）就開下一個，名字是原名加 `-N`（`railway-assets-private-2`、`-3`…）。
- **舊庫原樣留著、照舊可讀**：不搬重檔、不刪、不改寫歷史（素材庫 `AGENTS.md` 規則 8）。2026-11-18 之前文件、程式註解、決策裡寫的 `a91453/railway-assets-private` 路徑都還對，不用改。
- **關閉的庫有 `CLOSED.md`**：已開著的 PR 和已在那裡開工的工作室任務照舊在那裡做完；新的頂層資料夾、新的模型資料夾會被 guard 擋（規則 9），要開在新庫。
- 找舊輪次、同類車或建築時，**每一個素材庫都要找**，不只收新素材的那個（`model-look` §1）。
- 雲端 session 先用 `add_repo` 加上表中要用的庫；新庫也要在專案設定裡加進來。

## 換庫的步驟

素材庫 `AGENTS.md`「How to switch」是完整版。簡單說：

1. 作者在 GitHub 建私有 repo（勾「Add a README file」，`main` 才有第一個 commit，之後全走 PR），加進專案（唯一要作者動手的一步）。
2. 雲端 session：`python3 -I tools/next_repo.py seed --force …`（蓋掉那份 README）在新 repo 開第一個 PR（規則、guard、branding、記憶備份、工作室 kit、tools，加上排隊中派工單的文字檔與 `ref/` 照片；重檔不搬）。
3. 同一次：舊庫 `next_repo.py close` 寫 `CLOSED.md`；這張表改兩列。
4. Mac：在 `~/Developer/` 旁 clone 新庫、`studio.py init --repo` 裝工作室的 hook、從新庫重裝 studio-kit；之後 `runner.py start --repo` 用新庫的完整路徑。
5. 舊庫沒有開著的 PR、也沒有在那裡開工的工作室任務之後，才在 GitHub 按 Archive。
