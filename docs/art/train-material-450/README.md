# 列車的車窗反光與不鏽鋼光澤（決策 450）

`overview.png`：四款車頭（EMU800、EMU500、C341、太魯閣），等角視角。四欄：

1. 改前（main），14:00；
2. 改後，14:00；
3. 沒選的「較強」（鋼板 0.45 起、玻璃 `0.3 + 0.7 (1 − c)²`），14:00；
4. 改後，23:00。

做法：

```sh
tools/train-models/run.sh OUT --tag after --ids set-emu800-head,set-emu500-head,set-metroC341-head,set-taroko-head
node tools/train-models/render.mjs OUT --time both --views isometric             # 改前：不加旗標
node tools/train-models/render.mjs OUT2 --time both --views isometric --features 1  # 改後（OUT2 是同一次匯出的複本）
```

材質不改顏色，所以改前就是同一次匯出不加 `--features`。「較強」是暫時改 `renderer.js` 的兩個常數拍的，沒有留在工具裡。

這是 WebGL 預覽，不是 Metal：沒有霧、色調映射（決策 349），也沒有存在 `u` 的遮蔽，所以被遮住的面映得比遊戲裡多。實機的樣子與幀數 UNVERIFIED。
