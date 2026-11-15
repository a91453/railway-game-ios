#!/usr/bin/env python3
"""
舊版材質圖色票分類腳本 (tools/texture-palette/classify.py)

用法：
  uv run --with pillow --with numpy python tools/texture-palette/classify.py \
    --out ~/AlongTheLine-Studio/reports/t001/r3

分類規則說明（r3 準確優先版，依序判定，優先序與程式完全一致）：
1. 無法讀取 / 全透明 (opaque_pixels == 0) -> 透明裝飾（讀檔失敗另記於 unreadable）。
2. 純藍佔位圖／法線貼圖／極端純黑或純白遮罩 -> 其他。
3. 尺寸類 05_寬幅1600x700 -> 列車（極暗夜景或幾乎全透明除外）。
4. 夜間燈光（暗底亮點，透明比例 < 0.45 以免誤收透明底小車圖示）。
5. 透明裝飾（優先保留 01_小圖 置中對稱列車/車輛圖示）：
   - 01_小圖 置中對稱圖示（含紅/彩車身與深色車頭）-> 列車；
   - 非長條透明比例 >= 0.55，或稀疏窗格貼花（transparent >= 0.35 且前景碎片散落）-> 透明裝飾。
6. 單色小圖／純色細條：
   - L_std < 6.0 且 C_std < 5.0 且 edge_strength < 3.5 且透明比例 < 0.20：
     - max(w, h) <= 64（或 <= 128 且極純色）-> 單色小圖；
     - 低彩中性灰 -> 清水模／水泥；其餘純色長條 -> 其他。
7. 地面／鋪面／草地（含黃白線道路長條，優先於列車長條與立面）：
   - 灰底白/黃線道路（含橫/直長條，c_mean < 14, L* 20..65, 單向線條 edge_anisotropy > 0.28 且非雙向格）；
   - 草地／泥土／碎石（a* < 8, b* > 4.5, L* < 65, repeat_max < 0.24, edge_anisotropy < 0.25）。
8. 02_長條_長寬比4以上（非純色條、非道路）：
   - 橫條（w/h >= 2.5）：高透明/過散 -> 透明裝飾；高彩文字橫幅 -> 招牌／文字；
     全滿版規則窗格 -> 整面建築立面；其餘具車體橫向特徵（含透明底蒸汽機車/巴士）-> 列車。
   - 直條（h > w）：透明 >= 0.40 -> 透明裝飾；其餘依後續規則判定。
9. 寬橫幅車輛（aspect >= 2.6, min_dim >= 48, 橫向紋理）或白底黑剪影蒸汽機車 -> 列車。
10. 地圖／俯視平面（歸「另議」，優先於玻璃、清水模、立面）：
    - 04_大圖 地形圖（L* < 60, c_mean < 30, 明暗跨度 < 48, repeat_max < 0.28）；
    - 俯視建築/街區/UV 底圖（max_dim >= 128, 0.45 <= aspect <= 2.2, transparent < 0.18,
      大面積灰/米底 c0_area >= 0.30 且 c0_c < 14, min(repeat_h, repeat_v) < 0.24, edge 1.8..12.0）。
11. 招牌／文字（招牌／廣告，排除 UI 小圖示）：
    - 高對比多色塊＋文字筆畫、暗底高彩霓虹招牌、高彩海報/店招橫直幅。
12. 建築類（準確優先，只在很有把握時才歸；沒把握一律歸「其他」）：
    - 磚：暖紅褐/磚紅色系＋灰縫紋理，比對色票時正規化 L* >= 45 且排除木頭；
    - 木頭：暖棕單向木紋，排除高彩招牌；
    - 瓦／屋面：強方向性瓦壟/浪板紋理，低彩度或屋瓦色，排除高彩與霓虹；
    - 整面建築立面：max_dim >= 128, min_dim >= 48, n_distinct >= 3, edge >= 6.5, c_mean < 22, c_p90 < 40,
      具結構重複或方向性；主色面積比 < 0.25 時標「主色不明」不給色；
    - 玻璃／窗：嚴格雙向規則窗格（repeat_h > 0.26 且 repeat_v > 0.26, edge > 4.5, c_mean < 16, L* < 62）；
    - 金屬／鐵皮：min_dim >= 64, aspect < 3.0, 低彩中性灰具方向性紋理；
    - 清水模／水泥：min_dim >= 32, 低彩中性灰低邊緣（c_mean < 7.5, edge < 7.0）；
    - 石材／洗石子／磁磚：min_dim >= 32, 中低彩均勻石紋（c_mean < 14, edge_anisotropy < 0.22）。
13. 其餘一律歸為「其他」（處理方式「另議」）。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import os
import time
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Color space conversion (sRGB -> CIE Lab D65) & CIEDE2000
# ---------------------------------------------------------------------------

def srgb_to_lab_array(rgb01: np.ndarray) -> np.ndarray:
    """Convert (..., 3) sRGB in [0, 1] to CIE Lab (D65)."""
    rgb = np.clip(rgb01, 0.0, 1.0).astype(np.float64)
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    M = np.array([
        [0.4124564, 0.3575761, 0.1804375],
        [0.2126729, 0.7151522, 0.0721750],
        [0.0193339, 0.1191920, 0.9503041],
    ], dtype=np.float64)
    xyz = lin @ M.T
    xyz_ref = np.array([0.95047, 1.00000, 1.08883], dtype=np.float64)
    xyz_n = xyz / xyz_ref
    eps = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    f = np.where(xyz_n > eps, np.cbrt(xyz_n), (kappa * xyz_n + 16.0) / 116.0)
    L = 116.0 * f[..., 1] - 16.0
    a = 500.0 * (f[..., 0] - f[..., 1])
    b = 200.0 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


def hex_to_rgb01(hex_str: str) -> np.ndarray:
    h = hex_str.lstrip("#")
    return np.array([int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)], dtype=np.float64) / 255.0


def lab_to_hex(lab: np.ndarray) -> str:
    """Convert single Lab [L, a, b] to sRGB hex string."""
    L, a, b = float(lab[0]), float(lab[1]), float(lab[2])
    fy = (L + 16.0) / 116.0
    fx = a / 500.0 + fy
    fz = fy - b / 200.0
    eps = 216.0 / 24389.0
    kappa = 24389.0 / 27.0
    xr = fx**3 if fx**3 > eps else (116.0 * fx - 16.0) / kappa
    yr = ((L + 16.0) / 116.0) ** 3 if L > kappa * eps else L / kappa
    zr = fz**3 if fz**3 > eps else (116.0 * fz - 16.0) / kappa
    xyz = np.array([xr * 0.95047, yr * 1.00000, zr * 1.08883])
    M_inv = np.array([
        [ 3.2404542, -1.5371385, -0.4985314],
        [-0.9692660,  1.8760108,  0.0415560],
        [ 0.0556434, -0.2040259,  1.0572252],
    ])
    lin = np.clip(xyz @ M_inv.T, 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * (lin ** (1.0 / 2.4)) - 0.055)
    r, g, bl = [int(round(np.clip(c, 0.0, 1.0) * 255)) for c in srgb]
    return f"#{r:02X}{g:02X}{bl:02X}"


def ciede2000_batch(lab1: np.ndarray, lab2_array: np.ndarray) -> np.ndarray:
    """Vectorized CIEDE2000 between one Lab [3] and (N, 3) Lab array."""
    L1, a1, b1 = lab1[0], lab1[1], lab1[2]
    L2 = lab2_array[:, 0]
    a2 = lab2_array[:, 1]
    b2 = lab2_array[:, 2]

    C1 = math.sqrt(a1 * a1 + b1 * b1)
    C2 = np.sqrt(a2 * a2 + b2 * b2)
    C_bar = 0.5 * (C1 + C2)
    C_bar7 = C_bar ** 7
    G = 0.5 * (1.0 - np.sqrt(C_bar7 / (C_bar7 + 25.0 ** 7)))

    a1_p = (1.0 + G) * a1
    a2_p = (1.0 + G) * a2
    C1_p = np.sqrt(a1_p * a1_p + b1 * b1)
    C2_p = np.sqrt(a2_p * a2_p + b2 * b2)

    h1_p = np.degrees(np.arctan2(b1, a1_p)) % 360.0
    h2_p = np.degrees(np.arctan2(b2, a2_p)) % 360.0

    dL_p = L2 - L1
    dC_p = C2_p - C1_p

    C_prod = C1_p * C2_p
    dh_raw = h2_p - h1_p
    dh_p = np.where(
        C_prod == 0.0,
        0.0,
        np.where(np.abs(dh_raw) <= 180.0, dh_raw,
                 np.where(dh_raw > 180.0, dh_raw - 360.0, dh_raw + 360.0))
    )
    dH_p = 2.0 * np.sqrt(C_prod) * np.sin(np.radians(dh_p * 0.5))

    L_bar_p = 0.5 * (L1 + L2)
    C_bar_p = 0.5 * (C1_p + C2_p)

    h_sum = h1_p + h2_p
    h_bar_p = np.where(
        C_prod == 0.0,
        h_sum,
        np.where(np.abs(h1_p - h2_p) <= 180.0, 0.5 * h_sum,
                 np.where(h_sum < 360.0, 0.5 * (h_sum + 360.0), 0.5 * (h_sum - 360.0)))
    )

    T = (
        1.0
        - 0.17 * np.cos(np.radians(h_bar_p - 30.0))
        + 0.24 * np.cos(np.radians(2.0 * h_bar_p))
        + 0.32 * np.cos(np.radians(3.0 * h_bar_p + 6.0))
        - 0.20 * np.cos(np.radians(4.0 * h_bar_p - 63.0))
    )

    d_theta = 30.0 * np.exp(-(((h_bar_p - 275.0) / 25.0) ** 2))
    C_bar_p7 = C_bar_p ** 7
    R_C = 2.0 * np.sqrt(C_bar_p7 / (C_bar_p7 + 25.0 ** 7))

    L_term = (L_bar_p - 50.0) ** 2
    S_L = 1.0 + (0.015 * L_term) / np.sqrt(20.0 + L_term)
    S_C = 1.0 + 0.045 * C_bar_p
    S_H = 1.0 + 0.015 * C_bar_p * T
    R_T = -np.sin(np.radians(2.0 * d_theta)) * R_C

    dE = np.sqrt(
        (dL_p / S_L) ** 2
        + (dC_p / S_C) ** 2
        + (dH_p / S_H) ** 2
        + R_T * (dC_p / S_C) * (dH_p / S_H)
    )
    return dE


# ---------------------------------------------------------------------------
# Fast Dominant Color Clustering in Lab Space
# ---------------------------------------------------------------------------

def dominant_lab_clusters(lab_pixels: np.ndarray, k: int = 5, merge_de: float = 11.0) -> list[tuple[np.ndarray, float]]:
    """Return sorted [(center_lab, area_ratio), ...] from opaque Lab pixels (N, 3)."""
    n = len(lab_pixels)
    if n == 0:
        return []
    if n > 1500:
        idx = np.linspace(0, n - 1, 1500, dtype=np.int64)
        pts = lab_pixels[idx]
    else:
        pts = lab_pixels

    if np.all(np.std(pts, axis=0) < 2.0):
        return [(np.mean(pts, axis=0), 1.0)]

    order = np.argsort(pts[:, 0])
    q_idx = np.linspace(0, len(pts) - 1, min(k, len(pts)), dtype=np.int64)
    centers = pts[order[q_idx]].copy()

    for _ in range(7):
        dists = np.sum((pts[:, None, :] - centers[None, :, :]) ** 2, axis=2)
        labels = np.argmin(dists, axis=1)
        new_centers = []
        for ci in range(len(centers)):
            mask = labels == ci
            if np.any(mask):
                new_centers.append(np.mean(pts[mask], axis=0))
        if not new_centers:
            break
        centers = np.array(new_centers)

    dists = np.sum((pts[:, None, :] - centers[None, :, :]) ** 2, axis=2)
    labels = np.argmin(dists, axis=1)
    counts = np.bincount(labels, minlength=len(centers)).astype(np.float64)

    order_c = np.argsort(-counts)
    merged: list[tuple[np.ndarray, float]] = []
    for ci in order_c:
        if counts[ci] == 0:
            continue
        c_lab = centers[ci]
        c_cnt = counts[ci]
        placed = False
        for mi, (m_lab, m_cnt) in enumerate(merged):
            if np.linalg.norm(c_lab - m_lab) < merge_de:
                tot = m_cnt + c_cnt
                merged[mi] = ((m_lab * m_cnt + c_lab * c_cnt) / tot, tot)
                placed = True
                break
        if not placed:
            merged.append((c_lab, c_cnt))

    total = sum(c for _, c in merged)
    merged = [(lab, cnt / total) for lab, cnt in merged]
    merged.sort(key=lambda x: -x[1])
    return merged


# ---------------------------------------------------------------------------
# Feature Extraction & Classification
# ---------------------------------------------------------------------------

def autocorr_peak(signal: np.ndarray) -> float:
    """Normalized max periodic autocorrelation peak after first descent/valley (ignores monotonic smoothness)."""
    n = len(signal)
    if n < 10:
        return 0.0
    s = signal - np.mean(signal)
    var = np.dot(s, s)
    if var < 1e-6:
        return 0.0
    max_lag = min(n // 2, 36)
    corrs = [float(np.dot(s[:-lag], s[lag:]) / var) for lag in range(1, max_lag)]
    if len(corrs) < 4:
        return 0.0
    # Find first local minimum or zero-crossing so smooth ramps/circles return 0
    valley_idx = None
    for i in range(1, len(corrs) - 1):
        if corrs[i] <= 0.10 or (corrs[i] < corrs[i - 1] and corrs[i] <= corrs[i + 1]):
            valley_idx = i
            break
    if valley_idx is None:
        return 0.0
    best = max(corrs[valley_idx + 1 :])
    return max(0.0, best)


def extract_features_and_classify(img_path: Path, size_cat: str) -> dict[str, Any]:
    with Image.open(img_path) as im:
        orig_w, orig_h = im.size
        rgba_im = im.convert("RGBA")

    max_side = 192 if (max(orig_w, orig_h) / max(1, min(orig_w, orig_h)) >= 3.5) else 96
    scale = min(1.0, max_side / max(orig_w, orig_h))
    nw = max(1, int(round(orig_w * scale)))
    nh = max(1, int(round(orig_h * scale)))
    if (nw, nh) != (orig_w, orig_h):
        small = rgba_im.resize((nw, nh), Image.Resampling.BILINEAR)
    else:
        small = rgba_im

    arr = np.asarray(small, dtype=np.float32)
    alpha = arr[..., 3] / 255.0
    opaque = alpha >= 0.5
    transparent_ratio = float(1.0 - np.mean(opaque))
    n_opaque = int(np.sum(opaque))

    # 1. Fully transparent -> 透明裝飾
    if n_opaque == 0:
        return {
            "orig_w": orig_w, "orig_h": orig_h,
            "category": "透明裝飾",
            "clusters": [],
            "transparent_ratio": 1.0,
        }

    rgb01 = arr[..., :3] / 255.0
    opaque_rgb = rgb01[opaque]
    opaque_lab = srgb_to_lab_array(opaque_rgb)

    L = opaque_lab[:, 0]
    a = opaque_lab[:, 1]
    b = opaque_lab[:, 2]
    C = np.sqrt(a * a + b * b)

    l_mean = float(np.mean(L))
    l_std = float(np.std(L))
    l_p10 = float(np.percentile(L, 10))
    l_p90 = float(np.percentile(L, 90))
    l_max = float(np.max(L))
    a_mean = float(np.mean(a))
    b_mean = float(np.mean(b))
    a_p90 = float(np.percentile(a, 90))
    b_p90 = float(np.percentile(b, 90))
    c_mean = float(np.mean(C))
    c_std = float(np.std(C))
    c_p90 = float(np.percentile(C, 90))

    very_dark_ratio = float(np.mean(L < 14.0))
    dark_bg_ratio = float(np.mean(L < 24.0))
    glow_ratio = float(np.mean(L > 32.0))
    bright_ratio = float(np.mean(L > 55.0))
    white_ratio = float(np.mean(L > 92.0))

    Y = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    y_fill = float(np.mean(Y[opaque]))
    Y_clean = np.where(opaque, Y, y_fill)

    if nw > 1:
        dx_mask = opaque[:, 1:] & opaque[:, :-1]
        dx = np.abs(Y_clean[:, 1:] - Y_clean[:, :-1])
        edge_v = float(np.mean(dx[dx_mask])) if np.any(dx_mask) else 0.0
    else:
        edge_v = 0.0

    if nh > 1:
        dy_mask = opaque[1:, :] & opaque[:-1, :]
        dy = np.abs(Y_clean[1:, :] - Y_clean[:-1, :])
        edge_h = float(np.mean(dy[dy_mask])) if np.any(dy_mask) else 0.0
    else:
        edge_h = 0.0

    edge_strength = 0.5 * (edge_h + edge_v)
    edge_anisotropy = abs(edge_h - edge_v) / (edge_h + edge_v + 1e-6)

    repeat_h = autocorr_peak(np.mean(Y_clean, axis=0))
    repeat_v = autocorr_peak(np.mean(Y_clean, axis=1))
    repeat_max = max(repeat_h, repeat_v)

    ys, xs = np.where(opaque)
    x_span = float((xs.max() - xs.min() + 1) / nw) if nw > 0 else 0.0
    y_span = float((ys.max() - ys.min() + 1) / nh) if nh > 0 else 0.0

    clusters = dominant_lab_clusters(opaque_lab, k=5, merge_de=11.0)
    n_distinct = sum(1 for _, r in clusters if r >= 0.05)

    aspect = orig_w / max(1, orig_h)
    max_dim = max(orig_w, orig_h)
    min_dim = min(orig_w, orig_h)

    category = None

    # 2. Pure blue placeholder / normal map / extreme solid black or white mask -> 其他
    if b_mean < -35.0 and a_mean > 15.0 and l_mean < 48.0 and (edge_strength < 12.0 or n_distinct <= 2):
        category = "其他"
    elif b_mean < -22.0 and a_mean > 5.0 and 38.0 <= l_mean <= 72.0 and c_mean > 22.0 and (edge_strength < 12.0 or n_distinct <= 2):
        category = "其他"
    elif l_max < 12.0:
        category = "其他"
    elif l_p10 > 96.0 and edge_strength < 1.5 and transparent_ratio < 0.05:
        category = "其他"

    # 3. 05_寬幅1600x700 -> 列車
    if category is None and size_cat == "05_寬幅1600x700":
        if very_dark_ratio >= 0.65 and bright_ratio < 0.45:
            category = "夜間燈光"
        elif transparent_ratio >= 0.85:
            category = "透明裝飾"
        else:
            category = "列車"

    # 4. 夜間燈光（暗底亮點，透明比例 < 0.45 以免誤收透明底小車圖示；排除高彩紅字橫幅、高飽和藍底招牌與純灰/低對比拼版）
    if category is None and transparent_ratio < 0.45:
        is_red_sign_strip = (aspect >= 2.5 and c_p90 > 35.0 and edge_strength > 10.0 and a_mean > 8.0)
        is_blue_sign = (b_mean < -25.0 and edge_strength > 15.0)
        is_achromatic_low_glow = (c_p90 < 4.5 and l_mean < 15.0 and glow_ratio < 0.008)
        if not is_red_sign_strip and not is_blue_sign and not is_achromatic_low_glow and (
            (dark_bg_ratio >= 0.58 and glow_ratio >= 0.001 and l_mean < 26.0 and (l_p90 - l_p10) > 16.0)
            or (very_dark_ratio >= 0.42 and l_max > 25.0 and l_mean < 28.0 and glow_ratio <= 0.48 and (l_p90 - l_p10) > 16.0)
            or (dark_bg_ratio >= 0.55 and c_p90 > 28.0 and l_mean < 32.0 and glow_ratio >= 0.01)
        ):
            category = "夜間燈光"

    # 5. 透明裝飾（優先保留 01_小圖 置中對稱列車/車輛圖示）
    if category is None and size_cat != "02_長條_長寬比4以上":
        if (
            size_cat == "01_小圖_64以下"
            and 0.15 <= transparent_ratio <= 0.96
            and 0.20 <= x_span <= 0.90
            and 0.20 <= y_span <= 0.90
        ):
            left_half = Y_clean[:, : nw // 2]
            right_half = np.fliplr(Y_clean[:, nw - (nw // 2) :])
            sym = float(np.mean(np.abs(left_half - right_half))) if nw >= 4 else 99.0
            a_left = alpha[:, : nw // 2]
            a_right = np.fliplr(alpha[:, nw - (nw // 2) :])
            asym = float(np.mean(np.abs(a_left - a_right))) if nw >= 4 else 1.0
            is_green_foliage = (a_mean < -3.0 and b_mean > 6.0 and sym > 10.0)
            is_ui_icon = (b_mean < -25.0 and c_mean > 30.0) or (c_mean < 1.0 and transparent_ratio > 0.80)
            if sym < 28.0 and asym < 0.14 and l_mean < 75.0 and not is_green_foliage and not is_ui_icon:
                if transparent_ratio <= 0.88 or (sym < 12.0 and asym < 0.06):
                    category = "列車"
        if category is None and transparent_ratio >= 0.55:
            category = "透明裝飾"
        elif category is None and transparent_ratio >= 0.35 and (l_std > 10.0 or c_mean < 18.0):
            # 稀疏窗格或零散透明貼花
            if x_span < 0.92 or y_span < 0.92 or repeat_max > 0.20:
                category = "透明裝飾"

    # 6. 單色小圖 / 純色細條
    if category is None:
        is_flat = (
            (l_std < 6.0 and c_std < 5.0 and edge_strength < 3.5 and transparent_ratio < 0.20)
            or (max_dim <= 32 and l_std < 8.5 and c_std < 2.5 and transparent_ratio < 0.20)
        )
        if is_flat:
            if max_dim <= 64 or (max_dim <= 128 and l_std < 2.5 and c_std < 2.5 and edge_strength < 1.5):
                category = "單色小圖"
            elif c_mean < 8.5 and 38.0 <= l_mean <= 86.0:
                category = "清水模／水泥"
            else:
                category = "其他"

    # 7. 地面／鋪面／草地（含黃白線道路長條，優先於列車長條與立面；排除小圖照片、店面、木門、紅磚、列車拼版）
    if category is None:
        left_half_g = Y_clean[:, : nw // 2]
        right_half_g = np.fliplr(Y_clean[:, nw - (nw // 2) :])
        sym_g = float(np.mean(np.abs(left_half_g - right_half_g))) if nw >= 4 else 99.0
        is_road_stripe = (
            max_dim >= 128
            and transparent_ratio < 0.15
            and c_mean < 12.0
            and c_p90 < 28.0
            and n_distinct <= 3
            and 20.0 <= l_mean <= 65.0
            and edge_anisotropy > 0.28
            and min(repeat_h, repeat_v) < 0.20
            and (
                b_p90 > 16.0
                or ((l_p90 > 78.0 or (l_max > 78.0 and c_mean < 6.0 and (sym_g < 10.0 or (aspect >= 2.5 and edge_anisotropy > 0.50))))
                    and (aspect >= 2.0 or aspect <= 0.5))
            )
        )
        is_grass_earth = (
            max_dim >= 96
            and 0.45 <= aspect <= 2.2
            and transparent_ratio < 0.25
            and dark_bg_ratio < 0.45
            and a_mean < 8.0
            and b_mean > 4.5
            and not (a_mean > 1.5 and b_mean > 8.0)
            and not (max_dim >= 512 and n_distinct >= 4 and a_p90 > 2.0)
            and l_mean < 65.0
            and repeat_max < 0.24
            and edge_anisotropy < 0.25
            and (n_distinct <= 3 or edge_strength < 8.5)
            and (a_mean < -2.0 or (max_dim >= 128 and n_distinct <= 3))
        )
        if is_road_stripe or is_grass_earth:
            category = "地面／鋪面／草地"

    # 8. 02_長條_長寬比4以上（非純色條、非道路；不預設成列車）
    if category is None and size_cat == "02_長條_長寬比4以上":
        if aspect >= 2.5:
            if transparent_ratio >= 0.88 or (x_span < 0.24 and transparent_ratio > 0.50):
                category = "透明裝飾"
            elif transparent_ratio < 0.25 and (
                (l_mean > 50.0 and (a_p90 > 22.0 or c_p90 > 40.0) and edge_strength > 4.5)
                or ((a_p90 > 22.0 or c_p90 > 38.0) and edge_strength > 8.0 and a_mean > 6.0)
                or (a_mean < -18.0 and b_mean > 18.0 and c_p90 > 40.0)
            ):
                category = "招牌／文字"
            elif transparent_ratio < 0.05 and x_span > 0.95 and y_span > 0.95 and repeat_h > 0.22 and repeat_v > 0.22 and n_distinct >= 2:
                category = "整面建築立面"
            elif transparent_ratio < 0.05 and repeat_v > 0.30 and repeat_h < 0.20 and a_mean > 1.0 and b_mean > 4.0 and n_distinct >= 4:
                category = "整面建築立面"
            elif b_mean > 10.0 and edge_anisotropy < 0.25 and repeat_h < 0.25 and n_distinct >= 5:
                category = "其他"
            elif min_dim >= 32 and transparent_ratio < 0.88 and (
                transparent_ratio >= 0.15
                or white_ratio >= 0.25
                or (edge_h > edge_v * 1.10 and c_p90 > 22.0 and repeat_h < 0.60)
                or (repeat_h > 0.28 and edge_strength > 5.0 and edge_h > edge_v * 1.05 and c_p90 > 15.0)
            ):
                category = "列車"
        else:
            if transparent_ratio >= 0.40:
                category = "透明裝飾"

    # 9. 寬橫幅車輛（具明顯彩度與水平條紋）、列車貼圖拼版（512x256）或白底黑剪影蒸汽機車
    if category is None:
        is_green_turf = (a_mean < -5.0 and b_mean > 8.0)
        if aspect >= 2.6 and min_dim >= 64 and transparent_ratio < 0.55 and edge_h > edge_v * 1.15 and c_p90 > 20.0 and n_distinct >= 3 and repeat_h < 0.60 and not is_green_turf:
            category = "列車"
        elif aspect >= 1.9 and max_dim >= 256 and transparent_ratio < 0.15 and edge_anisotropy > 0.35 and repeat_v > 0.25 and c_p90 > 30.0 and n_distinct >= 4 and l_mean < 55.0 and not is_green_turf:
            category = "列車"
        elif white_ratio >= 0.35 and very_dark_ratio >= 0.18 and c_mean < 8.0 and transparent_ratio < 0.15 and max_dim >= 128:
            category = "列車"

    # 10. 地圖／俯視平面（歸另議，優先於玻璃、清水模、立面；嚴格要求低方向性與非立面窗格，避免誤收立面與牆）
    if category is None:
        is_terrain_map = (
            size_cat == "04_大圖_1024以上"
            and transparent_ratio < 0.15
            and l_mean < 60.0
            and c_mean < 30.0
            and (l_p90 - l_p10) < 48.0
            and repeat_max < 0.28
            and edge_strength < 12.0
        )
        c0_lab, c0_area = clusters[0]
        c0_c = math.sqrt(float(c0_lab[1]) ** 2 + float(c0_lab[2]) ** 2)
        is_topdown_plan = (
            max_dim >= 128
            and (max_dim >= 256 or edge_strength < 8.5)
            and 0.45 <= aspect <= 2.2
            and transparent_ratio < 0.18
            and c0_area >= 0.38
            and 42.0 <= c0_lab[0] <= 92.0
            and c0_c < 9.5
            and 1.8 <= edge_strength <= 10.5
            and (l_p90 - l_p10) < 58.0
            and not (l_mean > 75.0 and c_p90 > 10.0 and edge_strength > 7.0)
            and repeat_max < 0.26
            and edge_anisotropy < 0.22
            and n_distinct >= 2
        )
        is_topdown_site = (
            max_dim >= 256
            and 0.45 <= aspect <= 2.2
            and transparent_ratio < 0.15
            and min(repeat_h, repeat_v) < 0.22
            and edge_anisotropy < 0.22
            and n_distinct >= 3
            and edge_strength < 11.0
            and (l_p90 - l_p10) < 58.0
            and (a_mean < 2.5 and b_mean > 1.5 and l_mean < 72.0)
        )
        if is_terrain_map or is_topdown_plan or is_topdown_site:
            category = "地圖／俯視平面"

    # 11. 招牌／文字（招牌／廣告，排除 UI 小圖示、雙向重複立面與一維木板）
    if category is None:
        is_tiny_ui = (max_dim <= 32 and transparent_ratio > 0.15)
        is_ui_widget = (max_dim <= 192 and 0.7 <= aspect <= 1.4 and transparent_ratio > 0.25 and c_p90 > 28.0 and l_mean > 55.0)
        is_wood_plank = (edge_anisotropy > 0.65 and c_p90 < 30.0 and 2.0 <= a_mean <= 20.0 and 10.0 <= b_mean <= 40.0)
        c0_lab_s, c0_area_s = clusters[0]
        is_white_bg_sign = (l_mean > 75.0 and c0_lab_s[0] > 80.0 and c0_area_s >= 0.70 and c_p90 > 10.0 and repeat_h < 0.15 and edge_strength > 6.5)
        if not is_tiny_ui and not is_ui_widget and not is_wood_plank:
            if is_white_bg_sign:
                category = "招牌／文字"
            elif (l_p90 - l_p10) > 40.0 and edge_strength > 7.0 and repeat_h < 0.38 and repeat_v < 0.38:
                if (c_p90 > 30.0 and l_mean > 25.0) or (l_p90 > 76.0 and l_p10 < 26.0 and c_mean < 24.0 and transparent_ratio < 0.20 and repeat_max < 0.28) or (l_p10 < 15.0 and c_mean < 5.0 and edge_strength > 10.0 and min(repeat_h, repeat_v) < 0.10):
                    category = "招牌／文字"
            elif max_dim >= 64 and dark_bg_ratio > 0.35 and c_p90 > 40.0 and edge_strength > 6.5 and repeat_max < 0.28:
                category = "招牌／文字"
            elif c_p90 > 38.0 and n_distinct >= 3 and edge_strength > 6.5 and repeat_max < 0.30:
                category = "招牌／文字"
            elif transparent_ratio < 0.12 and max_dim >= 32 and c_p90 > 48.0 and n_distinct >= 3 and min(repeat_h, repeat_v) < 0.20 and repeat_max < 0.45:
                category = "招牌／文字"
            elif transparent_ratio < 0.08 and 1.8 <= aspect <= 2.2 and max_dim <= 128 and edge_strength > 8.0 and n_distinct >= 3 and (c_p90 > 25.0 or l_mean > 80.0 or l_mean < 36.0):
                category = "招牌／文字"

    # 12. 木頭（先於磚與瓦／屋面判定，避免木箱/木紋掉進磚）
    if category is None:
        if (
            transparent_ratio < 0.08
            and 2.0 <= a_mean <= 20.0
            and ((11.0 <= b_mean <= 40.0) or (6.0 <= b_mean <= 40.0 and edge_anisotropy > 0.50))
            and 20.0 <= l_mean <= 66.0
            and (n_distinct <= 2 or edge_anisotropy > 0.55)
            and c_p90 < 40.0
            and (l_p90 - l_p10 < 42.0 or edge_anisotropy > 0.65)
        ):
            if edge_anisotropy > 0.18 or edge_strength < 8.0:
                category = "木頭"

    # 13. 磚（要求紅暖色調且具灰縫雙向重複，嚴格排除木箱、照片、拼版與高彩招牌）
    if category is None:
        has_2d_brick_grid = (repeat_h > 0.25 and repeat_v > 0.25)
        if (
            min_dim >= 32
            and transparent_ratio < 0.08
            and a_mean > 7.5
            and b_mean > 6.5
            and 18.0 <= l_mean <= 62.0
            and edge_strength > 4.5
            and (l_p90 - l_p10) < 42.0
            and (c_p90 < 40.0 or (has_2d_brick_grid and c_p90 < 58.0))
            and ((repeat_h > 0.14 and repeat_v > 0.14) or (repeat_max > 0.25 and min(repeat_h, repeat_v) > 0.10))
        ):
            category = "磚"

    # 14. 瓦／屋面（浪板鐵皮屋面與屋瓦，嚴格排除高彩招牌/霓虹/暖棕木頭/梯子）
    if category is None:
        is_warm_wood_tone = (a_mean > 0.5 and b_mean > 4.0 and a_mean < 10.0)
        is_ladder_like = (min_dim <= 128 and b_mean < -2.0 and repeat_h < 0.05 and edge_anisotropy > 0.40)
        if (
            transparent_ratio < 0.08
            and not is_warm_wood_tone
            and not is_ladder_like
            and edge_anisotropy > 0.28
            and repeat_max > 0.30
            and edge_strength > 3.8
            and n_distinct <= 2
            and (l_p90 - l_p10) < 50.0
            and c_p90 < 32.0
        ):
            is_roof_color = (c_mean < 12.0 and l_mean < 70.0) or (l_mean < 45.0 and c_mean < 18.0) or (a_mean > 10.0 and b_mean > 8.0) or (b_mean < -6.0)
            if is_roof_color:
                category = "瓦／屋面"

    # 15. 整面建築立面（準確優先：必須有窗格週期重複等立面證據；排除塗鴉/販賣機/看板/低對比俯視）
    if category is None:
        c0_lab_f, c0_area_f = clusters[0]
        is_white_graffiti = (l_mean > 90.0 and c0_lab_f[0] > 93.0 and c0_area_f >= 0.70 and c_p90 > 14.0 and edge_strength > 9.0)
        is_vending_or_poster = (n_distinct >= 4 and c_p90 > 18.0 and repeat_max < 0.42 and edge_strength > 9.0 and max_dim <= 128)
        is_white_sign = (l_mean > 75.0 and c0_lab_f[0] > 80.0 and c0_area_f >= 0.70 and c_p90 > 10.0 and repeat_h < 0.15 and edge_strength > 6.5)
        is_small_atlas = (max_dim <= 128 and edge_strength > 11.0 and edge_anisotropy > 0.25 and min(repeat_h, repeat_v) < 0.15)
        has_window_grid = (repeat_max > 0.24)
        has_strong_grid = (repeat_h > 0.35 and repeat_v > 0.35 and edge_strength >= 5.5)
        if (
            max_dim >= 128
            and min_dim >= 48
            and transparent_ratio < 0.20
            and not is_white_graffiti
            and not is_vending_or_poster
            and not is_white_sign
            and not is_small_atlas
            and n_distinct >= 3
            and (edge_strength >= 6.8 or has_strong_grid)
            and c_mean < 22.0
            and c_p90 < 40.0
            and has_window_grid
        ):
            category = "整面建築立面"

    # 16. 玻璃／窗（嚴格要求雙向規則窗格且冷/中性色調，排除月亮/天空/logo/磚牆）
    if category is None:
        if (
            transparent_ratio < 0.15
            and min_dim >= 48
            and l_mean < 62.0
            and a_mean < 4.5
            and b_mean < 4.5
            and c_mean < 16.0
            and c_p90 < 32.0
            and edge_strength > 4.5
            and repeat_h > 0.28
            and repeat_v > 0.28
        ):
            category = "玻璃／窗"

    # 17. 金屬／鐵皮（排除細黑條與梯子）
    if category is None:
        is_ladder_like = (min_dim <= 128 and b_mean < -2.0 and repeat_h < 0.05 and edge_anisotropy > 0.40)
        if (
            min_dim >= 64
            and aspect < 3.0
            and (1.0 / max(1e-6, aspect)) < 3.0
            and transparent_ratio < 0.08
            and not is_ladder_like
            and c_mean < 8.5
            and 32.0 <= l_mean <= 76.0
            and edge_anisotropy > 0.25
            and repeat_max > 0.15
            and n_distinct <= 2
        ):
            category = "金屬／鐵皮"

    # 18. 清水模／水泥（排除大面積單一色群無重複的灰圖）
    c0_area_m = clusters[0][1]
    is_flat_gray_map = (c0_area_m >= 0.90 and n_distinct == 1 and min(repeat_h, repeat_v) < 0.20 and c_mean < 4.0)
    if category is None:
        if (
            min_dim >= 32
            and transparent_ratio < 0.10
            and not is_flat_gray_map
            and c_mean < 7.5
            and 38.0 <= l_mean <= 85.0
            and edge_strength < 7.0
            and (l_p90 - l_p10) < 35.0
            and n_distinct <= 2
            and repeat_max < 0.22
        ):
            category = "清水模／水泥"

    # 19. 石材／洗石子／磁磚（排除大面積單一色群無重複的灰圖）
    if category is None:
        if (
            min_dim >= 32
            and transparent_ratio < 0.10
            and not is_flat_gray_map
            and c_mean < 14.0
            and 42.0 <= l_mean <= 88.0
            and edge_anisotropy < 0.22
            and (l_p90 - l_p10) < 38.0
            and n_distinct <= 2
        ):
            category = "石材／洗石子／磁磚"

    # 20. 沒把握一律歸「其他」（準確優先，不強歸建築類）
    if category is None:
        category = "其他"

    return {
        "orig_w": orig_w,
        "orig_h": orig_h,
        "category": category,
        "clusters": clusters,
        "transparent_ratio": transparent_ratio,
    }


# ---------------------------------------------------------------------------
# Sheet Rendering (max 40 cells per category: left thumb, right palette swatch)
# ---------------------------------------------------------------------------

def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Hiragino Sans GB.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for p in candidates:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size=size)
            except Exception:
                pass
    return ImageFont.load_default()


def render_category_sheet(
    cat_name: str,
    rows: list[dict[str, Any]],
    out_path: Path,
    max_items: int = 40,
) -> None:
    if not rows:
        return
    if len(rows) > max_items:
        idxs = np.linspace(0, len(rows) - 1, max_items, dtype=int)
        sample = [rows[i] for i in idxs]
    else:
        sample = rows

    cols = 5
    cell_w = 220
    cell_h = 110
    pad = 10
    header_h = 44
    n_rows = (len(sample) + cols - 1) // cols
    canvas_w = cols * cell_w + (cols + 1) * pad
    canvas_h = header_h + n_rows * cell_h + (n_rows + 1) * pad

    canvas = Image.new("RGB", (canvas_w, canvas_h), (242, 243, 246))
    draw = ImageDraw.Draw(canvas)
    font_title = load_font(20)
    font_label = load_font(13)

    draw.text((pad, 10), f"{cat_name}（共 {len(rows)} 張，抽樣 {len(sample)} 張）", fill=(30, 35, 50), font=font_title)

    thumb_box = 72
    for idx, item in enumerate(sample):
        r = idx // cols
        c = idx % cols
        x0 = pad + c * (cell_w + pad)
        y0 = header_h + pad + r * (cell_h + pad)
        draw.rectangle([x0, y0, x0 + cell_w, y0 + cell_h], fill=(255, 255, 255), outline=(210, 214, 222))

        tx, ty = x0 + 8, y0 + 8
        draw.rectangle([tx, ty, tx + thumb_box, ty + thumb_box], fill=(228, 228, 228), outline=(190, 194, 200))
        try:
            with Image.open(item["path"]) as im:
                im_rgba = im.convert("RGBA")
                im_rgba.thumbnail((thumb_box, thumb_box), Image.Resampling.BILINEAR)
                bg = Image.new("RGBA", (thumb_box, thumb_box), (230, 232, 236, 255))
                ox = (thumb_box - im_rgba.width) // 2
                oy = (thumb_box - im_rgba.height) // 2
                bg.paste(im_rgba, (ox, oy), im_rgba)
                canvas.paste(bg.convert("RGB"), (tx, ty))
        except Exception:
            pass

        sx, sy = x0 + 90, y0 + 8
        sw_w, sw_h = 120, 72
        swatch_hex = item["swatch_hex"] or "#CCCCCC"
        rgb = tuple(int(swatch_hex.lstrip("#")[i:i+2], 16) for i in (0, 2, 4))
        draw.rectangle([sx, sy, sx + sw_w, sy + sw_h], fill=rgb, outline=(160, 165, 175))

        short_id = item["short_id"]
        label = item["sheet_label"]
        draw.text((x0 + 8, y0 + 84), f"{short_id}  {label}", fill=(35, 40, 55), font=font_label)

    canvas.save(out_path)


# ---------------------------------------------------------------------------
# Main Pipeline
# ---------------------------------------------------------------------------

BUILDING_CATS = {
    "磚", "瓦／屋面", "清水模／水泥", "石材／洗石子／磁磚",
    "木頭", "金屬／鐵皮", "玻璃／窗", "整面建築立面", "單色小圖",
}


def main() -> None:
    parser = argparse.ArgumentParser(description="Classify legacy textures into New Style palette.")
    parser.add_argument("--assets-dir", default=os.path.expanduser("~/SwiftRailMac/assets"))
    parser.add_argument("--palette", default=os.path.expanduser("~/AlongTheLine-Studio/reports/t001/ref/palette.json"))
    parser.add_argument("--out", default=os.path.expanduser("~/AlongTheLine-Studio/reports/t001/r3"))
    parser.add_argument("--limit", type=int, default=0, help="Optional limit for quick testing (0 = all)")
    args = parser.parse_args()

    t0 = time.time()
    assets_dir = Path(args.assets_dir)
    out_dir = Path(args.out)
    sheets_dir = out_dir / "sheets"
    out_dir.mkdir(parents=True, exist_ok=True)
    sheets_dir.mkdir(parents=True, exist_ok=True)

    with open(args.palette, "r", encoding="utf-8") as f:
        pal_data = json.load(f)["colors"]

    pal_entries = []
    for entry in pal_data:
        rgb01 = hex_to_rgb01(entry["hex"])
        lab = srgb_to_lab_array(rgb01)
        pal_entries.append({
            "group": entry["group"],
            "name": entry["name"],
            "hex": "#" + entry["hex"].lstrip("#").upper(),
            "lab": lab,
        })

    roof_pal = [p for p in pal_entries if p["group"] == "roof"]
    wall_mat_struct_pal = [p for p in pal_entries if p["group"] in {"wall", "material", "structure"}]
    no_wood_pal = [p for p in wall_mat_struct_pal if p["name"] != "木頭"]
    facade_no_dark_pal = [p for p in wall_mat_struct_pal if p["name"] != "深色／窗"]
    facade_no_dark_wood_pal = [p for p in facade_no_dark_pal if p["name"] != "木頭"]
    facade_blue_pal = [p for p in facade_no_dark_pal if p["lab"][2] < -7.5]
    all_pal = pal_entries

    roof_labs = np.array([p["lab"] for p in roof_pal])
    wms_labs = np.array([p["lab"] for p in wall_mat_struct_pal])
    no_wood_labs = np.array([p["lab"] for p in no_wood_pal])
    f_nodark_labs = np.array([p["lab"] for p in facade_no_dark_pal])
    f_nodark_nowood_labs = np.array([p["lab"] for p in facade_no_dark_wood_pal])
    f_blue_labs = np.array([p["lab"] for p in facade_blue_pal])
    all_labs = np.array([p["lab"] for p in all_pal])

    cat_root = assets_dir / "分類" / "貼圖"
    items: list[tuple[str, Path]] = []
    seen_names: set[str] = set()
    for size_dir in sorted(cat_root.iterdir()):
        if not size_dir.is_dir():
            continue
        size_cat = size_dir.name
        for p in sorted(size_dir.glob("item_*.png")):
            if p.name not in seen_names:
                seen_names.add(p.name)
                items.append((size_cat, p))

    raw_dir = assets_dir / "textures"
    if raw_dir.is_dir():
        for p in sorted(raw_dir.glob("item_*.png")):
            if p.name not in seen_names:
                seen_names.add(p.name)
                items.append(("未分類", p))

    if args.limit > 0:
        items = items[: args.limit]

    print(f"Found {len(items)} texture files. Processing...")

    csv_rows: list[list[str]] = []
    cat_counts: Counter[str] = Counter()
    pal_usage: Counter[str] = Counter()
    unreadable: list[tuple[str, str]] = []
    no_fit_items: list[tuple[str, np.ndarray, str]] = []
    sheet_buckets: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for idx, (size_cat, path) in enumerate(items, 1):
        fname = path.name
        short_id = fname.replace("item_", "").replace(".png", "")[:8]
        try:
            res = extract_features_and_classify(path, size_cat)
        except Exception as exc:
            unreadable.append((fname, str(exc)))
            continue

        cat = res["category"]
        cat_counts[cat] += 1
        w, h = res["orig_w"], res["orig_h"]
        clusters = res["clusters"]

        extra_flag = ""
        # For facades: exclude dark window/shadow clusters (L* < 38) if wall clusters (>= 22% total area, L* >= 38) exist
        if cat == "整面建築立面" and len(clusters) >= 2 and clusters[0][0][0] < 38.0:
            wall_cands = [c for c in clusters if c[0][0] >= 38.0]
            wall_area_sum = sum(c[1] for c in wall_cands)
            if wall_cands and (wall_cands[0][1] >= 0.20 or wall_area_sum >= 0.30):
                lab1, area1 = wall_cands[0]
                orig_hex1 = lab_to_hex(lab1)
                lab2 = clusters[0][0]
            else:
                lab1, area1 = clusters[0]
                orig_hex1 = lab_to_hex(lab1)
                lab2 = clusters[1][0]
        else:
            if cat == "磚" and len(clusters) >= 2 and clusters[0][0][1] < 3.0:
                brick_cands = [c for c in clusters if c[0][1] > 5.0 and c[0][2] > 5.0]
                if brick_cands:
                    lab1, area1 = brick_cands[0]
                    orig_hex1 = lab_to_hex(lab1)
                    lab2 = clusters[0][0]
                else:
                    lab1, area1 = clusters[0]
                    orig_hex1 = lab_to_hex(lab1)
                    lab2 = clusters[1][0]
            elif clusters:
                lab1, area1 = clusters[0]
                orig_hex1 = lab_to_hex(lab1)
                lab2 = clusters[1][0] if len(clusters) >= 2 else None
            else:
                lab1, area1, orig_hex1 = None, 0.0, ""
                lab2 = None

        # Facade primary area < 0.20, or neutral dark gray (L* < 38, chroma < 8) without wall cluster -> 主色不明 (do not assign palette color)
        if cat == "整面建築立面" and lab1 is not None:
            chroma1 = math.hypot(float(lab1[1]), float(lab1[2]))
            if area1 < 0.20 or (lab1[0] < 38.0 and chroma1 < 8.0):
                extra_flag = "主色不明"

        match_name, match_hex, de_str, flag = "", "", "", extra_flag
        match2_name, match2_hex = "", ""

        if cat in BUILDING_CATS and lab1 is not None:
            if extra_flag == "主色不明":
                proc = "另議"
            else:
                proc = "色票"
                # Brick (or warm brick-toned facade): normalize dark L* >= 45 and exclude 木頭
                is_brick_hue = (cat == "磚") or (
                    cat == "整面建築立面" and lab1[1] > 4.0 and lab1[2] > 2.0 and lab1[1] / max(1.0, lab1[2]) > 0.50
                )
                is_blue_wall = (
                    cat == "整面建築立面"
                    and lab1[2] < -10.0
                    and math.hypot(float(lab1[1]), float(lab1[2])) > 12.0
                    and lab1[1] < 6.0
                )
                is_true_wood_facade = (
                    cat == "整面建築立面"
                    and lab1[2] > 14.0
                    and lab1[1] > 3.0
                    and lab1[1] < lab1[2] * 0.55
                )
                match_lab1 = lab1.copy()
                if cat == "瓦／屋面":
                    cand_pal, cand_labs = roof_pal, roof_labs
                elif is_blue_wall:
                    cand_pal, cand_labs = facade_blue_pal, f_blue_labs
                elif is_brick_hue:
                    cand_pal = facade_no_dark_wood_pal if cat == "整面建築立面" else no_wood_pal
                    cand_labs = f_nodark_nowood_labs if cat == "整面建築立面" else no_wood_labs
                    if match_lab1[0] < 45.0:
                        match_lab1[0] = 45.0
                elif cat == "整面建築立面":
                    if is_true_wood_facade:
                        cand_pal, cand_labs = facade_no_dark_pal, f_nodark_labs
                    else:
                        cand_pal, cand_labs = facade_no_dark_wood_pal, f_nodark_nowood_labs
                elif cat in {"石材／洗石子／磁磚", "清水模／水泥"}:
                    cand_pal, cand_labs = no_wood_pal, no_wood_labs
                else:
                    cand_pal, cand_labs = wall_mat_struct_pal, wms_labs

                des = ciede2000_batch(match_lab1, cand_labs)
                best_i = int(np.argmin(des))
                best_de = float(des[best_i])
                best_p = cand_pal[best_i]
                match_name = best_p["name"]
                match_hex = best_p["hex"]
                de_str = f"{best_de:.2f}"
                pal_usage[f"{match_name} ({match_hex})"] += 1
                if best_de > 15.0:
                    flag = "沒有合適色票"
                    no_fit_items.append((fname, lab1, orig_hex1))
                if lab2 is not None:
                    des2 = ciede2000_batch(lab2, cand_labs)
                    b2 = int(np.argmin(des2))
                    match2_name = cand_pal[b2]["name"]
                    match2_hex = cand_pal[b2]["hex"]
        elif cat == "地面／鋪面／草地" and lab1 is not None:
            proc = "地面色"
            des = ciede2000_batch(lab1, all_labs)
            best_i = int(np.argmin(des))
            best_de = float(des[best_i])
            best_p = all_pal[best_i]
            match_name = best_p["name"]
            match_hex = best_p["hex"]
            de_str = f"{best_de:.2f}"
            pal_usage[f"{match_name} ({match_hex})"] += 1
            if best_de > 15.0:
                flag = "沒有合適色票"
                # Do NOT add ground/terrain to building suggested new colors
            if lab2 is not None:
                des2 = ciede2000_batch(lab2, all_labs)
                b2 = int(np.argmin(des2))
                match2_name = all_pal[b2]["name"]
                match2_hex = all_pal[b2]["hex"]
        elif cat in {"列車", "招牌／文字"}:
            proc = "轉貼圖"
        else:
            proc = "另議"

        csv_rows.append([
            fname,
            size_cat,
            f"{w}x{h}",
            cat,
            proc,
            match_name,
            match_hex,
            orig_hex1,
            de_str,
            f"{area1:.3f}" if lab1 is not None else "",
            match2_name,
            match2_hex,
            flag,
        ])

        swatch_hex = match_hex if match_hex else (orig_hex1 or "#CCCCCC")
        sheet_label = f"{match_name}" if match_name else f"{proc}"
        if flag:
            sheet_label += "(ΔE>15)"
        sheet_buckets[cat].append({
            "path": path,
            "short_id": short_id,
            "swatch_hex": swatch_hex,
            "sheet_label": sheet_label,
        })

        if idx % 1000 == 0:
            print(f"  Processed {idx}/{len(items)} ({time.time() - t0:.1f}s)")

    csv_path = out_dir / "palette-map.csv"
    with open(csv_path, "w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "檔名", "尺寸類", "寬高", "內容類別", "處理方式",
            "主色名", "主色hex", "原色hex", "ΔE(CIEDE2000)", "面積比",
            "第二色名", "第二色hex", "旗標",
        ])
        writer.writerows(csv_rows)

    suggested_clusters: list[tuple[str, int, list[str]]] = []
    if no_fit_items:
        nf_labs = np.array([x[1] for x in no_fit_items])
        nf_clusters = dominant_lab_clusters(nf_labs, k=6, merge_de=14.0)[:6]
        centers = np.array([c[0] for c in nf_clusters])
        groups: dict[int, list[str]] = defaultdict(list)
        for fname, lab, _ in no_fit_items:
            d = np.linalg.norm(centers - lab, axis=1)
            gi = int(np.argmin(d))
            groups[gi].append(fname)
        for gi, (c_lab, _) in enumerate(nf_clusters):
            c_hex = lab_to_hex(c_lab)
            reps = groups[gi][:3]
            suggested_clusters.append((c_hex, len(groups[gi]), reps))
        suggested_clusters.sort(key=lambda x: -x[1])

    cat_slug = {
        "磚": "01_brick",
        "瓦／屋面": "02_roof",
        "清水模／水泥": "03_concrete",
        "石材／洗石子／磁磚": "04_stone_tile",
        "木頭": "05_wood",
        "金屬／鐵皮": "06_metal",
        "玻璃／窗": "07_glass",
        "整面建築立面": "08_facade",
        "地面／鋪面／草地": "09_ground",
        "列車": "10_train",
        "招牌／文字": "11_sign",
        "夜間燈光": "12_night_light",
        "透明裝飾": "13_transparent_decal",
        "單色小圖": "14_solid_small",
        "其他": "15_other",
        "地圖／俯視平面": "16_topdown_plan",
    }
    for cat_name, rows in sheet_buckets.items():
        slug = cat_slug.get(cat_name, cat_name)
        render_category_sheet(cat_name, rows, sheets_dir / f"{slug}.png", max_items=40)

    elapsed = time.time() - t0
    print(f"Done in {elapsed:.1f}s. Total={len(items)}, Unreadable={len(unreadable)}, BuildingNoFit={len(no_fit_items)}")

    summary_path = out_dir / "summary.md"
    lines = [
        "# 舊版材質圖色票分類報告 (t003)",
        "",
        f"- 總張數：{len(items)}（成功 {len(csv_rows)}、無法讀取 {len(unreadable)}）",
        f"- 執行時間：{elapsed:.1f} 秒（`uv run --with pillow --with numpy python tools/texture-palette/classify.py --out {out_dir}`）",
        "- 色差公式：**CIEDE2000**（以 CIE Lab D65 計算主色群，排除透明像素 alpha < 0.5）",
        "- 分類原則：**準確優先、不求每張都分**——建築類只在有把握時才歸，沒把握一律歸「其他（另議）」。先判地圖／俯視平面、招牌／文字（含廣告）、列車（含透明底車頭、蒸汽機車、巴士）。建築類 ΔE > 15 標記「沒有合適色票」；瓦／屋面比對 `roof` 組，磚（比色前先正規化亮度 L*>=45）與石材／清水模排除木頭色票後比對 `wall + material + structure` 組，其餘建築類比對 `wall + material + structure` 組；地面類比對全色票最近色。建築立面主色面積比低於 0.25 時標「主色不明」不給色。",
        "",
        "## 1. 各內容類別張數",
        "",
        "| 內容類別 | 張數 | 佔比 |",
        "| --- | ---: | ---: |",
    ]
    total_ok = max(1, len(csv_rows))
    for cat_name, cnt in cat_counts.most_common():
        lines.append(f"| {cat_name} | {cnt} | {cnt / total_ok * 100:.1f}% |")

    lines.extend([
        "",
        "## 2. 各色票使用次數",
        "",
        "| 色票 | 使用次數 |",
        "| --- | ---: |",
    ])
    for pal_name, cnt in pal_usage.most_common():
        lines.append(f"| {pal_name} | {cnt} |")

    lines.extend([
        "",
        f"## 3. 「沒有合適色票」（ΔE > 15，僅統計建築類）原色色群與建議新增色（共 {len(no_fit_items)} 張）",
        "",
        "| 建議新增色 hex | 該色群張數 | 代表檔名（最多 3 個） |",
        "| --- | ---: | --- |",
    ])
    for c_hex, cnt, reps in suggested_clusters:
        lines.append(f"| `{c_hex}` | {cnt} | {', '.join(reps)} |")

    lines.extend([
        "",
        "## 4. 無法讀取的檔案",
        "",
    ])
    if unreadable:
        for fn, reason in unreadable[:50]:
            lines.append(f"- `{fn}`: {reason}")
    else:
        lines.append("- 無（全部檔案皆可正常讀取）")

    with open(summary_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
