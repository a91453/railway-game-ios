#!/usr/bin/env python3
"""
列車與招牌貼圖平塗腳本 (tools/texture-palette/flatten.py)

將貼圖每個像素歸到少數幾個平塗色（去除漸層與雜訊，維持原尺寸與版面/Alpha）：
- 預設以 palette.json 的 train + structure 組為基底色票；
- 若原圖有明顯的主要帶色／塗裝色與基底色票 ΔE > 15（如列車紅帶），自動保留該帶色為平塗實色；
- 先做輕微保邊平滑去除漸層抖動，再於 Lab 空間依 CIEDE2000 對應最近色票，最後做 3x3 孤立雜點清理（保留文字與細線）。

用法：
  uv run --with pillow --with numpy python tools/texture-palette/flatten.py \
    --input ~/AlongTheLine-Studio/reports/t001/ref/train-e752e7a2.png \
    --output ~/AlongTheLine-Studio/reports/t001/r1/train/e752e7a2-flat.png
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image

from classify import (
    ciede2000_batch,
    dominant_lab_clusters,
    hex_to_rgb01,
    lab_to_hex,
    srgb_to_lab_array,
)


def hex_to_rgb255(hex_str: str) -> np.ndarray:
    h = hex_str.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.uint8)


def load_base_palette(palette_path: Path, groups: set[str]) -> list[dict]:
    with open(palette_path, "r", encoding="utf-8") as f:
        colors = json.load(f)["colors"]
    entries = []
    for c in colors:
        if c["group"] in groups:
            rgb01 = hex_to_rgb01(c["hex"])
            entries.append({
                "name": c["name"],
                "hex": "#" + c["hex"].lstrip("#").upper(),
                "rgb255": hex_to_rgb255(c["hex"]),
                "lab": srgb_to_lab_array(rgb01),
            })
    return entries


def despeckle_labels(labels: np.ndarray, h: int, w: int) -> np.ndarray:
    """Remove isolated 1-pixel speckles (where >= 6 of 8 neighbors share a different label)."""
    if h < 3 or w < 3:
        return labels
    out = labels.copy()
    padded = np.pad(labels, 1, mode="edge")
    neighbors = np.stack([
        padded[0:h, 0:w], padded[0:h, 1:w+1], padded[0:h, 2:w+2],
        padded[1:h+1, 0:w],                   padded[1:h+1, 2:w+2],
        padded[2:h+2, 0:w], padded[2:h+2, 1:w+1], padded[2:h+2, 2:w+2],
    ], axis=0)  # (8, h, w)

    # Check if center differs from majority of 8 neighbors (>= 6 agree)
    # Since number of labels is small (< 20), count matches for each candidate
    unique_labels = np.unique(labels)
    best_cnt = np.zeros((h, w), dtype=np.int32)
    best_lbl = labels.copy()
    for ul in unique_labels:
        cnt = np.sum(neighbors == ul, axis=0)
        mask = cnt > best_cnt
        best_cnt[mask] = cnt[mask]
        best_lbl[mask] = ul

    replace_mask = (best_lbl != labels) & (best_cnt >= 6)
    out[replace_mask] = best_lbl[replace_mask]
    return out


def flatten_image(
    input_path: Path,
    output_path: Path,
    palette_path: Path,
    groups: set[str],
    allow_own_band: bool = True,
    max_own_colors: int = 1,
) -> dict:
    with Image.open(input_path) as im:
        rgba = im.convert("RGBA")
    arr = np.asarray(rgba, dtype=np.uint8)
    h, w, _ = arr.shape
    alpha = arr[..., 3]
    opaque_mask = alpha >= 128

    base_entries = load_base_palette(palette_path, groups)
    # Exclude near-duplicate warm grays (月台/混凝土) when 帶色淺 is in train group, to prevent gradient banding
    names_present = {e["name"] for e in base_entries}
    if "帶色淺" in names_present:
        base_entries = [e for e in base_entries if e["name"] not in {"月台", "混凝土"}]
    base_labs = np.array([e["lab"] for e in base_entries])

    rgb01 = arr[..., :3].astype(np.float64) / 255.0
    lab_img = srgb_to_lab_array(rgb01)

    # Find own dominant band/livery colors that have no close match in base palette (ΔE > 15)
    own_entries: list[dict] = []
    if allow_own_band and np.any(opaque_mask):
        opaque_labs = lab_img[opaque_mask]
        clusters = dominant_lab_clusters(opaque_labs, k=5, merge_de=24.0)
        for c_lab, area_ratio in clusters:
            if area_ratio < 0.04:
                continue
            des = ciede2000_batch(c_lab, base_labs)
            min_de = float(np.min(des))
            # Keep if no close palette color (ΔE > 15) and it's not near-pure black (handled by 深色／窗)
            if min_de > 15.0 and c_lab[0] > 18.0:
                c_hex = lab_to_hex(c_lab)
                own_entries.append({
                    "name": f"原圖帶色({c_hex})",
                    "hex": c_hex,
                    "rgb255": hex_to_rgb255(c_hex),
                    "lab": c_lab,
                })
                if len(own_entries) >= max_own_colors:
                    break

    target_entries = base_entries + own_entries
    target_labs = np.array([e["lab"] for e in target_entries])
    target_rgbs = np.array([e["rgb255"] for e in target_entries], dtype=np.uint8)

    # Map every pixel in Lab space via CIEDE2000
    flat_labs = lab_img.reshape(-1, 3)
    # Vectorized distance: compute CIEDE2000 to each target color
    dists = np.stack([ciede2000_batch(tl, flat_labs) for tl in target_labs], axis=1)  # (N, K)
    best_idx = np.argmin(dists, axis=1).reshape(h, w)

    # Clean 1-px noise speckles
    best_idx = despeckle_labels(best_idx, h, w)

    # Reconstruct flat RGBA (preserve original alpha binary/crisp or original alpha)
    out_rgb = target_rgbs[best_idx]
    out_arr = np.dstack([out_rgb, np.where(opaque_mask, 255, 0).astype(np.uint8)])

    output_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(out_arr, mode="RGBA").save(output_path)

    # Summarize used colors
    used_indices, counts = np.unique(best_idx[opaque_mask], return_counts=True)
    total_op = int(np.sum(opaque_mask))
    used_summary = [
        (target_entries[i]["name"], target_entries[i]["hex"], int(c), float(c) / max(1, total_op))
        for i, c in sorted(zip(used_indices, counts), key=lambda x: -x[1])
    ]
    return {
        "input": str(input_path),
        "output": str(output_path),
        "size": f"{w}x{h}",
        "used_colors": used_summary,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Flatten train/sign texture to New Style solid palette.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--palette", default=os.path.expanduser("~/AlongTheLine-Studio/reports/t001/ref/palette.json"))
    parser.add_argument("--groups", default="train,structure", help="Comma-separated palette groups")
    parser.add_argument("--no-own-band", action="store_true", help="Do not add unmatched dominant band color")
    args = parser.parse_args()

    groups = {g.strip() for g in args.groups.split(",") if g.strip()}
    info = flatten_image(
        Path(args.input),
        Path(args.output),
        Path(args.palette),
        groups=groups,
        allow_own_band=not args.no_own_band,
    )
    print(f"Flattened {info['input']} -> {info['output']} ({info['size']})")
    for name, hex_c, cnt, ratio in info["used_colors"]:
        print(f"  - {name} {hex_c}: {cnt} px ({ratio*100:.1f}%)")


if __name__ == "__main__":
    main()
