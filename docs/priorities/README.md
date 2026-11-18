# 評分檔搬到私有庫（2026-11-18）

一項工作一個的評分檔（決策 832）與它的寫法，2026-11-18 起放在私有素材庫 `a91453/railway-assets-private-2` 的 `docs/priorities/`：優先順序是獨門做法，不放公開 repo。新的評分檔寫在那裡，不寫在這個資料夾。

格式檢查與併回仍用這裡的工具，`--root` 指到私有庫的 checkout：

```sh
python3 -I tools/golden-checks/doc_numbers.py --priorities --root ../railway-assets-private-2
```
