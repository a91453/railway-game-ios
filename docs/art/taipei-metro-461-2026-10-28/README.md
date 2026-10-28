# 台北捷運 C371、C381、610 接進營運（決策 461）

`overview.png`：`tools/train-models/render.mjs` 的等角圖（WebGL 加決策 370 的遊戲模型光，不是 Metal、不是 iPhone 的畫面），每格上白天、下夜晚。夜晚的燈罩在這個工具裡不發光，遊戲裡頭車白、尾車紅。

- 第一列：舊的通用車（決策 461 前 key 叫 `metroC381`）的頭車與中間車；`set-metroGeneric-head` 是改名後的同一台車（雜湊相同），高雄、桃園、台中照舊畫它。
- 第二列：C381 近景頭車、遠景頭車（`metroC381Far`，500–900 m）、近景中間車（`m`）。
- 第三列：C371 近景頭車、遠景頭車（`metroC371Far`）、近景中間車（`t`）。
- 第四列：環狀線 610 近景頭車、遠景頭車（`light`）、近景中間車（`d`，`middleBack`）。

重建：

```sh
tools/train-models/run.sh OUT --tag after
node tools/train-models/render.mjs OUT --time both --ids set-metroC381-head,...
python3 -I tools/train-models/overview.py COMBINED overview.png --time both old-set-metroC381-head old-set-metroC381-car set-metroGeneric-head set-metroC381-head set-metroC381Far-head set-metroC381-centre set-metroC371-head set-metroC371Far-head set-metroC371-car set-circular610-head set-circular610Far-head set-circular610-carBack
```

`COMBINED` 是 `OUT` 的 `png/` 加上合併前 `main`（83509fb）匯出的舊 `set-metroC381-*` 等角圖，檔名前加 `old-`。七向圖（白天、夜晚、遠景）在 `a91453/railway-assets-private` 的 `game-art-previews/docs/art/` 下 `c371-set-2026-10-28/`、`c381-set-2026-10-28/`、`taipei610-set-2026-10-28/`、`metro-generic-2026-10-28/` 的 `revision-1/`。

外觀是 Codex 的原樣（#1324 起的研究模型），這次只點亮頭尾的燈並做遠景；外觀的接受與實機樣子 UNVERIFIED。
