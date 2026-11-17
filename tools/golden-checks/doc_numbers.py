#!/usr/bin/env python3
"""Checks that the numbers docs/OVERVIEW.md §2 states match the repository
(docs/HANDOFF.md §2, "核心玩法：回饋 → 開發工具"; §7.4).

Compared:
- the save version with `SavedGame.currentVersion`
  (Sources/GameCore/World/SavedGame.swift);
- the save fixtures with the JSON files in SaveFixtures/;
- the golden schema with `GoldenScenario.schemaVersion`
  (Tests/GameCoreTests/GoldenScenario.swift);
- the golden fixtures with the JSON files in GoldenScenarios/;
- the replay fixtures with the JSON files in ReplayFixtures/;
- the last decision with the largest `### N.` in docs/ARCHITECTURE.md and
  docs/decisions/.

Only a directory's own JSON files are counted, as the tests that read them
do (ReplayFixtures/Reports/ is not a replay fixture).

The decisions: every `### N.` heading of docs/ARCHITECTURE.md appears once,
every row of the decision index (OVERVIEW §9; ARCHITECTURE points to it)
has its heading. A heading with no row yet is a note: since 2026-10-21 a
pull request writes only its own reserved section (`### N. （預約）`, put on
`main` when the work is handed out) and the game planner fills the index
after merging, so parallel pull requests do not all change the same lines.
For the same reason OVERVIEW §2 may leave the last decision to the index
(no number before the remarks); it is compared only when stated. Headings
or rows out of order, the numbers missing below the last one and the
continuation headings (`### 204（續）.`) are notes too.

Since decision 329 each new decision is a file of its own,
docs/decisions/<N>.md, whose first `### N.` heading is its number: parallel
pull requests then add different files and no longer change the same lines
of ARCHITECTURE (decision 329). Those decisions have no row in the index;
the files are their index (`--index` prints the whole table). A file whose
name is not its heading's number, a file with no heading, a file other
than README.md whose name is not a number (or is one written with leading
zeros), a number that is both a file and an ARCHITECTURE heading, or an
ARCHITECTURE heading of 329 or later is a difference.

Since decision 832 the rows a pull request scores are a file of their own
too, docs/priorities/<TASK>.md, rather than the next section of
NEXT_PRIORITIES that every parallel pull request took the same number of.
Its first line is `# <TASK>（YYYY-MM-DD，<source, with the #PR>）`, its
table has the columns 項目, 玩家, 開發, 美術, 鐵道迷, 音樂 and 加權, every
score is 1-5 and every weighted score is §19's (30/25/15/15/15). A file
not in that form is a difference; a source with no #PR is a note.
`--priorities` prints the rows of the files not merged back yet (no line
「併回：」), sorted, for the game planner to paste into the list, and
`--mark WHERE` then writes 「併回：WHERE（date）」 into those files.

Python 3 standard library only:
    python3 -I tools/golden-checks/doc_numbers.py            # report
    python3 -I tools/golden-checks/doc_numbers.py --check    # exit 1 on a difference
    python3 -I tools/golden-checks/doc_numbers.py --selftest
    python3 -I tools/golden-checks/doc_numbers.py --index    # the whole decision index
    python3 -I tools/golden-checks/doc_numbers.py --priorities [--mark "NEXT_PRIORITIES §29.30"]
"""
import argparse
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]

OVERVIEW = "docs/OVERVIEW.md"
ARCHITECTURE = "docs/ARCHITECTURE.md"
DECISIONS = "docs/decisions"
# Decision 329: decisions from this number on are files of their own.
FIRST_FILED = 329
SAVED_GAME = "Sources/GameCore/World/SavedGame.swift"
GOLDEN_SCENARIO = "Tests/GameCoreTests/GoldenScenario.swift"
# Decision 832: the rows a pull request scores are a file of their own,
# docs/priorities/<TASK>.md, which the game planner merges back into the
# priority list (`--priorities`), instead of every pull request adding the
# next section of NEXT_PRIORITIES and racing for its number.
PRIORITIES = "docs/priorities"
# NEXT_PRIORITIES §19: player 30, developer 25, art 15, railway fan 15, music 15.
WEIGHTS = (("玩家", 30), ("開發", 25), ("美術", 15), ("鐵道迷", 15), ("音樂", 15))
PRIORITY_HEADING = re.compile(r"^# ([A-Z0-9]+(?:-[A-Z0-9]+)*)（(\d{4})-(\d{2})-(\d{2})，([^）]+)）\s*$")
PRIORITY_NAME = re.compile(r"[A-Z0-9]+(?:-[A-Z0-9]+)*")
MERGED = "併回："

HEADING = re.compile(r"^### (\d+)\.(?:\s|$)")
CONTINUATION = re.compile(r"^### (\d+)（[^）]*）\.")
UNUSED = "沒有使用"


def section(text, number):
    """The lines of `## <number>.` up to the next `## ` heading."""
    lines, inside = [], False
    for line in text.splitlines():
        if line.startswith("## "):
            if inside:
                break
            inside = line.startswith(f"## {number}.")
            continue
        if inside:
            lines.append(line)
    return lines


def table_rows(lines):
    """The cells of a Markdown table's body rows."""
    rows = []
    for line in lines:
        if not line.startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-+:?", cell) for cell in cells if cell):
            continue
        rows.append(cells)
    return rows[1:] if rows else rows


def first(pattern, text):
    match = re.search(pattern, text) if text is not None else None
    return int(match.group(1)) if match else None


def overview_numbers(text):
    """What OVERVIEW §2 states, by item; `None` where it cannot be read."""
    cells = {row[0]: row[1] for row in table_rows(section(text, 2)) if len(row) >= 2}
    save, golden, replay, decisions = (cells.get(name) for name in ("存檔版本", "golden", "replay", "決策"))
    last = None
    if decisions is not None:
        # "1–217、219–265（218 沒有使用…）": the ranges before the remarks.
        numbers = [int(n) for n in re.findall(r"\d+", decisions.split("（")[0])]
        last = max(numbers) if numbers else None
    return {
        "save_version": first(r"^\s*(\d+)", save),
        "save_fixtures": first(r"共\s*(\d+)\s*個", save),
        "golden_schema": first(r"schema\s*(\d+)", golden),
        "golden_fixtures": first(r"(\d+)\s*個\s*JSON", golden),
        "replay_fixtures": first(r"^\s*(\d+)\s*個", replay),
        "last_decision": last,
    }


def headings(text):
    """(number, line) of each `### N.` heading outside code fences, and the
    continuation headings' lines."""
    found, continued, fenced = [], [], False
    for index, line in enumerate(text.splitlines(), 1):
        if line.startswith("```"):
            fenced = not fenced
            continue
        if fenced:
            continue
        if match := HEADING.match(line):
            found.append((int(match.group(1)), index))
        elif match := CONTINUATION.match(line):
            continued.append((line[4:].split(".")[0], index))
    return found, continued


def decision_files(root, differences):
    """(number, title, path) of each docs/decisions/<N>.md, by number. A file
    the directory holds that is not one decision is a difference."""
    directory = pathlib.Path(root) / DECISIONS
    files = []
    if not directory.is_dir():
        return files
    for path in sorted(directory.glob("*.md")):
        relative = f"{DECISIONS}/{path.name}"
        if path.name == "README.md":
            continue
        if not path.stem.isdigit() or path.stem != str(int(path.stem)):
            differences.append(f"{relative} 的檔名不是決策號（應該是 <N>.md，例如 {FIRST_FILED}.md）")
            continue
        found, _ = headings(path.read_text(encoding="utf-8"))
        if not found:
            differences.append(f"{relative} 沒有 ### N. 標題")
            continue
        number, line = found[0]
        if number != int(path.stem):
            differences.append(f"{relative} 的標題是 ### {number}.，檔名應該是 {number}.md")
        for other, other_line in found[1:]:
            differences.append(f"{relative} 有第二個決策標題 ### {other}.（第 {other_line} 行）；一個檔一個決策")
        title = path.read_text(encoding="utf-8").splitlines()[line - 1].split(".", 1)[1].strip()
        files.append((number, title, relative))
    return sorted(files)


def priority_files(root, differences, notes):
    """The scored rows of each docs/priorities/<TASK>.md (decision 832), as
    dicts, and whether the file was merged back. A file not written in the
    fixed form is a difference."""
    import datetime
    directory = pathlib.Path(root) / PRIORITIES
    found = []
    if not directory.is_dir():
        return found
    columns = [name for name, _ in WEIGHTS]
    for path in sorted(directory.glob("*.md")):
        relative = f"{PRIORITIES}/{path.name}"
        if path.name == "README.md":
            continue
        if not PRIORITY_NAME.fullmatch(path.stem):
            differences.append(f"{relative} 的檔名不是工作名（大寫英數與連字號，例如 E200-REDO.md）")
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        match = PRIORITY_HEADING.match(lines[0]) if lines else None
        if not match:
            differences.append(f"{relative} 第一行應該是「# <工作名>（YYYY-MM-DD，來源）」，例如「# E200-REDO（2026-11-17，#2367）」")
            continue
        task, year, month, day, source = match.groups()
        if task != path.stem:
            differences.append(f"{relative} 的標題是 {task}，檔名應該是 {task}.md")
            continue
        try:
            datetime.date(int(year), int(month), int(day))
        except ValueError:
            differences.append(f"{relative} 的日期 {year}-{month}-{day} 不存在")
            continue
        pull = re.search(r"#(\d+)", source)
        if not pull:
            notes.append(f"{relative} 的來源沒有 PR 號（#N），開了 PR 後補上")
        merged = next((line[len(MERGED):].strip() for line in lines if line.startswith(MERGED)), None)
        rows, header, problems = [], None, False
        for number, line in enumerate(lines, 1):
            if not line.startswith("|"):
                header = None
                continue
            cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
            if all(re.fullmatch(r":?-+:?", cell) for cell in cells if cell):
                continue
            if header is None:
                header = cells if all(name in cells for name in ["項目", *columns, "加權"]) else []
                continue
            if not header:
                continue
            row = dict(zip(header, cells))
            item = row.get("項目", "")
            scores = []
            for name in columns:
                value = row.get(name, "")
                if not re.fullmatch(r"[1-5]", value):
                    differences.append(f"{relative} 第 {number} 行「{item}」的{name}分是 {value or '（空）'}，要是 1–5 的整數")
                    problems = True
                    break
                scores.append(int(value))
            else:
                total = sum(score * weight for score, (_, weight) in zip(scores, WEIGHTS))
                expected = f"{total // 100}.{total % 100:02d}"
                if row.get("加權", "") != expected:
                    differences.append(f"{relative} 第 {number} 行「{item}」的加權寫 {row.get('加權', '') or '（空）'}，照 §19 的權重是 {expected}")
                    problems = True
                status = next((value for key, value in row.items() if "狀態" in key), "")
                rows.append({"task": task, "pull": pull.group(1) if pull else None, "item": item,
                             "scores": scores, "weighted": expected, "total": total, "status": status})
        if not rows and not problems:
            differences.append(f"{relative} 沒有評分表（欄位要有 項目、{'、'.join(columns)}、加權）")
            continue
        found.append((relative, merged, rows))
    return found


def is_bug(item):
    return item.strip("* ").lower().startswith("bug")


def priorities(root, mark=None):
    """The rows of the priority files not merged back yet, bugs first, then
    by weighted score, player, developer and railway fan (§19's ties), as a
    table to paste into the priority list. With `mark`, each of those files
    gets the line 「併回：<mark>（date）」 under its heading."""
    import datetime
    root = pathlib.Path(root)
    differences, notes = [], []
    files = [entry for entry in priority_files(root, differences, notes) if entry[1] is None]
    rows = [row for _, _, found in files for row in found]
    rows.sort(key=lambda row: (not is_bug(row["item"]), -row["total"], -row["scores"][0], -row["scores"][1], -row["scores"][3]))
    print(f"還沒併回的評分檔 {len(files)} 個、{len(rows)} 列" + ("：" if files else "。"))
    if rows:
        print()
        print("| 名次 | 項目 | 來源 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 狀態 |")
        print("| --: | --- | --- | --: | --: | --: | --: | --: | --: | --- |")
        for place, row in enumerate(rows, 1):
            source = f"[{row['task']}](../priorities/{row['task']}.md)" + (f"（#{row['pull']}）" if row["pull"] else "")
            scores = " | ".join(map(str, row["scores"]))
            print(f"| {place} | {row['item']} | {source} | {scores} | {row['weighted']} | {row['status']} |")
    for line in differences:
        print(f"- {line}", file=sys.stderr)
    if mark:
        today = datetime.date.today().isoformat()
        for relative, _, _ in files:
            path = root / relative
            lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
            lines[1:1] = ["\n", f"{MERGED}{mark}（{today}）\n"]
            path.write_text("".join(lines), encoding="utf-8")
            print(f"已標記 {relative}：{MERGED}{mark}", file=sys.stderr)
    return 1 if differences else 0


def index_rows(text):
    """(number, title) of each row of OVERVIEW §9's table, in order."""
    return [(int(row[0]), row[1] if len(row) > 1 else "") for row in table_rows(section(text, 9)) if row and row[0].isdigit()]


def json_count(directory):
    return sum(1 for path in directory.glob("*.json") if path.is_file()) if directory.is_dir() else None


def descents(numbers, name):
    """Each number that comes after a larger one."""
    notes = []
    for previous, current in zip(numbers, numbers[1:]):
        if current[0] < previous[0]:
            notes.append(f"{name}：{current[0]} 排在 {previous[0]} 之後（第 {current[1]} {'行' if name == 'ARCHITECTURE' else '列'}）")
    return notes


def duplicates(numbers):
    seen, twice = set(), []
    for number in numbers:
        if number in seen and number not in twice:
            twice.append(number)
        seen.add(number)
    return twice


def compare(root):
    """(table, differences, notes) for the repository at `root`."""
    root = pathlib.Path(root)
    differences, notes = [], []

    def read(relative):
        path = root / relative
        if not path.is_file():
            differences.append(f"找不到 {relative}")
            return ""
        return path.read_text(encoding="utf-8")

    overview, architecture = read(OVERVIEW), read(ARCHITECTURE)
    stated = overview_numbers(overview)
    found, continued = headings(architecture)
    files = decision_files(root, differences)
    priority_files(root, differences, notes)
    filed = [number for number, _, _ in files]
    numbers = [number for number, _ in found] + filed
    actual = {
        "save_version": first(r"static let currentVersion\s*=\s*(\d+)", read(SAVED_GAME)),
        "save_fixtures": json_count(root / "SaveFixtures"),
        "golden_schema": first(r"static let schemaVersion\s*=\s*(\d+)", read(GOLDEN_SCENARIO)),
        "golden_fixtures": json_count(root / "GoldenScenarios"),
        "replay_fixtures": json_count(root / "ReplayFixtures"),
        "last_decision": max(numbers) if numbers else None,
    }
    items = [
        ("save_version", "存檔版本", "SavedGame.currentVersion"),
        ("save_fixtures", "存檔 fixture 個數", "SaveFixtures/*.json"),
        ("golden_schema", "golden schema", "GoldenScenario.schemaVersion"),
        ("golden_fixtures", "golden 個數", "GoldenScenarios/*.json"),
        ("replay_fixtures", "replay 個數", "ReplayFixtures/*.json"),
        ("last_decision", "最後的決策", "ARCHITECTURE 與 docs/decisions/ 最大的 ### N."),
    ]
    table = []
    for key, name, source in items:
        doc, code = stated[key], actual[key]
        if key == "last_decision" and doc is None and code is not None:
            table.append((name, doc, source, code, "不列（見 §9）"))
            continue
        if doc is None or code is None:
            result = "讀不到"
        else:
            result = "一致" if doc == code else "不一致"
        if result != "一致":
            differences.append(f"{name}：OVERVIEW §2 寫 {doc if doc is not None else '（讀不到）'}，{source} 是 {code if code is not None else '（讀不到）'}")
        table.append((name, doc, source, code, result))

    for number in duplicates([number for number, _ in found]):
        lines = "、".join(str(line) for n, line in found if n == number)
        differences.append(f"ARCHITECTURE 的 ### {number}. 出現不只一次（第 {lines} 行）")
    for number in sorted({number for number, _ in found if number >= FIRST_FILED}):
        differences.append(f"決策 {number} 寫在 ARCHITECTURE；{FIRST_FILED} 起每個決策寫在 {DECISIONS}/{number}.md")
    for number in sorted(set(filed) & {number for number, _ in found}):
        differences.append(f"決策 {number} 同時在 ARCHITECTURE 與 {DECISIONS}/{number}.md")
    indexed = index_rows(overview)
    rows = [number for number, _ in indexed]
    # A row the index itself marks as never used ("（保留後沒有使用）")
    # stands for a number with no heading.
    unused = {number for number, title in indexed if UNUSED in title}
    for number in duplicates(rows):
        differences.append(f"決策索引（OVERVIEW §9）的 {number} 不只一列")
    for number in sorted({number for number, _ in found if number < FIRST_FILED} - set(rows)):
        notes.append(f"決策 {number} 還沒進決策索引（OVERVIEW §9；遊戲規劃合併後補）")
    for number in sorted(set(rows) - set(numbers) - unused):
        differences.append(f"決策索引（OVERVIEW §9）有 {number}，ARCHITECTURE 沒有 ### {number}.")
    for number in sorted(unused & set(numbers)):
        differences.append(f"決策索引（OVERVIEW §9）寫 {number} 沒有使用，ARCHITECTURE 卻有 ### {number}.")
    for number in sorted(unused - set(numbers)):
        notes.append(f"決策索引（OVERVIEW §9）把 {number} 列為保留後沒有使用")

    for number in sorted(set(filed) & set(rows)):
        notes.append(f"決策 {number} 是 {DECISIONS}/{number}.md，索引（OVERVIEW §9）不用再列")
    notes += descents(found, "ARCHITECTURE")
    notes += descents([(number, row) for row, number in enumerate(rows, 1)], "決策索引")
    if numbers:
        missing = sorted(set(range(1, max(numbers) + 1)) - set(numbers))
        if missing:
            notes.append("ARCHITECTURE 沒有這些號碼：" + "、".join(map(str, missing)))
    for title, line in continued:
        notes.append(f"續篇標題 ### {title}.（第 {line} 行），不算重複")
    return table, differences, notes


def index(root):
    """The whole decision index: OVERVIEW §9's rows and the decision files."""
    root = pathlib.Path(root)
    differences = []
    overview = (root / OVERVIEW).read_text(encoding="utf-8") if (root / OVERVIEW).is_file() else ""
    rows = dict(index_rows(overview))
    for number, title, path in decision_files(root, differences):
        rows.setdefault(number, f"{title}（`{path}`）")
    print("| 決策 | 標題 |")
    print("| --: | --- |")
    for number in sorted(rows):
        print(f"| {number} | {rows[number]} |")
    for line in differences:
        print(f"- {line}", file=sys.stderr)
    return 0


def report(root):
    table, differences, notes = compare(root)
    print("| 項目 | OVERVIEW §2 | 程式／檔案 | 實際 | 結果 |")
    print("| --- | --: | --- | --: | --- |")
    for name, doc, source, code, result in table:
        print(f"| {name} | {doc if doc is not None else '—'} | `{source}` | {code if code is not None else '—'} | {result} |")
    print()
    print(f"差異 {len(differences)} 項" + ("：" if differences else "。"))
    for line in differences:
        print(f"- {line}")
    print(f"附註 {len(notes)} 項（不算失敗）" + ("：" if notes else "。"))
    for line in notes:
        print(f"- {line}")
    return differences


# MARK: - Self-test

def write_repository(root, *, overview_save="63", decisions="1–2、4（3 沒有使用，#5）。之後以 #231 為準", architecture_extra="", index_extra="", replay_reports=True, decision_files=None, priority_files=None):
    """A small repository whose numbers all agree unless told otherwise."""
    root = pathlib.Path(root)
    files = {
        OVERVIEW: f"""# 總覽

## 2. 現況數字

| 項目 | 現在 | 在哪裡 |
| --- | --- | --- |
| 存檔版本 | {overview_save}（說明，決策 2）；每個版本一個存檔 fixture，共 2 個 | `SavedGame.currentVersion` |
| golden | schema 74（車站商業，#595），`GoldenScenarios/` 裡 3 個 JSON | `GoldenScenarios/` |
| replay | 1 個指令紀錄（含 `a.json`，#468） | `ReplayFixtures/` |
| 決策 | {decisions} | `docs/ARCHITECTURE.md` |

## 9. 決策索引

| 決策 | 標題 |
| --: | --- |
| 1 | 一 |
| 2 | 二 |
| 3 | （保留後沒有使用） |
| 4 | 四 |
{index_extra}
""",
        ARCHITECTURE: f"""# 架構

### 內部

### 1. 一

```
### 9. 程式碼裡的範例不算
```

### 2. 二

### 2（續）. 二的續篇

### 4. 四
{architecture_extra}
## 目前規則摘要
""",
        SAVED_GAME: "struct SavedGame {\n    public static let currentVersion = 63\n}\n",
        GOLDEN_SCENARIO: "struct GoldenScenario {\n    static let schemaVersion = 74\n}\n",
        "SaveFixtures/v1.json": "{}",
        "SaveFixtures/v2.json": "{}",
        "SaveFixtures/README.md": "",
        "GoldenScenarios/a.json": "{}",
        "GoldenScenarios/b.json": "{}",
        "GoldenScenarios/c.json": "{}",
        "ReplayFixtures/a.json": "{}",
    }
    if replay_reports:
        files["ReplayFixtures/Reports/report.json"] = "{}"
    for name, content in (decision_files or {}).items():
        files[f"{DECISIONS}/{name}"] = content
    for name, content in (priority_files or {}).items():
        files[f"{PRIORITIES}/{name}"] = content
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


PRIORITY_EXAMPLE = """# E200-REDO（2026-11-17，#2367）

E200 重做之後留下的。

| 順位 | 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 | 狀態、注意 |
| --: | --- | --: | --: | --: | --: | --: | --: | --- |
| 1 | E200 的菱形集電弓 | 1 | 4 | 2 | 4 | 1 | 2.35 | 未派 |
| 2 | E200 側面的通風百葉 | 1 | 3 | 3 | 3 | 1 | 2.10 | 未派 |

五方：
- 玩家：拉遠後幾乎看不出來。
"""


def selftest():
    cases = []

    def case(name, **options):
        with tempfile.TemporaryDirectory() as directory:
            write_repository(directory, **options)
            table, differences, notes = compare(directory)
            cases.append(name)
            return table, differences, notes

    table, differences, notes = case("all agree")
    assert differences == [], differences
    assert [row[4] for row in table] == ["一致"] * 6, table
    assert [row[1] for row in table] == [63, 2, 74, 3, 1, 4], table
    assert "ARCHITECTURE 沒有這些號碼：3" in notes, notes
    assert "決策索引（OVERVIEW §9）把 3 列為保留後沒有使用" in notes, notes
    assert any("續篇標題 ### 2（續）." in note for note in notes), notes

    _, differences, _ = case("save version differs", overview_save="62")
    assert differences == ["存檔版本：OVERVIEW §2 寫 62，SavedGame.currentVersion 是 63"], differences

    _, differences, _ = case("a decision twice", architecture_extra="\n### 2. 又是二\n")
    assert any(line.startswith("ARCHITECTURE 的 ### 2. 出現不只一次") for line in differences), differences

    _, differences, notes = case("a decision not indexed is a note", architecture_extra="\n### 5. （預約）五\n")
    assert "決策 5 還沒進決策索引（OVERVIEW §9；遊戲規劃合併後補）" in notes, notes
    assert differences == ["最後的決策：OVERVIEW §2 寫 4，ARCHITECTURE 與 docs/decisions/ 最大的 ### N. 是 5"], differences

    table, differences, _ = case("the last decision left to the index", decisions="見決策索引（§9）", architecture_extra="\n### 5. 五\n")
    assert differences == [], differences
    assert table[5][4] == "不列（見 §9）", table

    _, differences, _ = case("an index row without its decision", index_extra="| 7 | 七 |")
    assert differences == ["決策索引（OVERVIEW §9）有 7，ARCHITECTURE 沒有 ### 7."], differences

    _, differences, notes = case("out of order is a note", architecture_extra="\n### 5. 五\n\n### 3. 三\n", index_extra="| 5 | 五 |\n| 6 | 六 |")
    assert differences == [
        "最後的決策：OVERVIEW §2 寫 4，ARCHITECTURE 與 docs/decisions/ 最大的 ### N. 是 5",
        "決策索引（OVERVIEW §9）有 6，ARCHITECTURE 沒有 ### 6.",
        "決策索引（OVERVIEW §9）寫 3 沒有使用，ARCHITECTURE 卻有 ### 3.",
    ], differences
    assert "ARCHITECTURE：3 排在 5 之後（第 19 行）" in notes, notes

    _, differences, notes = case("index out of order is a note", index_extra="| 2 | 又在四後面 |")
    assert differences == ["決策索引（OVERVIEW §9）的 2 不只一列"], differences
    assert "決策索引：2 排在 4 之後（第 5 列）" in notes, notes


    table, differences, notes = case("a decision in a file of its own", decisions="見決策索引（§9）", decision_files={
        "5.md": "### 5. 五\n\n本文\n\n### 5（續）. 五的續篇\n",
        "README.md": "### 9. 說明裡的標題不算\n",
    })
    assert differences == [], differences
    assert table[5][3] == 5, table
    assert not any("決策 5" in note for note in notes), notes

    _, differences, _ = case("a file named after another number", decisions="見決策索引（§9）", decision_files={"6.md": "### 5. 五\n"})
    assert differences == ["docs/decisions/6.md 的標題是 ### 5.，檔名應該是 5.md"], differences

    _, differences, _ = case("a file of two decisions", decisions="見決策索引（§9）", decision_files={"5.md": "### 5. 五\n\n### 6. 六\n"})
    assert differences == ["docs/decisions/5.md 有第二個決策標題 ### 6.（第 3 行）；一個檔一個決策"], differences

    _, differences, _ = case("a file with no heading", decision_files={"5.md": "五\n"})
    assert differences == ["docs/decisions/5.md 沒有 ### N. 標題"], differences

    _, differences, _ = case("a file named with leading zeros", decisions="見決策索引（§9）", decision_files={"05.md": "### 5. 五\n"})
    assert differences == [f"docs/decisions/05.md 的檔名不是決策號（應該是 <N>.md，例如 {FIRST_FILED}.md）"], differences

    _, differences, _ = case("a file not named by a number", decision_files={"5-draft.md": "### 5. 五\n"})
    assert differences == [f"docs/decisions/5-draft.md 的檔名不是決策號（應該是 <N>.md，例如 {FIRST_FILED}.md）"], differences

    _, differences, notes = case("a new decision appended to ARCHITECTURE", decisions="見決策索引（§9）", architecture_extra=f"\n### {FIRST_FILED}. 新的\n")
    assert differences == [f"決策 {FIRST_FILED} 寫在 ARCHITECTURE；{FIRST_FILED} 起每個決策寫在 docs/decisions/{FIRST_FILED}.md"], differences
    assert not any("還沒進決策索引" in note for note in notes), notes

    _, differences, _ = case("a decision both in ARCHITECTURE and a file", decisions="見決策索引（§9）", architecture_extra="\n### 5. 五\n", decision_files={"5.md": "### 5. 五\n"})
    assert differences == ["決策 5 同時在 ARCHITECTURE 與 docs/decisions/5.md"], differences


    # Decision 832: the rows a pull request scores are a file of their own.
    good = PRIORITY_EXAMPLE
    table, differences, notes = case("a priority file", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good, "README.md": "# 說明\n"})
    assert differences == [], differences
    assert not any("E200-REDO" in note for note in notes), notes

    _, differences, notes = case("a priority file with no pull request", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good.replace("，#2367）", "，E200 重做）")})
    assert differences == [], differences
    assert "docs/priorities/E200-REDO.md 的來源沒有 PR 號（#N），開了 PR 後補上" in notes, notes

    _, differences, _ = case("a priority file whose first line is not the heading", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": "E200 重做之後\n\n" + good})
    assert differences == ["docs/priorities/E200-REDO.md 第一行應該是「# <工作名>（YYYY-MM-DD，來源）」，例如「# E200-REDO（2026-11-17，#2367）」"], differences

    _, differences, _ = case("a priority file named after another task", decisions="見決策索引（§9）", priority_files={"E200.md": good})
    assert differences == ["docs/priorities/E200.md 的標題是 E200-REDO，檔名應該是 E200-REDO.md"], differences

    _, differences, _ = case("a priority file not named like a task", decisions="見決策索引（§9）", priority_files={"e200 redo.md": good})
    assert differences == ["docs/priorities/e200 redo.md 的檔名不是工作名（大寫英數與連字號，例如 E200-REDO.md）"], differences

    _, differences, _ = case("a priority file with an impossible date", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good.replace("2026-11-17", "2026-11-31")})
    assert differences == ["docs/priorities/E200-REDO.md 的日期 2026-11-31 不存在"], differences

    _, differences, _ = case("a priority file with no score table", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good.split("| 項目")[0]})
    assert differences == ["docs/priorities/E200-REDO.md 沒有評分表（欄位要有 項目、玩家、開發、美術、鐵道迷、音樂、加權）"], differences

    _, differences, _ = case("a score out of range", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good.replace("| 1 | 4 | 2 | 4 | 1 | 2.35 |", "| 1 | 6 | 2 | 4 | 1 | 2.85 |")})
    assert differences == ["docs/priorities/E200-REDO.md 第 7 行「E200 的菱形集電弓」的開發分是 6，要是 1–5 的整數"], differences

    _, differences, _ = case("a weighted score that does not add up", decisions="見決策索引（§9）", priority_files={"E200-REDO.md": good.replace("2.35", "2.40")})
    assert differences == ["docs/priorities/E200-REDO.md 第 7 行「E200 的菱形集電弓」的加權寫 2.40，照 §19 的權重是 2.35"], differences

    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory, priority_files={
            "E200-REDO.md": good,
            "OLD.md": "# OLD（2026-11-16，#2300）\n\n併回：NEXT_PRIORITIES §29.27（2026-11-17）\n\n| 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |\n| --- | --: | --: | --: | --: | --: | --: |\n| 早就併回的 | 5 | 5 | 5 | 5 | 5 | 5.00 |\n",
            "FIX.md": "# FIX（2026-11-17，#2380）\n\n| 項目 | 玩家 | 開發 | 美術 | 鐵道迷 | 音樂 | 加權 |\n| --- | --: | --: | --: | --: | --: | --: |\n| bug：低分的錯 | 1 | 1 | 1 | 1 | 1 | 1.00 |\n",
        })
        cases.append("--priorities lists what is not merged back, bugs first")
        import contextlib, io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            assert main(["--priorities", "--root", directory]) == 0
        lines = [line for line in out.getvalue().splitlines() if line.startswith("| ") and line[2].isdigit()]
        assert [line.split(" | ")[1] for line in lines] == ["bug：低分的錯", "E200 的菱形集電弓", "E200 側面的通風百葉"], out.getvalue()
        assert "早就併回的" not in out.getvalue(), out.getvalue()
        assert "[E200-REDO](../priorities/E200-REDO.md)（#2367）" in lines[1], lines[1]
        cases.append("--mark records where the files went")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            assert main(["--priorities", "--mark", "NEXT_PRIORITIES §29.30", "--root", directory]) == 0
        text = (pathlib.Path(directory) / PRIORITIES / "E200-REDO.md").read_text(encoding="utf-8")
        assert text.splitlines()[2].startswith("併回：NEXT_PRIORITIES §29.30（"), text
        assert compare(directory)[1] == [], compare(directory)[1]
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            main(["--priorities", "--root", directory])
        assert "E200" not in out.getvalue() and "低分" not in out.getvalue(), out.getvalue()

    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory, decision_files={"5.md": "### 5. 五\n"})
        cases.append("--index lists the rows and the files")
        import contextlib, io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            index(directory)
        assert out.getvalue().splitlines()[-2:] == ["| 4 | 四 |", "| 5 | 五（`docs/decisions/5.md`） |"], out.getvalue()

    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory)
        (pathlib.Path(directory) / SAVED_GAME).unlink()
        table, differences, _ = compare(directory)
        cases.append("a file missing")
        assert f"找不到 {SAVED_GAME}" in differences and table[0][4] == "讀不到", differences

    with tempfile.TemporaryDirectory() as directory:
        write_repository(directory, overview_save="62")
        cases.append("--check exits 1 on a difference")
        assert main(["--check", "--root", directory], quiet=True) == 1
        write_repository(directory)
        assert main(["--check", "--root", directory], quiet=True) == 0
        write_repository(directory, overview_save="62")
        assert main(["--root", directory], quiet=True) == 0, "without --check it only reports"

    print(f"selftest：{len(cases)} 個情境都通過")
    return 0


def main(argv=None, quiet=False):
    parser = argparse.ArgumentParser(description="OVERVIEW §2 的數字與程式、ARCHITECTURE 的決策號是否一致。")
    parser.add_argument("--check", action="store_true", help="有差異時 exit 1")
    parser.add_argument("--selftest", action="store_true", help="用假的 repository 測這支工具")
    parser.add_argument("--index", action="store_true", help="印出整份決策索引：OVERVIEW §9 加上 docs/decisions/ 的檔")
    parser.add_argument("--priorities", action="store_true", help="印出 docs/priorities/ 還沒併回優先清單的列，排好序（決策 832）")
    parser.add_argument("--mark", metavar="WHERE", help="和 --priorities 一起用：在那些檔的標題下寫「併回：WHERE（日期）」")
    parser.add_argument("--root", default=str(ROOT), help="repository 的根目錄（預設：這支工具所在的 repository）")
    options = parser.parse_args(argv)
    if options.selftest:
        return selftest()
    if options.index:
        return index(options.root)
    if options.priorities:
        return priorities(options.root, options.mark)
    if quiet:
        _, differences, _ = compare(options.root)
    else:
        differences = report(options.root)
    return 1 if options.check and differences else 0


if __name__ == "__main__":
    sys.exit(main())
