# E200 鳴日號風格（靜態 studies）

先讀 docs/art/e200-mingri-style/README.md。既有 E200CK 無獨立塗裝選用系統，故不新增營運接點。

```sh
PATH=/path/to/swift6.4/usr/bin:$PATH tools/train-models/run.sh OUT --ids e200mingri-style-head,e200mingri-style-car,e200mingri-style-tail,e200mingri-style-head-far,e200mingri-style-car-far,e200mingri-style-tail-far,set-E200CK-head,set-E200CK-car,set-E200CK-tail --assembly-spec tools/e200-mingri-style/assembly.json
node tools/train-models/package.mjs OUT
node tools/train-models/audit.mjs OUT
node tools/train-models/render.mjs OUT --views front,left,top,isometric
node tools/train-models/render.mjs OUT --views front,left,top,isometric --material clay
node tools/train-models/render.mjs OUT --views front,left,top,isometric --material silhouette
python3 tools/e200-mingri-style/audit.py MAIN_FULL_EXPORT FINAL_FULL_EXPORT
```

完整共存檢查用鎖檔全部 IDs 匯出 main 與 producer，逐原生bytes及全部頂點欄位FNV比對；不重寫鎖檔舊項。共用audit附編組錯位反例，專用audit附移殼／玻璃／燈色反例。近遠原始配方及完整八車展示保留拓樸，未做細分或幾何優化。舊遠景不滿「小於近景一半」是繼承限制，不放寬gate。
