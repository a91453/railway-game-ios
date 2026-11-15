#!/usr/bin/env python3
"""
將有貼圖的舊版列車 GLB 依平塗貼圖色塊邊界在 UV 空間切開，
轉成「無貼圖、無 UV、一個三角形一個頂點色（COLOR_0 linear RGBA float）」的 GLB。

用法：
  uv run --with pillow --with numpy python tools/texture-palette/cut_faces.py \
    --glb ~/SwiftRailMac/assets/models/item_e752e7a2b53bfd78eef72105.glb \
    --flat ~/AlongTheLine-Studio/reports/t001/r1/train/e752e7a2-flat.png \
    --palette ~/AlongTheLine-Studio/reports/t001/ref/palette.json \
    --out-dir ~/AlongTheLine-Studio/reports/t002/r2 \
    --min-area 22 --rdp-eps 1.8
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import time
from collections import Counter, defaultdict, deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from classify import ciede2000_batch, hex_to_rgb01, srgb_to_lab_array


# ---------------------------------------------------------------------------
# Color & Palette Helpers
# ---------------------------------------------------------------------------

def srgb01_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def load_palette(palette_path: Path, groups: set[str]) -> list[dict]:
    with open(palette_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    entries = []
    for c in data["colors"]:
        if c["group"] in groups:
            h = c["hex"].lstrip("#").upper()
            rgb01 = hex_to_rgb01(h)
            rgb255 = tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
            entries.append({
                "group": c["group"],
                "name": c["name"],
                "hex": f"#{h}",
                "rgb255": rgb255,
                "rgb01": rgb01,
                "lab": srgb_to_lab_array(rgb01),
            })
    return entries


def map_flat_colors_to_palette(
    unique_rgb: list[tuple[int, int, int]],
    palette: list[dict],
    max_delta_e: float = 5.0,
) -> list[dict]:
    """Map each unique sRGB color in flat.png to palette.json (train+structure) or keep as own band color."""
    pal_labs = np.array([p["lab"] for p in palette], dtype=np.float64)
    mapped = []
    for rgb255 in unique_rgb:
        hex_str = f"#{rgb255[0]:02X}{rgb255[1]:02X}{rgb255[2]:02X}"
        # Check exact hex match first
        exact = next((p for p in palette if p["rgb255"] == rgb255), None)
        if exact is not None:
            mapped.append({
                "src_hex": hex_str,
                "out_hex": exact["hex"],
                "rgb255": exact["rgb255"],
                "linear_rgba": (*srgb01_to_linear(exact["rgb01"]).tolist(), 1.0),
                "name": exact["name"],
                "group": exact["group"],
                "in_palette": True,
                "delta_e": 0.0,
            })
            continue

        rgb01 = np.array(rgb255, dtype=np.float64) / 255.0
        lab = srgb_to_lab_array(rgb01)
        de = ciede2000_batch(lab, pal_labs)
        best_idx = int(np.argmin(de))
        best_de = float(de[best_idx])
        if best_de <= max_delta_e:
            p = palette[best_idx]
            mapped.append({
                "src_hex": hex_str,
                "out_hex": p["hex"],
                "rgb255": p["rgb255"],
                "linear_rgba": (*srgb01_to_linear(p["rgb01"]).tolist(), 1.0),
                "name": p["name"],
                "group": p["group"],
                "in_palette": True,
                "delta_e": best_de,
            })
        else:
            mapped.append({
                "src_hex": hex_str,
                "out_hex": hex_str,
                "rgb255": rgb255,
                "linear_rgba": (*srgb01_to_linear(rgb01).tolist(), 1.0),
                "name": "車身帶色（保留平塗原色）",
                "group": "own-band",
                "in_palette": False,
                "delta_e": best_de,
            })
    return mapped


# ---------------------------------------------------------------------------
# Connected Component Filtering on Label Grid
# ---------------------------------------------------------------------------

def merge_small_components(labels: np.ndarray, min_area: int) -> tuple[np.ndarray, int]:
    """Merge 4-connected components with pixel area < min_area into their most frequent 4-neighbor label."""
    H, W = labels.shape
    out = labels.copy()
    merged_count = 0

    while True:
        visited = np.zeros((H, W), dtype=bool)
        small_comps: list[tuple[int, list[tuple[int, int]], int]] = []
        for y in range(H):
            for x in range(W):
                if visited[y, x]:
                    continue
                lbl = int(out[y, x])
                q = deque([(y, x)])
                visited[y, x] = True
                pixels = []
                neighbor_counts: Counter[int] = Counter()
                while q:
                    cy, cx = q.popleft()
                    pixels.append((cy, cx))
                    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < H and 0 <= nx < W:
                            nl = int(out[ny, nx])
                            if nl == lbl:
                                if not visited[ny, nx]:
                                    visited[ny, nx] = True
                                    q.append((ny, nx))
                            else:
                                neighbor_counts[nl] += 1
                if len(pixels) < min_area and neighbor_counts:
                    best_lbl = neighbor_counts.most_common(1)[0][0]
                    small_comps.append((len(pixels), pixels, best_lbl))

        if not small_comps:
            break
        # Merge smallest first
        small_comps.sort(key=lambda item: item[0])
        for _, pixels, best_lbl in small_comps:
            for py, px in pixels:
                out[py, px] = best_lbl
            merged_count += 1

    return out, merged_count


# ---------------------------------------------------------------------------
# PSLG Extraction & RDP Simplification
# ---------------------------------------------------------------------------

def _perp_dist(pt: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float:
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    if dx == 0.0 and dy == 0.0:
        return math.hypot(pt[0] - a[0], pt[1] - a[1])
    return abs(dy * pt[0] - dx * pt[1] + b[0] * a[1] - b[1] * a[0]) / math.hypot(dx, dy)


def rdp_simplify(pts: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    if len(pts) <= 2:
        return pts
    a, b = pts[0], pts[-1]
    max_d = -1.0
    max_i = 0
    for i in range(1, len(pts) - 1):
        d = _perp_dist(pts[i], a, b)
        if d > max_d:
            max_d = d
            max_i = i
    if max_d > eps:
        left = rdp_simplify(pts[: max_i + 1], eps)
        right = rdp_simplify(pts[max_i:], eps)
        return left[:-1] + right
    return [a, b]


def simplify_preserving_axis_runs(
    pts: list[tuple[float, float]],
    eps: float,
    min_run_len: float = 10.0,
    corner_snap: float = 2.5,
) -> list[tuple[float, float]]:
    """Simplify a polyline with RDP while keeping long horizontal/vertical runs strictly axis-aligned."""
    if len(pts) <= 2:
        return pts

    n = len(pts)
    runs: list[tuple[int, int, str]] = []
    i = 0
    while i < n - 1:
        dx = pts[i + 1][0] - pts[i][0]
        dy = pts[i + 1][1] - pts[i][1]
        if abs(dx) < 1e-9 and abs(dy) > 0:
            j = i + 1
            while j < n - 1 and abs(pts[j + 1][0] - pts[j][0]) < 1e-9:
                j += 1
            if abs(pts[j][1] - pts[i][1]) >= min_run_len:
                runs.append((i, j, "V"))
            i = j
        elif abs(dy) < 1e-9 and abs(dx) > 0:
            j = i + 1
            while j < n - 1 and abs(pts[j + 1][1] - pts[j][1]) < 1e-9:
                j += 1
            if abs(pts[j][0] - pts[i][0]) >= min_run_len:
                runs.append((i, j, "H"))
            i = j
        else:
            i += 1

    if not runs:
        return rdp_simplify(pts, eps)

    out: list[tuple[float, float]] = []
    if runs[0][0] > 0:
        out.extend(rdp_simplify(pts[: runs[0][0] + 1], eps))
    else:
        out.append(pts[0])

    skip_next_start = False
    for r_idx, (ri, rj, rtype) in enumerate(runs):
        if not skip_next_start:
            if not out or out[-1] != pts[ri]:
                out.append(pts[ri])
        skip_next_start = False
        out.append(pts[rj])
        if r_idx + 1 < len(runs):
            ni, _, ntype = runs[r_idx + 1]
            if rtype != ntype and max(abs(pts[rj][0] - pts[ni][0]), abs(pts[rj][1] - pts[ni][1])) <= corner_snap:
                out[-1] = (pts[rj][0], pts[ni][1]) if rtype == "V" else (pts[ni][0], pts[rj][1])
                skip_next_start = True
            elif rj < ni:
                mid = rdp_simplify(pts[rj : ni + 1], eps)
                for p in mid[1:-1]:
                    if out[-1] != p:
                        out.append(p)

    last_j = runs[-1][1]
    if last_j < n - 1:
        tail = rdp_simplify(pts[last_j:], eps)
        for p in tail[1:]:
            if out[-1] != p:
                out.append(p)
    return out


def simplify_closed_loop(pts: list[tuple[float, float]], eps: float) -> list[tuple[float, float]]:
    """Simplify a closed loop (pts[0] == pts[-1]) keeping >= 3 distinct vertices and axis runs."""
    ring = pts[:-1]
    n = len(ring)
    if n <= 3:
        return pts
    # Find farthest pair to split the loop cleanly
    best_i, best_j, best_d2 = 0, n // 2, -1.0
    p0 = ring[0]
    for i in range(1, n):
        d2 = (ring[i][0] - p0[0]) ** 2 + (ring[i][1] - p0[1]) ** 2
        if d2 > best_d2:
            best_d2 = d2
            best_i = i
    pi = ring[best_i]
    best_d2 = -1.0
    for j in range(n):
        d2 = (ring[j][0] - pi[0]) ** 2 + (ring[j][1] - pi[1]) ** 2
        if d2 > best_d2:
            best_d2 = d2
            best_j = j

    if best_i > best_j:
        best_i, best_j = best_j, best_i
    if best_i == best_j:
        return pts

    c1 = simplify_preserving_axis_runs(ring[best_i : best_j + 1], eps)
    c2 = simplify_preserving_axis_runs(ring[best_j:] + ring[: best_i + 1], eps)
    merged = c1[:-1] + c2[:-1]
    if len(merged) < 3:
        if eps > 0.1:
            return simplify_closed_loop(pts, eps * 0.5)
        return pts
    return merged + [merged[0]]


def extract_pslg_segments(labels: np.ndarray, rdp_eps: float) -> list[tuple[tuple[float, float], tuple[float, float]]]:
    """Extract simplified boundary segments between different labels in pixel space [0..W] x [0..H]."""
    H, W = labels.shape
    adj: dict[tuple[int, int], list[tuple[int, int]]] = defaultdict(list)

    # Vertical edges
    diff_v = labels[:, :-1] != labels[:, 1:]
    ys, xs = np.nonzero(diff_v)
    for y, x in zip(ys.tolist(), xs.tolist()):
        u = (x + 1, y)
        v = (x + 1, y + 1)
        adj[u].append(v)
        adj[v].append(u)

    # Horizontal edges
    diff_h = labels[:-1, :] != labels[1:, :]
    ys, xs = np.nonzero(diff_h)
    for y, x in zip(ys.tolist(), xs.tolist()):
        u = (x, y + 1)
        v = (x + 1, y + 1)
        adj[u].append(v)
        adj[v].append(u)

    visited_edges: set[tuple[tuple[int, int], tuple[int, int]]] = set()

    def mark_edge(a: tuple[int, int], b: tuple[int, int]) -> None:
        visited_edges.add((a, b) if a < b else (b, a))

    def is_visited(a: tuple[int, int], b: tuple[int, int]) -> bool:
        return ((a, b) if a < b else (b, a)) in visited_edges

    chains: list[tuple[bool, list[tuple[float, float]]]] = []

    # 1. Open chains starting/ending at nodes with degree != 2
    for u, nbrs in adj.items():
        if len(nbrs) == 2:
            continue
        for v in nbrs:
            if is_visited(u, v):
                continue
            path = [u, v]
            mark_edge(u, v)
            prev, cur = u, v
            while len(adj[cur]) == 2:
                n0, n1 = adj[cur]
                nxt = n1 if n0 == prev else n0
                if is_visited(cur, nxt):
                    break
                mark_edge(cur, nxt)
                path.append(nxt)
                prev, cur = cur, nxt
            chains.append((False, [(float(x), float(y)) for x, y in path]))

    # 2. Closed loops of degree-2 nodes
    for u, nbrs in adj.items():
        for v in nbrs:
            if is_visited(u, v):
                continue
            path = [u, v]
            mark_edge(u, v)
            prev, cur = u, v
            while cur != u:
                n0, n1 = adj[cur]
                nxt = n1 if n0 == prev else n0
                if is_visited(cur, nxt):
                    break
                mark_edge(cur, nxt)
                path.append(nxt)
                prev, cur = cur, nxt
            chains.append((True, [(float(x), float(y)) for x, y in path]))

    segments: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for is_loop, pts in chains:
        if is_loop:
            simp = simplify_closed_loop(pts, rdp_eps)
        else:
            simp = simplify_preserving_axis_runs(pts, rdp_eps)
        for i in range(len(simp) - 1):
            a, b = simp[i], simp[i + 1]
            if a != b:
                segments.append((a, b))
    return segments


# ---------------------------------------------------------------------------
# 2D Geometry: Clipping, Planar Subdivision, Hole Bridging, Ear Clipping
# ---------------------------------------------------------------------------

def orient2d(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def poly_signed_area(pts: list[tuple[float, float]]) -> float:
    s = 0.0
    n = len(pts)
    for i in range(n):
        x1, y1 = pts[i]
        x2, y2 = pts[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return 0.5 * s


def point_in_poly(pt: tuple[float, float], poly: list[tuple[float, float]]) -> bool:
    x, y = pt
    inside = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if ((y1 > y) != (y2 > y)) and (x < (x2 - x1) * (y - y1) / (y2 - y1 + 1e-30) + x1):
            inside = not inside
    return inside


def clip_segment_to_convex_ccw(
    a: tuple[float, float],
    b: tuple[float, float],
    poly_ccw: list[tuple[float, float]],
) -> tuple[tuple[float, float], tuple[float, float]] | None:
    """Clip segment a->b against a convex CCW polygon using Cyrus-Beck."""
    t0, t1 = 0.0, 1.0
    dx, dy = b[0] - a[0], b[1] - a[1]
    n_verts = len(poly_ccw)
    for i in range(n_verts):
        p0 = poly_ccw[i]
        p1 = poly_ccw[(i + 1) % n_verts]
        # Inward normal for CCW edge p0->p1 is (-(p1.y-p0.y), p1.x-p0.x)
        nx = -(p1[1] - p0[1])
        ny = p1[0] - p0[0]
        num = nx * (a[0] - p0[0]) + ny * (a[1] - p0[1])
        den = nx * dx + ny * dy
        if abs(den) < 1e-12:
            if num < -1e-9:
                return None
        else:
            t = -num / den
            if den > 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1 + 1e-9:
                return None
    if t1 - t0 < 1e-7:
        return None
    ca = (a[0] + t0 * dx, a[1] + t0 * dy)
    cb = (a[0] + t1 * dx, a[1] + t1 * dy)
    if math.hypot(cb[0] - ca[0], cb[1] - ca[1]) < 1e-6:
        return None
    return ca, cb


def _seg_param_on_line(p: tuple[float, float], a: tuple[float, float], b: tuple[float, float]) -> float | None:
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    if l2 < 1e-18:
        return None
    cross = abs((p[0] - a[0]) * dy - (p[1] - a[1]) * dx)
    if cross / math.sqrt(l2) > 1e-5:
        return None
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2
    if 1e-6 < t < 1.0 - 1e-6:
        return t
    return None


def _seg_seg_intersection(
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
    d: tuple[float, float],
) -> tuple[float, float, tuple[float, float]] | None:
    """Return (t_ab, t_cd, point) if segments ab and cd properly intersect."""
    r_x, r_y = b[0] - a[0], b[1] - a[1]
    s_x, s_y = d[0] - c[0], d[1] - c[1]
    denom = r_x * s_y - r_y * s_x
    if abs(denom) < 1e-12:
        return None
    qp_x, qp_y = c[0] - a[0], c[1] - a[1]
    t = (qp_x * s_y - qp_y * s_x) / denom
    u = (qp_x * r_y - qp_y * r_x) / denom
    if 1e-6 < t < 1.0 - 1e-6 and 1e-6 < u < 1.0 - 1e-6:
        return t, u, (a[0] + t * r_x, a[1] + t * r_y)
    return None


def cut_convex_poly_by_pslg(
    poly_uv: list[tuple[float, float]],
    pslg_segs: list[tuple[tuple[float, float], tuple[float, float]]],
    labels: np.ndarray,
    min_face_area: float,
) -> list[tuple[list[tuple[float, float]], int]]:
    """
    Partition a single convex UV polygon (triangle or quad) into colored faces
    (triangulated into 2D triangles) using the PSLG segments.
    Returns list of ([p0, p1, p2], label_id).
    """
    if poly_signed_area(poly_uv) < 0:
        poly_ccw = list(reversed(poly_uv))
    else:
        poly_ccw = list(poly_uv)

    umin = min(p[0] for p in poly_ccw) - 1e-4
    umax = max(p[0] for p in poly_ccw) + 1e-4
    vmin = min(p[1] for p in poly_ccw) - 1e-4
    vmax = max(p[1] for p in poly_ccw) + 1e-4

    clipped: list[tuple[tuple[float, float], tuple[float, float]]] = []
    for a, b in pslg_segs:
        if max(a[0], b[0]) < umin or min(a[0], b[0]) > umax:
            continue
        if max(a[1], b[1]) < vmin or min(a[1], b[1]) > vmax:
            continue
        res = clip_segment_to_convex_ccw(a, b, poly_ccw)
        if res is not None:
            clipped.append(res)

    # Polygon boundary edges
    n_poly = len(poly_ccw)
    poly_edges = [
        (poly_ccw[i], poly_ccw[(i + 1) % n_poly])
        for i in range(n_poly)
    ]

    all_segs = list(poly_edges) + clipped

    # Snap vertices within 1e-5
    pts_list: list[tuple[float, float]] = []
    grid_map: dict[tuple[int, int], list[int]] = defaultdict(list)
    inv_snap = 1e4

    def get_vid(pt: tuple[float, float]) -> int:
        gx, gy = int(round(pt[0] * inv_snap)), int(round(pt[1] * inv_snap))
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for vid in grid_map.get((gx + dx, gy + dy), ()):
                    vx, vy = pts_list[vid]
                    if math.hypot(vx - pt[0], vy - pt[1]) < 1e-4:
                        return vid
        vid = len(pts_list)
        pts_list.append(pt)
        grid_map[(gx, gy)].append(vid)
        return vid

    seg_vids: list[tuple[int, int]] = []
    for a, b in all_segs:
        va, vb = get_vid(a), get_vid(b)
        if va != vb:
            seg_vids.append((va, vb))

    # Split segments at any interior vertex or proper crossing
    # First collect crossings
    new_pts: list[tuple[float, float]] = []
    n_orig = len(seg_vids)
    for i in range(n_orig):
        a = pts_list[seg_vids[i][0]]
        b = pts_list[seg_vids[i][1]]
        for j in range(i + 1, n_orig):
            c = pts_list[seg_vids[j][0]]
            d = pts_list[seg_vids[j][1]]
            hit = _seg_seg_intersection(a, b, c, d)
            if hit is not None:
                new_pts.append(hit[2])
    for p in new_pts:
        get_vid(p)

    # Split every segment at all vertices lying on it
    undirected_edges: set[tuple[int, int]] = set()
    for va, vb in seg_vids:
        a, b = pts_list[va], pts_list[vb]
        splits: list[tuple[float, int]] = [(0.0, va), (1.0, vb)]
        s_umin, s_umax = min(a[0], b[0]) - 1e-4, max(a[0], b[0]) + 1e-4
        s_vmin, s_vmax = min(a[1], b[1]) - 1e-4, max(a[1], b[1]) + 1e-4
        for vid, p in enumerate(pts_list):
            if vid == va or vid == vb:
                continue
            if not (s_umin <= p[0] <= s_umax and s_vmin <= p[1] <= s_vmax):
                continue
            t = _seg_param_on_line(p, a, b)
            if t is not None:
                splits.append((t, vid))
        splits.sort(key=lambda x: x[0])
        for k in range(len(splits) - 1):
            u, v = splits[k][1], splits[k + 1][1]
            if u != v:
                undirected_edges.add((u, v) if u < v else (v, u))

    # Iteratively prune degree-1 dangling vertices (cannot form faces)
    while True:
        deg: Counter[int] = Counter()
        for u, v in undirected_edges:
            deg[u] += 1
            deg[v] += 1
        dangling = {v for v, d in deg.items() if d <= 1}
        if not dangling:
            break
        undirected_edges = {(u, v) for (u, v) in undirected_edges if u not in dangling and v not in dangling}

    # Build half-edge structure
    out_edges: dict[int, list[int]] = defaultdict(list)
    for u, v in undirected_edges:
        out_edges[u].append(v)
        out_edges[v].append(u)

    # Sort outgoing edges CCW by angle at each vertex
    sorted_out: dict[int, list[int]] = {}
    pos_in_out: dict[tuple[int, int], int] = {}
    for u, nbrs in out_edges.items():
        ux, uy = pts_list[u]
        nbrs_sorted = sorted(nbrs, key=lambda v: math.atan2(pts_list[v][1] - uy, pts_list[v][0] - ux))
        sorted_out[u] = nbrs_sorted
        for idx_v, v in enumerate(nbrs_sorted):
            pos_in_out[(u, v)] = idx_v

    visited_he: set[tuple[int, int]] = set()
    ccw_faces: list[list[int]] = []
    cw_cycles: list[list[int]] = []

    for u, nbrs in sorted_out.items():
        for v in nbrs:
            if (u, v) in visited_he:
                continue
            cycle: list[int] = []
            cur_u, cur_v = u, v
            while (cur_u, cur_v) not in visited_he:
                visited_he.add((cur_u, cur_v))
                cycle.append(cur_u)
                # At cur_v, find incoming edge (cur_v -> cur_u) and take previous in CCW order
                idx_back = pos_in_out[(cur_v, cur_u)]
                nbrs_v = sorted_out[cur_v]
                nxt_w = nbrs_v[(idx_back - 1) % len(nbrs_v)]
                cur_u, cur_v = cur_v, nxt_w
            if len(cycle) >= 3:
                area = poly_signed_area([pts_list[i] for i in cycle])
                if area > 1e-7:
                    ccw_faces.append(cycle)
                elif area < -1e-7:
                    cw_cycles.append(cycle)

    # The largest |area| CW cycle is the outer boundary of T itself; all other CW cycles are holes
    holes: list[list[int]] = []
    if cw_cycles:
        cw_cycles.sort(key=lambda c: abs(poly_signed_area([pts_list[i] for i in c])), reverse=True)
        holes = cw_cycles[1:]

    # Assign each hole to the smallest-area CCW face strictly larger than it and containing it
    ccw_areas = [poly_signed_area([pts_list[i] for i in f]) for f in ccw_faces]
    face_holes: list[list[list[int]]] = [[] for _ in ccw_faces]
    for h in holes:
        h_area = abs(poly_signed_area([pts_list[i] for i in h]))
        h_pt = pts_list[h[0]]
        best_f = -1
        best_area = float("inf")
        for fi, f in enumerate(ccw_faces):
            if ccw_areas[fi] <= h_area + 1e-6:
                continue
            if ccw_areas[fi] < best_area:
                f_pts = [pts_list[i] for i in f]
                if point_in_poly(h_pt, f_pts):
                    best_area = ccw_areas[fi]
                    best_f = fi
        if best_f >= 0:
            face_holes[best_f].append(h)

    # Sample label for each face
    H, W = labels.shape
    face_tris: list[tuple[list[list[tuple[float, float]]], int, float]] = []
    for fi, outer_ids in enumerate(ccw_faces):
        outer_pts = [pts_list[i] for i in outer_ids]
        hole_pts_list = [[pts_list[i] for i in h] for h in face_holes[fi]]
        net_area = ccw_areas[fi] - sum(abs(poly_signed_area(hp)) for hp in hole_pts_list)
        if net_area <= 1e-6:
            continue

        simple_pts = bridge_holes(outer_pts, hole_pts_list)
        tris_2d = ear_clip(simple_pts)
        if not tris_2d:
            continue

        # Pick largest sub-triangle centroid to sample label
        best_tri = max(tris_2d, key=lambda t: abs(orient2d(t[0], t[1], t[2])))
        cx = (best_tri[0][0] + best_tri[1][0] + best_tri[2][0]) / 3.0
        cy = (best_tri[0][1] + best_tri[1][1] + best_tri[2][1]) / 3.0
        px = int(min(max(math.floor(cx), 0), W - 1))
        py = int(min(max(math.floor(cy), 0), H - 1))
        lbl = int(labels[py, px])
        face_tris.append((tris_2d, lbl, net_area))

    # If any face inside T has net_area < min_face_area (clipped corner sliver), merge its label
    # with the largest face in T (or adjacent face)
    if len(face_tris) > 1:
        largest_lbl = max(face_tris, key=lambda x: x[2])[1]
        out: list[tuple[list[tuple[float, float]], int]] = []
        for tris_2d, lbl, net_area in face_tris:
            use_lbl = largest_lbl if net_area < min_face_area else lbl
            for t in tris_2d:
                out.append((t, use_lbl))
        return out

    out = []
    for tris_2d, lbl, _ in face_tris:
        for t in tris_2d:
            out.append((t, lbl))
    return out


def bridge_holes(
    outer: list[tuple[float, float]],
    holes: list[list[tuple[float, float]]],
) -> list[tuple[float, float]]:
    """Bridge CW holes into a CCW outer polygon using mutually visible vertex pairs."""
    if not holes:
        return outer

    poly = list(outer)
    # Process holes from rightmost max-x to leftmost
    holes_sorted = sorted(holes, key=lambda h: max(p[0] for p in h), reverse=True)

    for hole in holes_sorted:
        # Find rightmost vertex M in hole
        m_idx = max(range(len(hole)), key=lambda i: (hole[i][0], -hole[i][1]))
        M = hole[m_idx]

        # Cast ray +x from M to find closest intersection with poly edges
        best_x = float("inf")
        best_edge_i = -1
        n = len(poly)
        for i in range(n):
            a = poly[i]
            b = poly[(i + 1) % n]
            if (a[1] > M[1]) == (b[1] > M[1]):
                continue
            # Edge crosses y = M[1]
            t = (M[1] - a[1]) / (b[1] - a[1])
            ix = a[0] + t * (b[0] - a[0])
            if ix >= M[0] - 1e-9 and ix < best_x:
                best_x = ix
                best_edge_i = i

        if best_edge_i < 0:
            # Fallback: nearest vertex of poly
            p_idx = min(range(n), key=lambda i: (poly[i][0] - M[0]) ** 2 + (poly[i][1] - M[1]) ** 2)
        else:
            a = poly[best_edge_i]
            b = poly[(best_edge_i + 1) % n]
            p_idx = best_edge_i if a[0] >= b[0] else (best_edge_i + 1) % n
            P = poly[p_idx]
            I = (best_x, M[1])
            # Check if any reflex vertex of poly lies inside triangle (M, I, P)
            best_ang = -1.0
            for j in range(n):
                V = poly[j]
                if V[0] <= M[0] - 1e-9:
                    continue
                if j == p_idx:
                    continue
                # Check if V is inside triangle M-I-P (approx)
                s1 = orient2d(M, I, V)
                s2 = orient2d(I, P, V)
                s3 = orient2d(P, M, V)
                if (s1 >= -1e-9 and s2 >= -1e-9 and s3 >= -1e-9) or (s1 <= 1e-9 and s2 <= 1e-9 and s3 <= 1e-9):
                    dx, dy = V[0] - M[0], V[1] - M[1]
                    d = math.hypot(dx, dy)
                    if d > 1e-9:
                        ang = abs(dx) / d
                        if ang > best_ang:
                            best_ang = ang
                            p_idx = j

        # Splice hole into poly at (p_idx, m_idx)
        reordered_hole = hole[m_idx:] + hole[:m_idx]
        poly = poly[: p_idx + 1] + reordered_hole + [reordered_hole[0], poly[p_idx]] + poly[p_idx + 1 :]

    return poly


def ear_clip(poly: list[tuple[float, float]]) -> list[list[tuple[float, float]]]:
    """Ear-clip a simple CCW polygon into triangles."""
    pts = list(poly)
    # Remove consecutive duplicate vertices
    cleaned: list[tuple[float, float]] = []
    for p in pts:
        if not cleaned or math.hypot(p[0] - cleaned[-1][0], p[1] - cleaned[-1][1]) > 1e-8:
            cleaned.append(p)
    if len(cleaned) >= 2 and math.hypot(cleaned[0][0] - cleaned[-1][0], cleaned[0][1] - cleaned[-1][1]) <= 1e-8:
        cleaned.pop()
    pts = cleaned

    if len(pts) < 3:
        return []
    if poly_signed_area(pts) < 0:
        pts.reverse()

    tris: list[list[tuple[float, float]]] = []
    guard = 0
    max_guard = len(pts) * len(pts) + 10
    while len(pts) > 3 and guard < max_guard:
        guard += 1
        n = len(pts)
        ear_found = False
        for i in range(n):
            a = pts[(i - 1) % n]
            b = pts[i]
            c = pts[(i + 1) % n]
            area2 = orient2d(a, b, c)
            if area2 <= 1e-9:
                continue
            # Check no other vertex lies inside (a, b, c)
            has_inside = False
            for j in range(n):
                if j in ((i - 1) % n, i, (i + 1) % n):
                    continue
                p = pts[j]
                if p == a or p == b or p == c:
                    continue
                if orient2d(a, b, p) >= -1e-9 and orient2d(b, c, p) >= -1e-9 and orient2d(c, a, p) >= -1e-9:
                    has_inside = True
                    break
            if not has_inside:
                tris.append([a, b, c])
                pts.pop(i)
                ear_found = True
                break
        if not ear_found:
            # Remove collinear vertex if any
            removed = False
            for i in range(n):
                a = pts[(i - 1) % n]
                b = pts[i]
                c = pts[(i + 1) % n]
                if abs(orient2d(a, b, c)) <= 1e-7:
                    pts.pop(i)
                    removed = True
                    break
            if not removed:
                break

    if len(pts) == 3 and abs(orient2d(pts[0], pts[1], pts[2])) > 1e-9:
        tris.append([pts[0], pts[1], pts[2]])
    return tris


# ---------------------------------------------------------------------------
# GLB Reader & Writer
# ---------------------------------------------------------------------------

def read_glb(glb_path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    data = glb_path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise ValueError(f"Unsupported GLB header: {magic:#x} v{version}")

    off = 12
    json_chunk = None
    bin_chunk = None
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        cdata = data[off + 8 : off + 8 + clen]
        if ctype == 0x4E4F534A:
            json_chunk = cdata
        elif ctype == 0x004E4942:
            bin_chunk = cdata
        off += 8 + clen

    gltf = json.loads(json_chunk.decode("utf-8"))
    prim = gltf["meshes"][0]["primitives"][0]

    def read_acc(acc_idx: int) -> np.ndarray:
        acc = gltf["accessors"][acc_idx]
        bv = gltf["bufferViews"][acc["bufferView"]]
        offset = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        count = acc["count"]
        ct = acc["componentType"]
        t = acc["type"]
        dtype = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[ct]
        comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[t]
        arr = np.frombuffer(bin_chunk, dtype=dtype, count=count * comps, offset=offset)
        return arr.reshape((count, comps)) if comps > 1 else arr

    pos = read_acc(prim["attributes"]["POSITION"]).astype(np.float64)
    nrm = read_acc(prim["attributes"]["NORMAL"]).astype(np.float64)
    uv = read_acc(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = read_acc(prim["indices"]).reshape(-1, 3).astype(np.int64)
    return pos, nrm, uv, idx


def write_glb(
    out_path: Path,
    body_tris: list[tuple[np.ndarray, np.ndarray, tuple[float, float, float, float]]],
    glass_tris: list[tuple[np.ndarray, np.ndarray, tuple[float, float, float, float]]],
) -> None:
    """Write a self-contained GLB 2.0 with POSITION, NORMAL, COLOR_0 (linear RGBA float), no texture/UV."""
    bin_buf = bytearray()
    buffer_views = []
    accessors = []
    primitives = []

    def append_bytes(b: bytes, target: int) -> int:
        while len(bin_buf) % 4 != 0:
            bin_buf.append(0)
        offset = len(bin_buf)
        bin_buf.extend(b)
        bv_idx = len(buffer_views)
        buffer_views.append({
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(b),
            "target": target,
        })
        return bv_idx

    def add_prim(tris: list[tuple[np.ndarray, np.ndarray, tuple[float, float, float, float]]], mat_idx: int, is_glass: bool) -> None:
        if not tris:
            return
        n_tris = len(tris)
        n_verts = n_tris * 3
        pos_arr = np.empty((n_verts, 3), dtype=np.float32)
        nrm_arr = np.empty((n_verts, 3), dtype=np.float32)
        col_arr = np.empty((n_verts, 4), dtype=np.float32)
        idx_arr = np.arange(n_verts, dtype=np.uint16 if n_verts <= 65535 else np.uint32)

        for ti, (v3, n3, rgba) in enumerate(tris):
            base = ti * 3
            pos_arr[base : base + 3] = v3.astype(np.float32)
            nrm_arr[base : base + 3] = n3.astype(np.float32)
            col_arr[base : base + 3] = np.array(rgba, dtype=np.float32)

        bv_pos = append_bytes(pos_arr.tobytes(), 34962)
        bv_nrm = append_bytes(nrm_arr.tobytes(), 34962)
        bv_col = append_bytes(col_arr.tobytes(), 34962)
        bv_idx = append_bytes(idx_arr.tobytes(), 34963)

        acc_pos = len(accessors)
        accessors.append({
            "bufferView": bv_pos,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC3",
            "min": pos_arr.min(axis=0).tolist(),
            "max": pos_arr.max(axis=0).tolist(),
        })
        acc_nrm = len(accessors)
        accessors.append({
            "bufferView": bv_nrm,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC3",
        })
        acc_col = len(accessors)
        accessors.append({
            "bufferView": bv_col,
            "componentType": 5126,
            "count": n_verts,
            "type": "VEC4",
        })
        acc_idx = len(accessors)
        accessors.append({
            "bufferView": bv_idx,
            "componentType": 5123 if idx_arr.dtype == np.uint16 else 5125,
            "count": n_verts,
            "type": "SCALAR",
        })

        prim = {
            "attributes": {
                "POSITION": acc_pos,
                "NORMAL": acc_nrm,
                "COLOR_0": acc_col,
            },
            "indices": acc_idx,
            "material": mat_idx,
        }
        if is_glass:
            prim["extras"] = {"glass": True}
        primitives.append(prim)

    add_prim(body_tris, 0, False)
    add_prim(glass_tris, 1, True)

    while len(bin_buf) % 4 != 0:
        bin_buf.append(0)

    gltf = {
        "asset": {"version": "2.0", "generator": "along-the-line/cut_faces.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": "train_car", "mesh": 0}],
        "meshes": [{"name": "train_car_mesh", "primitives": primitives}],
        "materials": [
            {
                "name": "body",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.9,
                },
            },
            {
                "name": "glass",
                "extras": {"glass": True},
                "pbrMetallicRoughness": {
                    "baseColorFactor": [1.0, 1.0, 1.0, 1.0],
                    "metallicFactor": 0.0,
                    "roughnessFactor": 0.2,
                },
            },
        ],
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_buf)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":"), ensure_ascii=True).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_buf)
    header = struct.pack("<III", 0x46546C67, 2, total_len)
    c0_hdr = struct.pack("<II", len(json_bytes), 0x4E4F534A)
    c1_hdr = struct.pack("<II", len(bin_buf), 0x004E4942)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_bytes(header + c0_hdr + json_bytes + c1_hdr + bytes(bin_buf))


# ---------------------------------------------------------------------------
# Main Pipeline
# ---------------------------------------------------------------------------

def barycentric_2d(
    p: tuple[float, float],
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
) -> tuple[float, float, float]:
    v0x, v0y = b[0] - a[0], b[1] - a[1]
    v1x, v1y = c[0] - a[0], c[1] - a[1]
    v2x, v2y = p[0] - a[0], p[1] - a[1]
    den = v0x * v1y - v1x * v0y
    w1 = (v2x * v1y - v1x * v2y) / den
    w2 = (v0x * v2y - v2x * v0y) / den
    w0 = 1.0 - w1 - w2
    return w0, w1, w2


def cut_degenerate_line_triangle(
    v0: np.ndarray,
    v1: np.ndarray,
    v2: np.ndarray,
    n: np.ndarray,
    u0: tuple[float, float],
    u1: tuple[float, float],
    u2: tuple[float, float],
    labels: np.ndarray,
    min_band_px: float = 2.5,
) -> list[tuple[np.ndarray, int, tuple[float, float]]]:
    """
    Slice a 3D triangle whose UV coordinates are collinear (zero UV area) but not coincident
    into parallel color bands along the UV line.
    Returns list of (v_tri (3x3), label_id, uv_centroid_px).
    """
    H, W = labels.shape
    uvs = [u0, u1, u2]
    verts = [v0, v1, v2]

    # Find the two farthest UV vertices to define the line segment [p_start, p_end]
    best_i, best_j, max_d = 0, 1, -1.0
    for i in range(3):
        for j in range(i + 1, 3):
            d = math.hypot(uvs[j][0] - uvs[i][0], uvs[j][1] - uvs[i][1])
            if d > max_d:
                max_d = d
                best_i, best_j = i, j

    if max_d < 1e-3:
        cx = (u0[0] + u1[0] + u2[0]) / 3.0
        cy = (u0[1] + u1[1] + u2[1]) / 3.0
        px = int(min(max(math.floor(cx), 0), W - 1))
        py = int(min(max(math.floor(cy), 0), H - 1))
        return [(np.stack([v0, v1, v2], axis=0), int(labels[py, px]), (cx, cy))]

    p_start = uvs[best_i]
    p_end = uvs[best_j]
    dx = p_end[0] - p_start[0]
    dy = p_end[1] - p_start[1]
    l2 = dx * dx + dy * dy

    t_verts = [
        min(max(((u[0] - p_start[0]) * dx + (u[1] - p_start[1]) * dy) / l2, 0.0), 1.0)
        for u in uvs
    ]

    # Sample labels along the UV line using floor(x), floor(y) to match PSLG pixel cells
    n_steps = max(int(math.ceil(max_d * 8.0)), 32)
    runs: list[list] = []  # [lbl, t_start, t_end]
    for s in range(n_steps + 1):
        t = s / n_steps
        x = p_start[0] + t * dx
        y = p_start[1] + t * dy
        px = int(min(max(math.floor(x), 0), W - 1))
        py = int(min(max(math.floor(y), 0), H - 1))
        lbl = int(labels[py, px])
        if not runs or runs[-1][0] != lbl:
            runs.append([lbl, t, t])
        else:
            runs[-1][2] = t

    # Merge tiny edge-bleed bands (< min_band_px) into the longer adjacent band
    while len(runs) > 1:
        lengths = [(r[2] - r[1]) * max_d for r in runs]
        min_idx = min(range(len(runs)), key=lambda i: lengths[i])
        if lengths[min_idx] >= min_band_px:
            break
        if min_idx == 0:
            runs[1][1] = runs[0][1]
            runs.pop(0)
        elif min_idx == len(runs) - 1:
            runs[-2][2] = runs[-1][2]
            runs.pop()
        else:
            if lengths[min_idx - 1] >= lengths[min_idx + 1]:
                runs[min_idx - 1][2] = runs[min_idx][2]
            else:
                runs[min_idx + 1][1] = runs[min_idx][1]
            runs.pop(min_idx)
        # Coalesce adjacent runs with identical label
        coalesced: list[list] = []
        for r in runs:
            if coalesced and coalesced[-1][0] == r[0]:
                coalesced[-1][2] = r[2]
            else:
                coalesced.append(r)
        runs = coalesced

    # Build contiguous [t_a, t_b] intervals covering [0.0, 1.0]
    bands: list[tuple[int, float, float]] = []
    for i, r in enumerate(runs):
        ta = 0.0 if i == 0 else 0.5 * (runs[i - 1][2] + r[1])
        tb = 1.0 if i == len(runs) - 1 else 0.5 * (r[2] + runs[i + 1][1])
        bands.append((r[0], ta, tb))

    def clip_poly_t(poly: list[tuple[np.ndarray, float]], t_val: float, keep_ge: bool) -> list[tuple[np.ndarray, float]]:
        if not poly:
            return []
        out: list[tuple[np.ndarray, float]] = []
        np_len = len(poly)
        for i in range(np_len):
            va, ta = poly[i]
            vb, tb = poly[(i + 1) % np_len]
            in_a = (ta >= t_val - 1e-9) if keep_ge else (ta <= t_val + 1e-9)
            in_b = (tb >= t_val - 1e-9) if keep_ge else (tb <= t_val + 1e-9)
            if in_a and in_b:
                out.append((vb, tb))
            elif in_a and not in_b:
                denom = tb - ta
                alpha = (t_val - ta) / denom if abs(denom) > 1e-12 else 0.0
                out.append((va + alpha * (vb - va), t_val))
            elif not in_a and in_b:
                denom = tb - ta
                alpha = (t_val - ta) / denom if abs(denom) > 1e-12 else 0.0
                out.append((va + alpha * (vb - va), t_val))
                out.append((vb, tb))
        return out

    init_poly = list(zip(verts, t_verts))
    results: list[tuple[np.ndarray, int, tuple[float, float]]] = []
    for lbl, ta, tb in bands:
        poly = clip_poly_t(init_poly, ta, keep_ge=True)
        poly = clip_poly_t(poly, tb, keep_ge=False)
        if len(poly) < 3:
            continue
        t_mid = 0.5 * (ta + tb)
        uv_mid = (p_start[0] + t_mid * dx, p_start[1] + t_mid * dy)
        p0_3d = poly[0][0]
        for k in range(1, len(poly) - 1):
            va, vb, vc = p0_3d, poly[k][0], poly[k + 1][0]
            cross = np.cross(vb - va, vc - va)
            if float(np.linalg.norm(cross)) < 1e-10:
                continue
            if float(np.dot(cross, n)) < 0.0:
                vb, vc = vc, vb
            results.append((np.stack([va, vb, vc], axis=0), lbl, uv_mid))

    return results


def is_window_triangle(centroid_3d: np.ndarray, normal_3d: np.ndarray, uv_centroid_px: tuple[float, float], color_hex: str) -> bool:
    """Identify window (#2B2F36) triangles vs underbody/roof/coupler/number dark triangles."""
    if color_hex != "#2B2F36":
        return False
    u, v = uv_centroid_px
    # Top-right UV quadrant is roof HVAC & underbody bogies/chassis
    if u > 260.0 and v < 128.0:
        return False
    # Lower front bumper / coupler
    if centroid_3d[1] < 0.70:
        return False
    # Front nose "1000" train number (below windshield, v >= 200 / y < 1.12)
    if abs(normal_3d[2]) > 0.7 and centroid_3d[1] < 1.12:
        return False
    # Roof slope (above 2.29m) unless it's the front windshield top arch (normal pointing +/-Z)
    if centroid_3d[1] > 2.28 and abs(normal_3d[2]) < 0.7:
        return False
    return True


def group_coplanar_quads(
    pos: np.ndarray,
    uv_px_all: np.ndarray,
    idx: np.ndarray,
) -> list[tuple[list[tuple[float, float]], np.ndarray, tuple[np.ndarray, np.ndarray, np.ndarray], tuple[tuple[float, float], tuple[float, float], tuple[float, float]]]]:
    """
    Merge pairs of adjacent coplanar triangles that share an edge in both 3D and UV,
    have an identical 3D-to-UV affine mapping, and form a strictly convex UV quad.
    Returns list of (poly_uv, unit_normal, ref_v3, ref_uv3) for each patch (quad or single tri).
    """
    n_tris = len(idx)
    tri_norms: list[np.ndarray | None] = [None] * n_tris
    tri_uvs: list[list[tuple[float, float]]] = []
    tri_uv_areas: list[float] = [0.0] * n_tris

    for ti, tri in enumerate(idx):
        v0, v1, v2 = pos[tri[0]], pos[tri[1]], pos[tri[2]]
        n = np.cross(v1 - v0, v2 - v0)
        n_len = float(np.linalg.norm(n))
        if n_len >= 1e-12:
            tri_norms[ti] = n / n_len
        u3 = [tuple(float(x) for x in uv_px_all[k]) for k in tri]
        tri_uvs.append(u3)
        tri_uv_areas[ti] = abs(orient2d(u3[0], u3[1], u3[2])) * 0.5

    edge_map: dict[tuple, list[int]] = defaultdict(list)
    for ti, tri in enumerate(idx):
        if tri_norms[ti] is None or tri_uv_areas[ti] < 1e-3:
            continue
        for a, b in ((0, 1), (1, 2), (2, 0)):
            ka = (tuple(pos[tri[a]].round(5)), tuple(uv_px_all[tri[a]].round(4)))
            kb = (tuple(pos[tri[b]].round(5)), tuple(uv_px_all[tri[b]].round(4)))
            key = (ka, kb) if ka < kb else (kb, ka)
            edge_map[key].append(ti)

    candidates: list[tuple[float, int, int, list[tuple[float, float]]]] = []
    for tris in edge_map.values():
        if len(tris) != 2:
            continue
        t1, t2 = tris
        n1, n2 = tri_norms[t1], tri_norms[t2]
        if n1 is None or n2 is None or float(np.dot(n1, n2)) <= 0.9999:
            continue
        s1 = {(tuple(pos[m].round(5)), tuple(uv_px_all[m].round(4))): m for m in idx[t1]}
        s2 = {(tuple(pos[m].round(5)), tuple(uv_px_all[m].round(4))): m for m in idx[t2]}
        shared_keys = [k for k in s1 if k in s2]
        if len(shared_keys) != 2:
            continue
        opp1 = [s1[k] for k in s1 if k not in s2][0]
        opp2 = [s2[k] for k in s2 if k not in s1][0]
        sh_a, sh_b = s1[shared_keys[0]], s1[shared_keys[1]]

        # Check 3D-to-UV affine consistency
        u_t1 = tri_uvs[t1]
        w0, w1, w2 = barycentric_2d(tuple(float(x) for x in uv_px_all[opp2]), u_t1[0], u_t1[1], u_t1[2])
        pred = w0 * pos[idx[t1][0]] + w1 * pos[idx[t1][1]] + w2 * pos[idx[t1][2]]
        if float(np.linalg.norm(pred - pos[opp2])) >= 1e-4:
            continue

        # Order quad vertices around perimeter: opp1 -> sh_a -> opp2 -> sh_b
        quad_uv = [
            tuple(float(x) for x in uv_px_all[opp1]),
            tuple(float(x) for x in uv_px_all[sh_a]),
            tuple(float(x) for x in uv_px_all[opp2]),
            tuple(float(x) for x in uv_px_all[sh_b]),
        ]
        # Verify strict convexity in UV
        signs = [
            orient2d(quad_uv[i], quad_uv[(i + 1) % 4], quad_uv[(i + 2) % 4])
            for i in range(4)
        ]
        if not (all(s > 1e-3 for s in signs) or all(s < -1e-3 for s in signs)):
            continue
        candidates.append((tri_uv_areas[t1] + tri_uv_areas[t2], t1, t2, quad_uv))

    candidates.sort(key=lambda x: x[0], reverse=True)
    used = [False] * n_tris
    patches: list[tuple[list[tuple[float, float]], np.ndarray, tuple[np.ndarray, np.ndarray, np.ndarray], tuple[tuple[float, float], tuple[float, float], tuple[float, float]]]] = []

    for _, t1, t2, quad_uv in candidates:
        if used[t1] or used[t2]:
            continue
        used[t1] = True
        used[t2] = True
        tri = idx[t1]
        v3 = (pos[tri[0]], pos[tri[1]], pos[tri[2]])
        u3 = (tri_uvs[t1][0], tri_uvs[t1][1], tri_uvs[t1][2])
        patches.append((quad_uv, tri_norms[t1], v3, u3))

    for ti, tri in enumerate(idx):
        if used[ti] or tri_norms[ti] is None:
            continue
        v3 = (pos[tri[0]], pos[tri[1]], pos[tri[2]])
        u3 = (tri_uvs[ti][0], tri_uvs[ti][1], tri_uvs[ti][2])
        patches.append((list(u3), tri_norms[ti], v3, u3))

    return patches


def run_cut(
    glb_path: Path,
    flat_path: Path,
    palette_path: Path,
    out_dir: Path,
    min_area: int = 22,
    rdp_eps: float = 1.8,
) -> dict:
    t0 = time.perf_counter()

    # 1. Load flat texture & map to palette
    with Image.open(flat_path) as im:
        rgba = np.asarray(im.convert("RGBA"), dtype=np.uint8)
    H, W, _ = rgba.shape

    rgb_flat = rgba[..., :3].reshape(-1, 3)
    uniq_arr, inv = np.unique(rgb_flat, axis=0, return_inverse=True)
    unique_rgb = [tuple(int(c) for c in row) for row in uniq_arr]
    labels = inv.reshape((H, W)).astype(np.int32)

    palette = load_palette(palette_path, {"train", "structure"})
    color_info = map_flat_colors_to_palette(unique_rgb, palette)

    # 2. Merge small fragments (< min_area px^2)
    labels_clean, merged_fragments = merge_small_components(labels, min_area)

    # 3. Extract simplified PSLG
    pslg_segs = extract_pslg_segments(labels_clean, rdp_eps)

    # 4. Read GLB and cut each triangle
    pos, _, uv, idx = read_glb(glb_path)
    uv_px_all = uv * np.array([float(W), float(H)], dtype=np.float64)

    body_tris: list[tuple[np.ndarray, np.ndarray, tuple[float, float, float, float]]] = []
    glass_tris: list[tuple[np.ndarray, np.ndarray, tuple[float, float, float, float]]] = []
    uv_cut_tris: list[tuple[list[tuple[float, float]], tuple[int, int, int]]] = []
    color_tri_counts: Counter[str] = Counter()

    patches = group_coplanar_quads(pos, uv_px_all, idx)
    for poly_uv, n, (v0, v1, v2), (u0, u1, u2) in patches:
        if len(poly_uv) == 3:
            uv_area = abs(orient2d(u0, u1, u2)) * 0.5
            if uv_area < 1e-3:
                deg_tris = cut_degenerate_line_triangle(v0, v1, v2, n, u0, u1, u2, labels_clean)
                for v_tri, lbl, uv_mid in deg_tris:
                    cinfo = color_info[lbl]
                    c3d = v_tri.mean(axis=0)
                    if is_window_triangle(c3d, n, uv_mid, cinfo["out_hex"]):
                        glass_tris.append((v_tri, n, cinfo["linear_rgba"]))
                    else:
                        body_tris.append((v_tri, n, cinfo["linear_rgba"]))
                    color_tri_counts[cinfo["out_hex"]] += 1
                continue

        cut_list = cut_convex_poly_by_pslg(poly_uv, pslg_segs, labels_clean, 4.0)
        for tri2d, lbl in cut_list:
            cinfo = color_info[lbl]
            p3d = []
            for p2 in tri2d:
                w0, w1, w2 = barycentric_2d(p2, u0, u1, u2)
                p3d.append(w0 * v0 + w1 * v1 + w2 * v2)
            va, vb, vc = p3d
            # Ensure 3D winding matches original plane normal n
            if float(np.dot(np.cross(vb - va, vc - va), n)) < 0.0:
                vb, vc = vc, vb
            v_tri = np.stack([va, vb, vc], axis=0)
            c3d = v_tri.mean(axis=0)
            ucx = (tri2d[0][0] + tri2d[1][0] + tri2d[2][0]) / 3.0
            ucy = (tri2d[0][1] + tri2d[1][1] + tri2d[2][1]) / 3.0
            if is_window_triangle(c3d, n, (ucx, ucy), cinfo["out_hex"]):
                glass_tris.append((v_tri, n, cinfo["linear_rgba"]))
            else:
                body_tris.append((v_tri, n, cinfo["linear_rgba"]))
            uv_cut_tris.append((tri2d, cinfo["rgb255"]))
            color_tri_counts[cinfo["out_hex"]] += 1

    # 5. Write output GLB
    out_dir.mkdir(parents=True, exist_ok=True)
    out_glb = out_dir / "e752e7a2-cut.glb"
    write_glb(out_glb, body_tris, glass_tris)

    # 6. Render uv-cut.png (2x scale for crispness)
    scale = 2
    canvas = Image.new("RGBA", (W * scale, H * scale), (20, 20, 24, 255))
    # Faint background of flat texture so uncovered UV areas are visible for reference
    bg = Image.fromarray(rgba, mode="RGBA").resize((W * scale, H * scale), Image.NEAREST)
    bg_arr = np.asarray(bg, dtype=np.uint8).copy()
    bg_arr[..., :3] = (bg_arr[..., :3].astype(np.float32) * 0.35).astype(np.uint8)
    canvas = Image.fromarray(bg_arr, mode="RGBA")
    draw = ImageDraw.Draw(canvas)

    for tri2d, rgb255 in uv_cut_tris:
        pts = [(p[0] * scale, p[1] * scale) for p in tri2d]
        draw.polygon(pts, fill=(*rgb255, 255), outline=(0, 220, 120, 255))

    out_uv = out_dir / "uv-cut.png"
    canvas.save(out_uv)

    elapsed = time.perf_counter() - t0
    total_tris = len(body_tris) + len(glass_tris)

    # 7. Write summary.md
    hex_to_info = {c["out_hex"]: c for c in color_info}
    lines = [
        "# t002 列車 UV 切面報告 (`e752e7a2-cut.glb`)",
        "",
        f"- **原始三角形數**：{len(idx)}",
        f"- **切後三角形數**：{total_tris}（上限 1,500）",
        f"  - 車身（`body`）：{len(body_tris)}",
        f"  - 車窗（`glass`）：{len(glass_tris)}",
        f"- **合併碎片數**（< {min_area} px²）：{merged_fragments}",
        f"- **PSLG 簡化容差**（RDP）：{rdp_eps} px（共 {len(pslg_segs)} 段線段）",
        f"- **執行時間**：{elapsed:.3f} s",
        "",
        "## 色票使用統計",
        "",
        "| 輸出色碼 | 色票名稱 | 群組 | 三角形數 | 說明 |",
        "|---|---|---|---:|---|",
    ]
    for hex_code, cnt in color_tri_counts.most_common():
        ci = hex_to_info[hex_code]
        note = "色票精準對應" if ci["in_palette"] else f"帶色例外：與色票最近 ΔE={ci['delta_e']:.1f}，保留平塗原色"
        lines.append(f"| `{hex_code}` | {ci['name']} | `{ci['group']}` | {cnt} | {note} |")

    cmd_str = (
        "uv run --with pillow --with numpy python tools/texture-palette/cut_faces.py "
        f"--glb {glb_path} --flat {flat_path} --palette {palette_path} "
        f"--out-dir {out_dir} --min-area {min_area} --rdp-eps {rdp_eps}"
    )
    lines.extend([
        "",
        "## 執行指令",
        "",
        "```sh",
        cmd_str,
        "```",
        "",
        "## 輸出檔案",
        "",
        f"- GLB：`{out_glb}`",
        f"- UV 切面圖：`{out_uv}`",
    ])
    out_summary = out_dir / "summary.md"
    out_summary.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return {
        "orig_tris": len(idx),
        "total_tris": total_tris,
        "body_tris": len(body_tris),
        "glass_tris": len(glass_tris),
        "merged_fragments": merged_fragments,
        "elapsed": elapsed,
        "color_tri_counts": dict(color_tri_counts),
        "out_glb": str(out_glb),
        "out_uv": str(out_uv),
        "out_summary": str(out_summary),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Cut GLB triangles along flat texture color boundaries in UV space.")
    parser.add_argument("--glb", type=Path, required=True)
    parser.add_argument("--flat", type=Path, required=True)
    parser.add_argument("--palette", type=Path, required=True)
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--min-area", type=int, default=22)
    parser.add_argument("--rdp-eps", type=float, default=1.8)
    args = parser.parse_args()

    res = run_cut(
        glb_path=args.glb.expanduser(),
        flat_path=args.flat.expanduser(),
        palette_path=args.palette.expanduser(),
        out_dir=args.out_dir.expanduser(),
        min_area=args.min_area,
        rdp_eps=args.rdp_eps,
    )
    print(json.dumps(res, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
