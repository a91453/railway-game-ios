"""Compare complete actual runtime exports, independently of hashes.lock.json.

Both runs must enumerate standard followed by studies and include one native
payload plus little-endian x/y/z/nx/ny/nz/color/u/v/layer words for every vertex.
No missing old model is permitted. Only the R100CK head replacement is allowed
to change existing payloads; the generic locomotive and all coaches stay pinned.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re


INTENTIONAL = {
    "set-R100CK-head", "set-R100CKFar-head",
    "light-set-R100CK-head", "light-set-R100CKFar-head",
}
FIELDS = ["x", "y", "z", "nx", "ny", "nz", "color", "u", "v", "layer"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_run(root):
    manifest_bytes = (root / "manifest.json").read_bytes()
    manifest = json.loads(manifest_bytes)
    rows = manifest["models"]
    inventory = manifest["runtime_inventory"]
    count = inventory["standard"] + inventory["studies"]
    if count != len(rows) or len({row["id"] for row in rows}) != count:
        raise ValueError("Export is not the complete unique standard/studies runtime inventory")
    standard_vertices = sum(row["triangles"] * 3 for row in rows[:inventory["standard"]])
    studies_vertices = sum(row["triangles"] * 3 for row in rows[inventory["standard"]:])
    if (standard_vertices, studies_vertices) != (inventory["standard_vertices"], inventory["studies_vertices"]):
        raise ValueError("Actual per-model vertex totals differ from runtime inventory")
    records = {}
    for row in rows:
        native = root / row["native"]
        fields = root / "models" / (row["id"] + ".vertices.bin")
        if not native.is_file() or fields.stat().st_size != row["triangles"] * 3 * len(FIELDS) * 4:
            raise ValueError("Incomplete ten-field vertex payload: " + row["id"])
        records[row["id"]] = (row, native, fields)
    return manifest, digest(manifest_bytes), records


def compare(before, after, baseline_commit, candidate_ref):
    a, a_sha, old = read_run(before)
    b, b_sha, new = read_run(after)
    missing = sorted(set(old) - set(new))
    rows = []
    changed = []
    for name in old.keys() & new.keys():
        first, native_a_path, fields_a_path = old[name]
        second, native_b_path, fields_b_path = new[name]
        native_a, native_b = native_a_path.read_bytes(), native_b_path.read_bytes()
        fields_a, fields_b = fields_a_path.read_bytes(), fields_b_path.read_bytes()
        flags = {
            "native_bytes_identical": native_a == native_b,
            "all_ten_vertex_fields_bytes_identical": fields_a == fields_b,
            "all_vertex_fields_fnv_identical": first["hash"] == second["hash"],
            "bounds_identical": all(first[k] == second[k] for k in ["minimum", "maximum"]),
        }
        if not all(flags.values()):
            changed.append(name)
        rows.append({"id": name, **flags,
                     "baseline_native_sha256": digest(native_a),
                     "candidate_native_sha256": digest(native_b),
                     "baseline_all_fields_sha256": digest(fields_a),
                     "candidate_all_fields_sha256": digest(fields_b),
                     "baseline_all_fields_fnv": first["hash"],
                     "candidate_all_fields_fnv": second["hash"]})
    unexpected = sorted(set(changed) - INTENTIONAL)
    return {
        "status": "VERIFIED" if not missing and not unexpected else "FAILED",
        "baseline_commit": baseline_commit,
        "candidate_ref": candidate_ref,
        "baseline_manifest_sha256": a_sha,
        "candidate_manifest_sha256": b_sha,
        "baseline_runtime_inventory": a["runtime_inventory"],
        "candidate_runtime_inventory": b["runtime_inventory"],
        "method": "Actual complete standard+studies enumeration, native bytes, ten-field bytes, FNV and bounds; not a lock-file model list.",
        "all_vertex_fields": FIELDS,
        "existing_models": len(old),
        "unchanged_existing_models": len(rows) - len(changed),
        "intentional_changed": sorted(changed),
        "missing": missing,
        "unexpected_changed": unexpected,
        "new_models": sorted(set(new) - set(old)),
        "models": sorted(rows, key=lambda row: row["id"]),
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--baseline-commit", required=True)
    parser.add_argument("--candidate-ref", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-f]{40}", args.baseline_commit):
        parser.error("baseline must identify the actual unmodified commit")
    result = compare(args.before, args.after, args.baseline_commit, args.candidate_ref)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({key: value for key, value in result.items() if key != "models"}))
    raise SystemExit(0 if result["status"] == "VERIFIED" else 1)
