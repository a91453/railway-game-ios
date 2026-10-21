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
name is not its heading's number, a file with no heading, or a number that
is both a file and an ARCHITECTURE heading is a difference.

Python 3 standard library only:
    python3 -I tools/golden-checks/doc_numbers.py            # report
    python3 -I tools/golden-checks/doc_numbers.py --check    # exit 1 on a difference
    python3 -I tools/golden-checks/doc_numbers.py --selftest
    python3 -I tools/golden-checks/doc_numbers.py --index    # the whole decision index
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
SAVED_GAME = "Sources/GameCore/World/SavedGame.swift"
GOLDEN_SCENARIO = "Tests/GameCoreTests/GoldenScenario.swift"

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
        if not path.stem.isdigit():
            continue  # README.md and the like
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
    for number in sorted(set(filed) & {number for number, _ in found}):
        differences.append(f"決策 {number} 同時在 ARCHITECTURE 與 {DECISIONS}/{number}.md")
    indexed = index_rows(overview)
    rows = [number for number, _ in indexed]
    # A row the index itself marks as never used ("（保留後沒有使用）")
    # stands for a number with no heading.
    unused = {number for number, title in indexed if UNUSED in title}
    for number in duplicates(rows):
        differences.append(f"決策索引（OVERVIEW §9）的 {number} 不只一列")
    for number in sorted({number for number, _ in found} - set(rows)):
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

def write_repository(root, *, overview_save="63", decisions="1–2、4（3 沒有使用，#5）。之後以 #231 為準", architecture_extra="", index_extra="", replay_reports=True, decision_files=None):
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
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


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

    _, differences, _ = case("a decision both in ARCHITECTURE and a file", decisions="見決策索引（§9）", architecture_extra="\n### 5. 五\n", decision_files={"5.md": "### 5. 五\n"})
    assert differences == ["決策 5 同時在 ARCHITECTURE 與 docs/decisions/5.md"], differences

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
    parser.add_argument("--root", default=str(ROOT), help="repository 的根目錄（預設：這支工具所在的 repository）")
    options = parser.parse_args(argv)
    if options.selftest:
        return selftest()
    if options.index:
        return index(options.root)
    if quiet:
        _, differences, _ = compare(options.root)
    else:
        differences = report(options.root)
    return 1 if options.check and differences else 0


if __name__ == "__main__":
    sys.exit(main())
