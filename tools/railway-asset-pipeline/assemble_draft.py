#!/usr/bin/env python3
"""Create approximate GLB formation previews from owner-supplied Railway car GLBs.

This is a review aid, not authentic coupling/pivot reconstruction. Geometry,
orientation flags and rough car order are inspectable; texture and animations
are not invented. No model data ships with this source.
"""
import argparse
import json
import math
from pathlib import Path
import sys


def generate(manifest_path: Path, models_dir: Path, output_dir: Path, gap: float = 0.4):
    try:
        import numpy as np
        import trimesh
    except ImportError as exc:
        raise RuntimeError("Private GLB preview assembly needs numpy and trimesh") from exc

    if not (0 <= gap <= 5.0):
        raise ValueError("Gap must be a small nonnegative distance in model units")
    source = json.loads(manifest_path.read_text(encoding="utf-8"))
    output_dir.mkdir(parents=True, exist_ok=True)
    assembled = []
    for vehicle in source["vehicles"]:
        code = f'{vehicle["ordinal"]:02d}_{vehicle["model_prefix"]}'
        directory = models_dir / code
        candidate = [m for m in vehicle["models"]
                     if (directory / m["expected_glb"]).is_file()
                     and not (m.get("model_name_guess") or "").lower().endswith("_sd1")]
        model_map = []
        warnings = []
        for unit_index, unit in enumerate(vehicle["units"]):
            reference = unit["model_reference"].lower()
            exact = [m for m in candidate if (m.get("model_name_guess") or "").lower() == reference]
            close = [m for m in candidate if (m.get("model_name_guess") or "").lower().startswith(reference + "_")]
            fallback = candidate[unit_index:unit_index + 1] or candidate[:1]
            chosen = (exact or close or fallback)
            if not chosen:
                warnings.append("Missing mesh for " + reference)
                model_map.append(None)
                continue
            model_map.append(chosen[0])
            if not (exact or close):
                warnings.append("Approximated " + reference + " with " + str(chosen[0].get("name_guess")))

        formations = vehicle.get("formations", [])
        default = next((f for f in formations if f.get("is_default")), None)
        formation = default or (formations[-1] if formations else None)
        if not formation:
            warnings.append("No formation definition available")
            assembled.append(dict(form_id=vehicle["form_id"], status="MISSING_FORMATION", warnings=warnings))
            continue

        scene = trimesh.Scene()
        cache = {}
        last_pos, last_length = 0.0, 0.0
        placements = []
        for order, car in enumerate(formation["cars"], 1):
            at = car["unit_index"] - 1
            if at < 0 or at >= len(model_map) or not model_map[at]:
                warnings.append("Missing mapped unit " + str(car["unit_index"]))
                continue
            model = model_map[at]
            path = directory / model["expected_glb"]
            if path not in cache:
                loaded = trimesh.load(str(path), force="scene")
                meshes = [part for part in loaded.geometry.values()
                          if isinstance(part, trimesh.Trimesh) and len(part.faces)]
                if not meshes:
                    warnings.append("No geometry in " + path.name)
                    continue
                merged = np.concatenate([part.vertices for part in meshes], axis=0)
                centre = (merged.min(axis=0) + merged.max(axis=0)) / 2
                length = float(np.ptp(merged[:, 2]))
                if not (np.isfinite(length) and length > 0.01):
                    warnings.append("Invalid length in " + path.name)
                    continue
                cache[path] = (meshes, centre, length)
            if path not in cache:
                continue
            meshes, centre, length = cache[path]
            position = (last_pos + last_length / 2 + length / 2 + gap) if placements else 0.0
            last_pos, last_length = position, length
            local = trimesh.transformations.translation_matrix([-centre[0], 0, -centre[2]])
            reverse = (trimesh.transformations.rotation_matrix(math.pi, [0, 1, 0])
                       if car.get("reversed") else np.eye(4))
            forward = trimesh.transformations.translation_matrix([0, 0, position])
            transform = forward @ reverse @ local
            for part_index, mesh in enumerate(meshes):
                scene.add_geometry(mesh, geom_name=f"car{order:02d}_{part_index:02d}",
                                   node_name=f"unit{car['unit_index']}_{order:02d}_{part_index:02d}",
                                   transform=transform)
            placements.append(dict(order=order, unit_index=car["unit_index"],
                                   source_index=model["source_index"], reversed=bool(car.get("reversed")),
                                   offset_z=round(position, 4)))
        if not placements:
            assembled.append(dict(form_id=vehicle["form_id"], status="NO_RENDERABLE_CARS",
                                  warnings=warnings))
            continue

        output = output_dir / f'{code}_draft_formation.glb'
        scene.export(str(output))
        loaded = trimesh.load(str(output), force="scene")
        if len(loaded.graph.nodes_geometry) < len(placements):
            output.unlink(missing_ok=True)
            raise ValueError("GLB formation failed reimport: " + code)
        record = dict(form_id=vehicle["form_id"], prefix=vehicle["model_prefix"],
                      status="APPROXIMATE_DRAFT", glb=output.name,
                      nominal_cars=formation["length"], placed_cars=len(placements),
                      gap_model_units=gap, placements=placements, warnings=sorted(set(warnings)))
        assembled.append(record)
        (output_dir / f'{code}_formation_manifest.json').write_text(
            json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output_dir / "formation_audit.json").write_text(
        json.dumps(dict(vehicles=len(assembled),
                        exported=sum(x["status"] == "APPROXIMATE_DRAFT" for x in assembled),
                        details=assembled), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return assembled


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", required=True, help="railway_vehicles.json from select-vehicles")
    parser.add_argument("--models-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--gap", type=float, default=0.4)
    args = parser.parse_args()
    try:
        result = generate(Path(args.manifest), Path(args.models_dir),
                          Path(args.output_dir), args.gap)
        print(f"Exported {sum(v['status'] == 'APPROXIMATE_DRAFT' for v in result)}"
              f"/{len(result)} Railway formation drafts")
        return 0
    except (ValueError, OSError, ImportError, RuntimeError) as exc:
        print("Railway formation preview: " + str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
