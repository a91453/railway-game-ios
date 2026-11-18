# DEPARTURE-MELODY（發車旋律）

## 做了什麼

- 工作串「接回電車路線聲音與自製聲音」（雲端），分支 `claude/project-thread-7x486r`，[決策 853](../decisions/853.md)。存檔版本、golden schema、GameCore 不動。
- 在看的列車、60 倍以下、車門開始關時，響那條路線固定的一首原創發車旋律（三首，路線名稱雜湊挑）；終點站不響。取樣鋼琴＋豎琴／撥弦，7.8 秒，歸「車站鈴聲」音量。
- 試聽檔：私有素材庫 `railway-assets-private-2` 的 `game-art-previews/docs/art/departure-melody-2026-11/`（單獨三首與疊在主題曲上三首）。

## 還留下什麼

1. **作者聽**（UNVERIFIED）：試聽檔與實機跟車、駕駛；特別是疊在配樂上吵不吵、C 會不會尖。不喜歡哪一首就換那份樂譜重產（`python3 tools/audio/make_game_audio.py RailwayGameApp/Resources/Audio`，要下載約 400 MB 音色庫，見 `tools/audio/README.md`）。
2. **逐站自選鈴聲**（決策 219 第二階段另一半，GameCore＋存檔）與 **自製車站旋律工作坊**（第四階段）：評分在私有素材庫 `docs/priorities/DEPARTURE-MELODY.md`，由規劃派。
3. 網站的資料來源頁「音樂」一句（主題曲與發車旋律是原創）下次部署官網時一起改（技能 music-review §4）。
