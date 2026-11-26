#!/usr/bin/env python3
"""Automatic checks of a landmark model against its survey, run by whoever
built it before the review (`.claude/skills/landmark-survey/SKILL.md`): the
review then looks at the photographs, not at numbers a script can count.

    uv run --with numpy python -I tools/landmark-survey/landmark_check.py MODEL.glb \\
        [--survey DIR/survey.json] [--up y|z] [--tolerance 0.05] [--max-triangles 15000] \\
        [--allow-open M2] [--allow-ground-plate] [--md OUT.md]

MODEL is a GLB (glTF's +y up unless `--up z`). Checks:

1. Size: the outline 1 m above the model's foot (where the walls stand,
   below the eaves) against the survey's footprint: long and short side
   within `--tolerance` (5 %).
2. Height: foot to top against the survey's height within `--tolerance`
   when the survey's height has a source; an estimate (levels × storey) is
   only printed.
3. Closed on top: the model seen straight from above in 0.25 m cells.
   A cell whose highest face looks down (the back of a wall or roof) or an
   empty cell walled in by the model (an open shaft) shows the inside or
   the ground through the building; more than 0.25 m² of either fails.
   A courtyard that is meant to be open passes with `--allow-open` and its
   area. (Pocket City's `references/landmarks.md`: "Close every level on
   top"; model-look checklist 11.)
4. Faces of different colours in one plane that overlap, and nearly so
   (normals within 2°, within 5 cm): `tools/texture-palette/port_check.py`'s
   `coplanar` and `near_coplanar`.
5. Degenerate faces (three points in a line at millimetres).
6. Triangles at most `--max-triangles` (one native model, shoot.mjs).
7. No ground plate: level faces looking up at the foot reaching more than
   25 m² beyond the body (`tools/landmarks/ground_plate.py`'s rule; the map
   draws its own ground).
8. The ground: when the survey's ground under the footprint drops more than
   0.5 m, prints the drop, which the model's plinth must step down
   (model-look §6, moving an old model, the second point).

Exit code 0 when all pass, 1 otherwise. The table goes into the review's
REQUEST.md as it is printed.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "texture-palette"))
import port_check  # noqa: E402

CELL = 0.25
OPEN_LIMIT = 0.25       # m² of back faces or open shafts seen from above
PLATE_LIMIT = 25.0      # m², as tools/landmarks/ground_plate.py
CUT = 1.0               # metres above the foot where the outline is measured


def load(path: Path, up: str):
    model = port_check.Car(path)
    tri = model.tri.copy()
    if up == "y":   # glTF: x, y up, z towards the viewer -> plan x, plan y, up
        tri = np.stack([tri[..., 0], -tri[..., 2], tri[..., 1]], -1)
    model.plan = tri
    return model


def outline_at(tri, z):
    """Points where the plane at height `z` cuts the triangles."""
    pts = []
    for t in tri:
        d = t[:, 2] - z
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if (d[a] < 0) != (d[b] < 0):
                s = d[a] / (d[a] - d[b])
                pts.append(t[a, :2] + s * (t[b, :2] - t[a, :2]))
    return np.array(pts)


def size_check(tri, survey, tolerance):
    foot = tri[..., 2].min()
    pts = outline_at(tri, foot + CUT)
    if len(pts) < 3:
        return None, "nothing stands 1 m above the foot"
    got = survey_box(pts)
    want = survey["footprint"]["box"] if survey else None
    if not want:
        return got, None
    bad = [f"{k} {got[k]:.2f} m against {want[k]} m" for k in ("L", "W") if abs(got[k] - want[k]) > tolerance * want[k]]
    return got, "; ".join(bad) or None


def survey_box(pts):
    sys.path.insert(0, str(HERE))
    import survey
    return survey.box(pts)


def top_view(tri):
    """Highest face per cell from above; (back-facing m², open-shaft m², cells)."""
    lo, hi = tri[..., :2].reshape(-1, 2).min(0) - CELL, tri[..., :2].reshape(-1, 2).max(0) + CELL
    nx, ny = int(np.ceil((hi[0] - lo[0]) / CELL)), int(np.ceil((hi[1] - lo[1]) / CELL))
    top = np.full((ny, nx), -np.inf)
    up = np.zeros((ny, nx), bool)
    normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    for t, n in zip(tri, normals):
        if abs(n[2]) < 1e-9:
            continue
        a, b, c = t[:, :2]
        x0, x1 = int((min(a[0], b[0], c[0]) - lo[0]) / CELL), int((max(a[0], b[0], c[0]) - lo[0]) / CELL) + 1
        y0, y1 = int((min(a[1], b[1], c[1]) - lo[1]) / CELL), int((max(a[1], b[1], c[1]) - lo[1]) / CELL) + 1
        xs = lo[0] + (np.arange(x0, x1) + 0.5) * CELL
        ys = lo[1] + (np.arange(y0, y1) + 0.5) * CELL
        gx, gy = np.meshgrid(xs, ys)
        den = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(den) < 1e-12:
            continue
        w0 = ((b[1] - c[1]) * (gx - c[0]) + (c[0] - b[0]) * (gy - c[1])) / den
        w1 = ((c[1] - a[1]) * (gx - c[0]) + (a[0] - c[0]) * (gy - c[1])) / den
        w2 = 1 - w0 - w1
        hit = (w0 >= -1e-9) & (w1 >= -1e-9) & (w2 >= -1e-9)
        if not hit.any():
            continue
        z = w0 * t[0, 2] + w1 * t[1, 2] + w2 * t[2, 2]
        block = top[y0:y1, x0:x1]
        better = hit & (z > block + 1e-6)
        block[better] = z[better]
        up[y0:y1, x0:x1][better] = n[2] > 0
    filled = np.isfinite(top)
    back = filled & ~up
    # empty cells not reachable from the edge are walled in
    outside = np.zeros_like(filled)
    stack = [(y, x) for y in range(ny) for x in (0, nx - 1)] + [(y, x) for x in range(nx) for y in (0, ny - 1)]
    while stack:
        y, x = stack.pop()
        if 0 <= y < ny and 0 <= x < nx and not outside[y, x] and not filled[y, x]:
            outside[y, x] = True
            stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    shaft = ~filled & ~outside
    return back.sum() * CELL * CELL, shaft.sum() * CELL * CELL, filled.sum()


def ground_plate(tri):
    foot = tri[..., 2].min()
    height = tri[..., 2].max() - foot
    body = tri.reshape(-1, 3)
    body = body[body[:, 2] > foot + max(1.0, 0.12 * height)]
    if not len(body):
        return 0.0
    blo, bhi = body[:, :2].min(0) - 0.5, body[:, :2].max(0) + 0.5
    total = 0.0
    for t in tri:
        if t[:, 2].max() > foot + 0.05:
            continue
        n = np.cross(t[1] - t[0], t[2] - t[0])
        length = np.linalg.norm(n)
        if length == 0 or n[2] / length < 0.98:
            continue
        if ((t[:, :2] < blo) | (t[:, :2] > bhi)).any():
            total += length / 2
    return total


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("model")
    ap.add_argument("--survey")
    ap.add_argument("--up", choices=("y", "z"), default="y")
    ap.add_argument("--tolerance", type=float, default=0.05)
    ap.add_argument("--max-triangles", type=int, default=15000)
    ap.add_argument("--allow-open", type=float, default=0.0, help="m² of courtyard meant to be open")
    ap.add_argument("--allow-ground-plate", action="store_true")
    ap.add_argument("--md")
    a = ap.parse_args(argv)
    model = load(Path(a.model), a.up)
    tri = model.plan
    survey = json.loads(Path(a.survey).read_text()) if a.survey else None
    rows = []

    def row(name, ok, detail):
        rows.append((name, "看" if ok is None else "過" if ok else "不過", detail))

    got, bad = size_check(tri, survey, a.tolerance)
    if got is None:
        row("1 輪廓大小", False, bad)
    elif survey:
        b = survey["footprint"]["box"]
        row("1 輪廓大小", bad is None, f"離地 1 m 的外框 {got['L']} × {got['W']} m，實測 {b['L']} × {b['W']} m"
            + (f"：{bad}" if bad else ""))
    else:
        row("1 輪廓大小", None, f"離地 1 m 的外框 {got['L']} × {got['W']} m（沒給 --survey）")
    foot, top = tri[..., 2].min(), tri[..., 2].max()
    h = survey.get("height") if survey else None
    if h and not h["estimate"]:
        row("2 高度", abs((top - foot) - h["value"]) <= a.tolerance * h["value"],
            f"{top - foot:.2f} m，實測 {h['value']} m（{h['source']}）")
    else:
        row("2 高度", None, f"{top - foot:.2f} m" + (f"；實測只有推估 {h['value']} m" if h else "；實測沒有高度"))
    back, shaft, _ = top_view(tri)
    row("3 從上面看封頂", back <= OPEN_LIMIT and shaft <= OPEN_LIMIT + a.allow_open,
        f"看到背面 {back:.2f} m²、圍起來的空洞 {shaft:.2f} m²" + (f"（容許天井 {a.allow_open} m²）" if a.allow_open else ""))
    same, degenerate = port_check.coplanar(model)
    near = port_check.near_coplanar(model)
    row("4 異色共面", not same and not near, f"精確 {len(same)} 對、近共面 {len(near)} 對"
        + (f"；最大 {model.where(same[0][1])} ↔ {model.where(same[0][2])}" if same else ""))
    row("5 退化面", not degenerate, f"{len(degenerate)} 個")
    row("6 三角形", len(tri) <= a.max_triangles, f"{len(tri)}（上限 {a.max_triangles}）")
    plate = ground_plate(tri)
    row("7 自帶地坪", plate <= PLATE_LIMIT or a.allow_ground_plate, f"本體外 {plate:.1f} m²（上限 {PLATE_LIMIT:.0f}）")
    g = survey.get("ground") if survey else None
    if g:
        row("8 地面落差", None, f"輪廓下 {g['lowest']}–{g['highest']} m，落差 {g['drop']} m"
            + ("：台基要照坡分層" if g["drop"] > 0.5 else ""))
    lines = ["| 項目 | 結果 | 數字 |", "| --- | --- | --- |"] + [f"| {n} | {r} | {d} |" for n, r, d in rows]
    print("\n".join(lines))
    if a.md:
        Path(a.md).write_text(f"# {Path(a.model).name} 自動檢查\n\n" + "\n".join(lines) + "\n")
    return 1 if any(r == "不過" for _, r, _ in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
