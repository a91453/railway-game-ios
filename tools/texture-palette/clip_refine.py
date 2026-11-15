"""用 CLIP 修 classify.py 分不開的三類：整面建築立面、地圖／俯視平面、其他（t003 第 4 輪）。

classify.py 的規則只看顏色、亮度、紋路的週期，立面拼版、俯視圖、雜項三者常常分錯
（第 3 輪獨立審查：全體類別錯 16.7%，大半是立面掉進「其他」「地圖」）。這裡用 CLIP 的
圖像特徵，加上人工標的 192 張（`clip-labels.csv`，F 立面、M 俯視、其他字母都算其他），
訓練一個邏輯迴歸，只在模型很有把握（機率 ≥ 0.7）時改這幾種方向：

- 其他 → 立面、其他 → 地圖、地圖 → 立面、立面 → 地圖。
- 不做立面 → 其他、地圖 → 其他（抽看時約一半改錯，保留規則的結果）。

全部在本機跑，貼圖不會離開這台電腦。模型 ViT-B-16（laion2b_s34b_b88k，約 600 MB，
第一次跑時從 Hugging Face 下載）。輸出給 classify.py 的 --override。

    uv run --with open_clip_torch --with torch --with pillow --with numpy --with scikit-learn \\
        python tools/texture-palette/clip_refine.py --rules <第 3 輪 palette-map.csv> --out override.csv
    uv run --with pillow --with numpy python tools/texture-palette/classify.py --override override.csv --out <輸出>
"""

import argparse
import csv
import os
from pathlib import Path

import numpy as np
import open_clip
import torch
from PIL import Image
from sklearn.linear_model import LogisticRegression

HERE = Path(__file__).resolve().parent
CLASS = {"整面建築立面": "F", "地圖／俯視平面": "M", "其他": "O"}
NAME = {v: k for k, v in CLASS.items()}
MOVES = {("O", "F"), ("O", "M"), ("M", "F"), ("F", "M")}
SURE = 0.7


def embed(paths, device):
    model, _, pre = open_clip.create_model_and_transforms("ViT-B-16", pretrained="laion2b_s34b_b88k")
    model = model.to(device).eval()
    out = []
    with torch.no_grad():
        for i in range(0, len(paths), 64):
            batch = []
            for p in paths[i:i + 64]:
                im = Image.open(p).convert("RGBA")
                grey = Image.new("RGBA", im.size, (128, 128, 128, 255))
                batch.append(pre(Image.alpha_composite(grey, im).convert("RGB")))
            e = model.encode_image(torch.stack(batch).to(device))
            out.append((e / e.norm(dim=-1, keepdim=True)).cpu().numpy())
    return np.concatenate(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rules", required=True, help="classify.py（不加 --override）輸出的 palette-map.csv")
    ap.add_argument("--assets-dir", default=os.path.expanduser("~/SwiftRailMac/assets"))
    ap.add_argument("--labels", default=str(HERE / "clip-labels.csv"))
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    files = {}
    for p in sorted((Path(args.assets_dir) / "分類" / "貼圖").glob("*/item_*.png")):
        files.setdefault(p.name, p)
    with open(args.rules, encoding="utf-8-sig") as f:
        rules = {r["檔名"]: r["內容類別"] for r in csv.DictReader(f)}
    with open(args.labels, encoding="utf-8") as f:
        labels = {r["檔名"]: r["標記"] for r in csv.DictReader(f)}

    pool = [n for n, c in rules.items() if c in CLASS and n in files]
    train = [n for n in labels if n in files]
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    vectors = embed([files[n] for n in pool + train], device)
    x_pool, x_train = vectors[:len(pool)], vectors[len(pool):]
    y_train = [labels[n] if labels[n] in ("F", "M") else "O" for n in train]

    clf = LogisticRegression(C=8.0, max_iter=5000).fit(x_train, y_train)
    proba = clf.predict_proba(x_pool)
    moved = {}
    for n, p in zip(pool, proba):
        k = int(p.argmax())
        to = clf.classes_[k]
        if (CLASS[rules[n]], to) in MOVES and p[k] >= SURE:
            moved[n] = NAME[to]
    with open(args.out, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["檔名", "內容類別"])
        for n in sorted(moved):
            w.writerow([n, moved[n]])
    counts = {}
    for n, c in moved.items():
        key = f"{rules[n]} → {c}"
        counts[key] = counts.get(key, 0) + 1
    print(f"pool {len(pool)}, train {len(train)}, moved {len(moved)}: {counts}")


if __name__ == "__main__":
    main()
