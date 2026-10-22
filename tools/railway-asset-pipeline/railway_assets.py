#!/usr/bin/env python3
"""Railway owner-supplied asset explorer: indexed resources, X geometry and previews.

Standard-library stages require Python >=3.10. GLB preview conversion is optional
and imports numpy/trimesh/Pillow only when called. It is not a production exporter.
All asset inputs/outputs are local paths; this script makes no network requests.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import mmap
from pathlib import Path
import re
import shutil
import struct
import sys
import tempfile

X_HEADER = b"xof 0303bin 0032"
MARKS = "{}()[]<>.,;"
MAX_ITEMS = 200_000
MAX_RECORD_BYTES = 512 * 1024 * 1024


class FormatError(ValueError):
    pass


def save_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_name(name: str) -> str:
    normalized = name.replace("\\", "/")
    leaf = normalized.rsplit("/", 1)[-1]
    if not leaf or leaf in {".", ".."} or "\x00" in leaf:
        raise FormatError("Unsafe resource name")
    if not re.fullmatch(r"[\w .()+@_-]{1,255}", leaf, flags=re.UNICODE):
        raise FormatError("Resource name contains unsupported characters: " + repr(name))
    return leaf


def named_records(buffer: mmap.mmap | bytes, *, textures: bool) -> list[dict]:
    """Count, UTF-16LE name (512 bytes), size; textures also have width + height."""
    length = len(buffer)
    if length < 4:
        raise FormatError("Missing resource count")
    count = struct.unpack_from("<I", buffer, 0)[0]
    if count > MAX_ITEMS:
        raise FormatError(f"Implausible resource count: {count}")
    offset = 4
    rows: list[dict] = []
    seen: set[str] = set()
    for index in range(count):
        header = 524 if textures else 516
        if offset + header > length:
            raise FormatError(f"Short record header #{index} at {offset}")
        name = buffer[offset:offset + 512].decode("utf-16le").split("\x00", 1)[0]
        leaf = safe_name(name)
        if leaf.casefold() in seen:
            raise FormatError(f"Duplicate resource name in one pack: {leaf}")
        seen.add(leaf.casefold())
        if textures:
            width, height, size = struct.unpack_from("<III", buffer, offset + 512)
            start = offset + 524
            if not (width > 0 and height > 0 and size >= 128):
                raise FormatError(f"Invalid texture dimensions/length for {leaf}")
        else:
            size = struct.unpack_from("<I", buffer, offset + 512)[0]
            start = offset + 516
            width = height = None
        if size > MAX_RECORD_BYTES or start + size > length:
            raise FormatError(f"Truncated resource {leaf}: bytes={size}")
        magic = bytes(buffer[start:start + 4])
        if textures:
            if magic != b"DDS ":
                raise FormatError(f"Expected DDS header in {leaf}")
            header_height, header_width = struct.unpack_from("<II", buffer, start + 12)
            if (header_width, header_height) != (width, height):
                raise FormatError(f"DDS dimensions differ from catalog for {leaf}")
        rows.append(dict(index=index, name=leaf, offset=start, size=size,
                         width=width, height=height, magic=magic.hex()))
        offset = start + size
    if offset != length:
        raise FormatError(f"Unexpected trailing bytes: {length - offset}")
    return rows


def cmd_index_pack(args: argparse.Namespace) -> None:
    path = Path(args.input)
    with path.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as mm:
        rows = named_records(mm, textures=args.kind == "textures")
        if args.extract_dir:
            output = Path(args.extract_dir)
            output.mkdir(parents=True, exist_ok=True)
            for entry in rows:
                (output / entry["name"]).write_bytes(
                    mm[entry["offset"]:entry["offset"] + entry["size"]]
                )
    save_json(Path(args.index_json), dict(pack=path.name, sha256=source_hash(path),
                                           kind=args.kind, count=len(rows), entries=rows))
    print(f"indexed {len(rows)} {args.kind} from {path.name}")


def x_tokens(blob: bytes):
    """Minimal DirectX binary X lexer; used only for geometry preview and frame names."""
    if len(blob) < 16 or blob[:16] != X_HEADER:
        raise FormatError("Not the supported 32-bit binary DirectX X encoding")
    p, length = 16, len(blob)
    while p < length:
        if p + 2 > length:
            raise FormatError("Partial X token")
        token = struct.unpack_from("<H", blob, p)[0]
        p += 2
        if token in (1, 2):
            if p + 4 > length:
                raise FormatError("Short X name length")
            size = struct.unpack_from("<I", blob, p)[0]
            p += 4
            if size > length - p:
                raise FormatError("Short X name")
            name = blob[p:p + size].decode("cp932", "replace").rstrip("\x00")
            p += size
            yield ("name" if token == 1 else "quoted"), name
            if token == 2:
                if p + 4 > length:
                    raise FormatError("Short X string delimiter")
                delimiter = struct.unpack_from("<I", blob, p)[0]
                p += 4
                if delimiter in (19, 20):
                    yield "mark", MARKS[delimiter - 10]
        elif token == 3:
            if p + 4 > length:
                raise FormatError("Short X integer")
            yield "int", struct.unpack_from("<I", blob, p)[0]
            p += 4
        elif token == 5:
            if p + 16 > length:
                raise FormatError("Short X GUID")
            p += 16
            yield "guid", None
        elif token in (6, 7):
            if p + 4 > length:
                raise FormatError("Short X array length")
            count = struct.unpack_from("<I", blob, p)[0]
            p += 4
            width = 4  # X_HEADER declares 32-bit numeric payload
            if count > (length - p) // width:
                raise FormatError("X numeric array extends past EOF")
            kind, fmt = ("int", "I") if token == 6 else ("float", "f")
            for (value,) in struct.iter_unpack("<" + fmt, blob[p:p + 4 * count]):
                yield kind, value
            p += 4 * count
        elif 10 <= token <= 20:
            yield "mark", MARKS[token - 10]
        elif token == 31:
            yield "name", "template"
        elif 40 <= token <= 52:
            yield "name", ("WORD", "DWORD", "FLOAT", "DOUBLE", "CHAR", "UCHAR",
                           "SWORD", "SDWORD", "void", "string", "unicode", "cstring", "array")[token - 40]
        else:
            raise FormatError(f"Unknown DirectX token {token} at {p - 2}")


def first_frame_name(binary_x: bytes) -> str | None:
    try:
        lex = x_tokens(binary_x)
        for kind, name in lex:
            if kind == "name" and name == "Frame":
                next_kind, next_name = next(lex)
                if next_kind == "name" and next_name:
                    return next_name
    except (FormatError, StopIteration):
        pass
    return None


def x_records(mm: mmap.mmap | bytes, source_prefix: str) -> list[dict]:
    positions: list[dict] = []
    length = len(mm)
    start = 0
    while True:
        at = mm.find(b"ADX0", start)
        if at < 0:
            break
        start = at + 4
        if at + 28 > length:
            continue
        version, size = struct.unpack_from("<II", mm, at + 4)
        data_at = at + 12
        if size < len(X_HEADER) or size > MAX_RECORD_BYTES or data_at + size > length:
            continue
        if mm[data_at:data_at + len(X_HEADER)] != X_HEADER:
            continue
        name = first_frame_name(bytes(mm[data_at:data_at + size]))
        index = len(positions)
        readable = re.sub(r"[^A-Za-z0-9_-]", "_", name or "unnamed")[:100]
        positions.append(dict(index=index, start=at, version=version,
                              body_start=data_at, bytes=size, name_guess=name,
                              source_x=f"{source_prefix}_{index:04d}_{readable}.x"))
        start = data_at + size
    return positions


def cmd_index_x(args: argparse.Namespace) -> None:
    path = Path(args.input)
    if path.stat().st_size == 0:
        raise FormatError("Empty model stream")
    with path.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as mm:
        records = x_records(mm, path.stem)
        if args.extract_dir:
            dest = Path(args.extract_dir)
            dest.mkdir(parents=True, exist_ok=True)
            for record in records:
                (dest / record["source_x"]).write_bytes(
                    mm[record["body_start"]:record["body_start"] + record["bytes"]])
    save_json(Path(args.index_json), dict(pack=path.name, sha256=source_hash(path),
                                          count=len(records), entries=records))
    print(f"indexed {len(records)} DirectX X sections from {path.name}")


def read_utf16_table(path: Path) -> list[list[str]]:
    with path.open("r", encoding="utf-16", newline="") as source:
        return list(csv.reader(source))


def model_family(frame: str | None, prefixes: set[str]) -> str | None:
    if not frame:
        return None
    lowered = frame.casefold()
    for marker in ("_d_t_", "_t_", "_d_"):
        if not lowered.startswith(marker):
            continue
        rest = lowered[len(marker):]
        matches = [prefix for prefix in prefixes if rest == prefix.casefold()
                   or rest.startswith(prefix.casefold() + "_")]
        if matches:
            return max(matches, key=len)
    return None


def select_vehicle_records(form_rows: list[list[str]], pattern_rows: list[list[str]],
                           records: list[dict], *, start: int, count: int) -> list[dict]:
    chosen = form_rows[start:start + count]
    if len(chosen) != count:
        raise FormatError(f"Only {len(chosen)} vehicle records found; expected {count}")
    groups: dict[str, list[list[str]]] = {}
    current = None
    for row in pattern_rows:
        if row and row[0]:
            current = row[0]
        if current:
            groups.setdefault(current, []).append(row)
    for form in chosen:
        if len(form) <= 19 or form[0] not in groups:
            raise FormatError("Missing vehicle catalog/form association")
    prefixes = {groups[form[0]][0][1].casefold() for form in chosen}
    bucket: dict[str, list[dict]] = {prefix: [] for prefix in prefixes}
    for record in records:
        family = model_family(record.get("name_guess"), prefixes)
        if family:
            bucket[family.casefold()].append(record)
    vehicles = []
    for ordinal, row in enumerate(chosen, 1):
        form_id = row[0]
        lines = groups[form_id]
        prefix = lines[0][1].casefold()
        units = [dict(unit_index=i + 1, model_reference=line[2])
                 for i, line in enumerate(lines) if len(line) > 2 and line[2].startswith("_")]
        formations = []
        for line in lines:
            if len(line) <= 17 or not line[17].strip().isdigit():
                continue
            cars = []
            for slot in line[6:16]:
                if re.fullmatch(r"-?\d+", slot.strip()):
                    n = int(slot)
                    cars.append(dict(unit_index=abs(n), reversed=n < 0))
            if cars:
                formations.append(dict(length=int(line[17]), cars=cars,
                                       is_default=any("\u25cb" in cell for cell in line[6:17])))
        models = [dict(source_index=e["index"], model_name_guess=e.get("name_guess"),
                       source_x=e["source_x"],
                       expected_glb=Path(e["source_x"]).with_suffix(".glb").name,
                       body_start=e["body_start"], bytes=e["bytes"]) for e in bucket[prefix]]
        vehicles.append(dict(ordinal=ordinal, form_id=form_id,
                             vehicle_name=row[19], model_prefix=prefix,
                             model_chunk_count=len(models), units=units,
                             formations=formations, models=models))
    return vehicles


def cmd_select_vehicles(args: argparse.Namespace) -> None:
    model_idx = json.loads(Path(args.x_index).read_text(encoding="utf-8"))
    records = model_idx["entries"]
    vehicles = select_vehicle_records(read_utf16_table(Path(args.forms)),
                                      read_utf16_table(Path(args.patterns)),
                                      records, start=args.start, count=args.count)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    with Path(args.x_stream).open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as mm:
        for vehicle in vehicles:
            directory = out / "models" / f'{vehicle["ordinal"]:02d}_{vehicle["model_prefix"]}'
            directory.mkdir(parents=True, exist_ok=True)
            for record in vehicle["models"]:
                begin = record["body_start"]
                end = begin + record["bytes"]
                if end > len(mm):
                    raise FormatError("Selected X offset extends past source stream")
                (directory / record["source_x"]).write_bytes(mm[begin:end])
    manifest = dict(vehicle_count=len(vehicles), selected_x=sum(v["model_chunk_count"] for v in vehicles),
                    selection=dict(start=args.start, count=args.count),
                    source_index_sha256=source_hash(Path(args.x_index)),
                    status="geometric sources only; optional GLB and draft formations are separate",
                    vehicles=vehicles)
    save_json(out / "railway_vehicles.json", manifest)
    print(f'selected {len(vehicles)} vehicle types, {manifest["selected_x"]} X parts')


def convert_x_to_glb(source: Path, output: Path) -> dict:
    """Geometry-only: strips material definitions, retains UVs with neutral preview material."""
    try:
        import numpy as np
        import trimesh
        from PIL import Image
    except ImportError as exc:
        raise RuntimeError("Preview conversion needs numpy, trimesh and Pillow installed outside the repo") from exc
    tt = list(x_tokens(source.read_bytes()))
    geometry = []

    def skip(pos):
        while pos < len(tt) and tt[pos] in (("mark", ";"), ("mark", ",")):
            pos += 1
        return pos

    def number(pos):
        pos = skip(pos)
        if pos >= len(tt) or tt[pos][0] not in ("float", "int"):
            raise FormatError(f"Numeric token missing at {pos}")
        return float(tt[pos][1]), pos + 1

    def opener(pos):
        pos += 1
        if pos < len(tt) and tt[pos][0] == "name":
            pos += 1
        return pos if pos < len(tt) and tt[pos] == ("mark", "{") else None

    def end_of_block(pos):
        depth, pos = 1, pos + 1
        while pos < len(tt) and depth:
            if tt[pos] == ("mark", "{"):
                depth += 1
            elif tt[pos] == ("mark", "}"):
                depth -= 1
            pos += 1
        return pos

    for i, token in enumerate(tt):
        if token != ("name", "Mesh"):
            continue
        brace = opener(i)
        if brace is None or brace + 1 >= len(tt) or tt[brace + 1][0] != "int":
            continue
        try:
            pos = brace + 1
            n_vertices, pos = number(pos)
            n_vertices = int(n_vertices)
            if not 3 <= n_vertices <= 500_000:
                continue
            values = []
            for _ in range(n_vertices * 3):
                v, pos = number(pos)
                values.append(v)
            vertices = np.array(values, dtype=np.float32).reshape(-1, 3)
            n_faces, pos = number(pos)
            n_faces = int(n_faces)
            if not 0 <= n_faces <= 1_000_000:
                raise FormatError("Unexpected face count")
            faces = []
            for _ in range(n_faces):
                count, pos = number(pos)
                count = int(count)
                if not 3 <= count <= 128:
                    raise FormatError("Unexpected polygon size")
                ids = []
                for _ in range(count):
                    vertex_id, pos = number(pos)
                    ids.append(int(vertex_id))
                for j in range(1, count - 1):
                    tri = (ids[0], ids[j], ids[j + 1])
                    if min(tri) < 0 or max(tri) >= n_vertices:
                        raise FormatError("Face index out of range")
                    faces.append(tri)
            if not faces:
                continue
            uv = None
            for j in range(pos, end_of_block(brace)):
                if tt[j] == ("name", "MeshTextureCoords"):
                    nested = opener(j)
                    if nested is None:
                        continue
                    texture_vertices, at = number(nested + 1)
                    if int(texture_vertices) == n_vertices:
                        coords = []
                        for _ in range(n_vertices * 2):
                            value, at = number(at)
                            coords.append(value)
                        uv = np.array(coords, dtype=np.float32).reshape(-1, 2)
                    break
            vertices[:, 2] *= -1  # DirectX left-handed -> glTF right-handed.
            faces_array = np.asarray(faces, dtype=np.int64)
            faces_array[:, [1, 2]] = faces_array[:, [2, 1]]
            mesh = trimesh.Trimesh(vertices=vertices, faces=faces_array, process=False)
            if uv is not None:
                placeholder = Image.new("RGB", (4, 4), (188, 202, 212))
                mesh.visual = trimesh.visual.TextureVisuals(
                    uv=uv, material=trimesh.visual.material.SimpleMaterial(
                        image=placeholder, name="NEUTRAL_PREVIEW_NOT_SOURCE_TEXTURE"))
            geometry.append(mesh)
        except (FormatError, ValueError, IndexError):
            continue
    if not geometry:
        raise FormatError("No triangle mesh found; no blank GLB created")
    scene = trimesh.Scene()
    for i, mesh in enumerate(geometry):
        scene.add_geometry(mesh, geom_name=f"part_{i:03d}")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Do not leave a corrupt final GLB if export or verification fails.
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".glb", delete=False) as temp:
        staged = Path(temp.name)
    try:
        scene.export(str(staged))
        loaded = trimesh.load(str(staged), force="scene")
        meshes = list(loaded.geometry.values())
        if not meshes or not all(len(x.faces) and np.isfinite(x.vertices).all() for x in meshes):
            raise FormatError("GLB reimport and finite geometry checks failed")
        staged.replace(output)
    finally:
        staged.unlink(missing_ok=True)
    return dict(mesh_count=len(meshes), vertices=sum(len(x.vertices) for x in meshes),
                triangles=sum(len(x.faces) for x in meshes), uv_preview=bool(any(
                    getattr(x.visual, "uv", None) is not None for x in meshes)))


def cmd_convert_glb(args: argparse.Namespace) -> None:
    root = Path(args.models_dir)
    all_x = sorted(root.rglob("*.x"))
    results = []
    for x in all_x:
        destination = x.with_suffix(".glb")
        try:
            stats = convert_x_to_glb(x, destination)
            results.append(dict(file=x.relative_to(root).as_posix(), status="VERIFIED",
                                glb=destination.name, **stats))
        except Exception as exc:
            results.append(dict(file=x.relative_to(root).as_posix(), status="UNCONVERTED",
                                reason=str(exc)))
    summary = dict(source_x=len(all_x), converted=sum(r["status"] == "VERIFIED" for r in results),
                   results=results, scope="geometry + UV preview; textures/animation not attached")
    save_json(Path(args.report), summary)
    print(f'converted {summary["converted"]}/{len(all_x)} geometry previews')


def dds_end(buffer: mmap.mmap | bytes, offset: int) -> int:
    if buffer[offset:offset + 4] != b"DDS " or offset + 128 > len(buffer):
        raise FormatError("DDS signature/header missing")
    header_size = struct.unpack_from("<I", buffer, offset + 4)[0]
    height, width = struct.unpack_from("<II", buffer, offset + 12)
    if header_size != 124 or not (0 < width <= 16384 and 0 < height <= 16384):
        raise FormatError("Unexpected DDS header/dimensions")
    fourcc = bytes(buffer[offset + 84:offset + 88])
    if fourcc in (b"DXT1", b"DXT3", b"DXT5"):
        block_bytes = 8 if fourcc == b"DXT1" else 16
        payload = ((width + 3) // 4) * ((height + 3) // 4) * block_bytes
    else:
        # Preview probe for common uncompressed 32-bit DDS, not a general DDS loader.
        payload = width * height * 4
    return offset + 128 + payload


def cmd_tp_sprites(args: argparse.Namespace) -> None:
    path = Path(args.input)
    with path.open("rb") as file, mmap.mmap(file.fileno(), 0, access=mmap.ACCESS_READ) as mm:
        first = args.first_name.encode("utf-16le")
        table_at = mm.find(first)
        if table_at < 0:
            raise FormatError("2D preview filename table marker not found")
        names: list[str] = []
        table_end = min(len(mm), table_at + args.name_bytes)
        names_bytes = mm[table_at:table_end].decode("utf-16le", "replace")
        for name in names_bytes.split("\x00"):
            if not name.lower().endswith(".dds"):
                break
            names.append(safe_name(name))
        positions = []
        start = 0
        while True:
            at = mm.find(b"DDS ", start, table_at)
            if at < 0:
                break
            positions.append(at)
            start = at + 4
        preamble = len(positions) - len(names)
        if preamble < 0 or not names:
            raise FormatError("Preview table and DDS item count differ")
        chosen = []
        for i, name in enumerate(names):
            at = positions[preamble + i]
            end = positions[preamble + i + 1] if preamble + i + 1 < len(positions) else table_at
            if dds_end(mm, at) != end:
                raise FormatError(f"Non-contiguous DDS preview #{i}: {name}")
            if args.prefix and not name.casefold().startswith(args.prefix.casefold()):
                continue
            chunk = bytes(mm[at:end])
            folder = Path(args.output_dir)
            folder.mkdir(parents=True, exist_ok=True)
            (folder / name).write_bytes(chunk)
            width = struct.unpack_from("<I", mm, at + 16)[0]
            height = struct.unpack_from("<I", mm, at + 12)[0]
            chosen.append(dict(name=name, width=width, height=height, bytes=end - at))
    save_json(Path(args.index_json), dict(total_named=len(names), unnamed_preamble=preamble,
                                          selected=len(chosen), previews=chosen))
    print(f'validated {len(names)} 2D preview DDS records; extracted {len(chosen)}')


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    index = commands.add_parser("index-pack", help="Index and optionally extract UTF-16LE-named DDS/CSV records")
    index.add_argument("--input", required=True)
    index.add_argument("--kind", choices=["textures", "named"], required=True)
    index.add_argument("--index-json", required=True)
    index.add_argument("--extract-dir")
    index.set_defaults(func=cmd_index_pack)

    x = commands.add_parser("index-x", help="Index ADX0-wrapped DirectX Binary X mesh records")
    x.add_argument("--input", required=True)
    x.add_argument("--index-json", required=True)
    x.add_argument("--extract-dir", help="Optional: write every X section; may be thousands")
    x.set_defaults(func=cmd_index_x)

    forms = commands.add_parser("select-vehicles", help="Cross-reference local UTF-16 catalog and model frames")
    forms.add_argument("--forms", required=True)
    forms.add_argument("--patterns", required=True)
    forms.add_argument("--x-index", required=True)
    forms.add_argument("--x-stream", required=True)
    forms.add_argument("--output-dir", required=True)
    forms.add_argument("--start", type=int, required=True, help="0-based index in source form table")
    forms.add_argument("--count", type=int, required=True)
    forms.set_defaults(func=cmd_select_vehicles)

    convert = commands.add_parser("convert-glb", help="Optional geometry/UV-only X -> GLB preview")
    convert.add_argument("--models-dir", required=True)
    convert.add_argument("--report", required=True)
    convert.set_defaults(func=cmd_convert_glb)

    tp = commands.add_parser("tp-sprites", help="Validate and extract name-mapped 2D DDS previews")
    tp.add_argument("--input", required=True)
    tp.add_argument("--output-dir", required=True)
    tp.add_argument("--index-json", required=True)
    tp.add_argument("--first-name", default="automobile_bus00_1_f.dds")
    tp.add_argument("--prefix", help="Optional filename prefix, e.g. form_e353_")
    tp.add_argument("--name-bytes", type=int, default=150000)
    tp.set_defaults(func=cmd_tp_sprites)

    args = parser.parse_args(argv)
    try:
        args.func(args)
        return 0
    except (OSError, ValueError, RuntimeError, UnicodeError, struct.error) as exc:
        print(f"Railway asset pipeline: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
